# Offline address-range geocoder for Colorado, in R.
#
# A line-by-line port of pipeline/tiger_geocode.py (the geocoder that produced the published coordinates), so the
# geocoding step can be reproduced, inspected and re-run from R. Given the same inputs it returns the same coordinates
# and quality codes (see R/compare_with_python.R for the agreement check).
#
# Method
#   * Street segments: US Census TIGER/Line 2023 ADDRFEAT for the 64 Colorado counties (house-number ranges on each
#     side of every segment, with the ZIP code on each side).
#   * An address "1934 S BROADWAY, DENVER 80210" is parsed into number 1934, prefix direction S, street core BROADWAY,
#     type (ST/AVE/...). OCR slips in the house number (O->0, l->1, S->5 ...) and in street types are corrected; 'SO'/'NO'
#     are directions, 'NO' is a unit marker only when a number follows.
#   * Candidate segments share the street core and a ZIP, searched in this order: the listed ZIP, the other ZIPs of
#     the listed city, then ZIPs within 12 km (of the listed ZIP, or of the town's ZIPs when none is listed). The prefix
#     direction must match exactly in a first pass; a second, "direction-loose" pass is used only if the first fails, and
#     is flagged (_dirloose, approximate). On the Denver grid a prefixed address never lands on an unprefixed segment on
#     the wrong side of the Ellsworth/Broadway baselines ('4000 S KALAMATH' is never put on north Kalamath St).
#   * The house number is interpolated along the segment whose range contains it (preferring the side with the same
#     odd/even parity) and the point is moved 12 m off the centre-line toward that side (left/right of the from->to
#     direction). A segment of a different street type (16TH AVE vs 16TH ST) is used only as a last resort and flagged
#     _sufloose (approximate). If no range contains it, the nearest segment end within 300 numbers is used
#     (street_nearest). OCR-garbled street names are matched to the closest name in the same ZIPs (Indel similarity
#     >= 86, as rapidfuzz.fuzz.ratio; numbers in the name must agree, so 20TH never becomes 120TH); a direction letter
#     glued to the name ('SBANNOCK') is split off (_dirsplit) or recovered from the fuzzy match. A leading junk token
#     and then trailing tokens of the street name are dropped one by one (_trim) if the full name is not found; a name is
#     never trimmed down to a bare one-digit ordinal.
#   * An address printed without a direction whose number exists on both the plain and a directional version of the
#     street ('4300 LIPAN' / '4300 S LIPAN') is decided by the printed street type when the two are different streets
#     (24th St vs E 24th Ave: _dirtype), else by the printed ZIP's own ranges or the ZIP's (town's) half of the Denver grid
#     (_dirzip; the halves are derived from TIGER against the baselines); otherwise _dirambig, which is not placed.
#   * A match more than 15 km from the listed city is rejected. Failing everything, the ZIP centroid, then the city's
#     median ZIP centroid, is returned.
# Quality codes -> geocode level (as in pipeline/build_sites.py):
#   address         range_interp (optionally _cityzips, _dirzip, _dirtype), no fuzzy / nearzips / trim / dirloose / sufloose / dirsplit
#   address_approx  any other range_interp or street_nearest
#   zip_centroid    zip_centroid, and any code with _dirambig
#   city_centroid, none
#
# Usage
#   source("R/geocode_tiger.R")
#   g <- tiger_geocoder("work/tiger", "data/geocoder/zip_city.csv", "data/geocoder/zip_centroids.csv")
#   geocode_one(g, "1934 S BROADWAY", "DENVER", "80210")
#   geocode_many(g, data.frame(street = ..., city = ..., zip = ...))
# Download the TIGER files first with fetch_tiger_addrfeat("work/tiger") (needs internet; ~250 MB).

suppressPackageStartupMessages({ library(sf); library(data.table) })

# ---------------------------------------------------------------------------------------------- inputs
CO_COUNTY_FIPS <- sprintf("08%03d", c(1, 3, 5, 7, 9, 11, 13, 14, 15, 17, 19, 21, 23, 25, 27, 29, 31, 33, 35, 37, 39, 41, 43, 45,
                                     47, 49, 51, 53, 55, 57, 59, 61, 63, 65, 67, 69, 71, 73, 75, 77, 79, 81, 83, 85, 87, 89, 91,
                                     93, 95, 97, 99, 101, 103, 105, 107, 109, 111, 113, 115, 117, 119, 121, 123, 125))

fetch_tiger_addrfeat <- function(dir = "work/tiger", year = 2023) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (f in CO_COUNTY_FIPS) {
    shp <- file.path(dir, sprintf("tl_%d_%s_addrfeat.shp", year, f))
    if (file.exists(shp)) next
    url <- sprintf("https://www2.census.gov/geo/tiger/TIGER%d/ADDRFEAT/tl_%d_%s_addrfeat.zip", year, year, f)
    zf <- tempfile(fileext = ".zip"); utils::download.file(url, zf, mode = "wb", quiet = TRUE); utils::unzip(zf, exdir = dir)
  }
  invisible(dir)
}

# ---------------------------------------------------------------------------------------------- parsing
DIRS <- c(N = "N", S = "S", E = "E", W = "W", NORTH = "N", SOUTH = "S", EAST = "E", WEST = "W", NE = "NE", NW = "NW", SE = "SE", SW = "SW",
          WE = "W", WH = "W", WW = "W", WWW = "W", HW = "W", EE = "E", SS = "S", NN = "N", SO = "S", NO = "N", S0 = "S", N0 = "N")
TYPES <- c(ST = "ST", STREET = "ST", AVE = "AVE", AV = "AVE", AVENUE = "AVE", BLVD = "BLVD", BOULEVARD = "BLVD", RD = "RD", ROAD = "RD",
           DR = "DR", DRIVE = "DR", PL = "PL", PLACE = "PL", CT = "CT", COURT = "CT", WAY = "WAY", LN = "LN", LANE = "LN", CIR = "CIR",
           CIRCLE = "CIR", PKWY = "PKWY", PARKWAY = "PKWY", HWY = "HWY", HIGHWAY = "HWY", TER = "TER", TERRACE = "TER", TRL = "TRL",
           TRAIL = "TRL", LOOP = "LOOP", SQ = "SQ", ALY = "ALY", PIKE = "PIKE", EXPY = "EXPY", FWY = "FWY", RUN = "RUN", PT = "PT", XING = "XING",
           # OCR variants
           OR = "DR", ORIVE = "DR", SI = "ST", `5T` = "ST", PI = "PL", AVF = "AVE", AYE = "AVE", AVL = "AVE", BIVD = "BLVD", BLVO = "BLVD",
           `8LVD` = "BLVD", RO = "RD", R0 = "RD", CI = "CT", LA = "LN")
ORD <- c(FIRST = "1ST", SECOND = "2ND", THIRD = "3RD", FOURTH = "4TH", FIFTH = "5TH", SIXTH = "6TH", SEVENTH = "7TH", EIGHTH = "8TH",
         NINTH = "9TH", TENTH = "10TH")
OFFSET_M <- 12                       # distance of the point from the street centre-line, toward the matched side
ELLS <- 39.7163; BWAY <- -104.9875   # Denver grid baselines: Ellsworth Ave (N/S house numbers), Broadway (E/W)
GRID_KM <- 40                        # the Denver grid is only tested for ZIPs within this distance of the baselines' crossing
GRID_CORE_KM <- 25                   # within this distance every street is on the grid

ordfix <- function(t) {
  m <- regmatches(t, regexec("^(\\d+)(ST|ND|RD|TH)?$", t))[[1]]
  if (length(m) && m[3] == "" && nchar(t) <= 3) {
    n <- as.integer(t); suf <- if (n %% 100 >= 10 && n %% 100 <= 20) "TH" else switch(as.character(n %% 10), "1" = "ST", "2" = "ND", "3" = "RD", "TH")
    return(paste0(n, suf))
  }
  if (t %in% names(ORD)) ORD[[t]] else t
}

parse_name <- function(s) {
  toks <- strsplit(trimws(gsub("[^A-Z0-9 ]", " ", toupper(as.character(s)))), "\\s+")[[1]]
  toks <- toks[toks != ""]
  pre <- suf <- ""
  if (length(toks) > 1 && toks[1] %in% names(DIRS)) { pre <- DIRS[[toks[1]]]; toks <- toks[-1] }
  if (length(toks) > 1 && toks[length(toks)] %in% names(DIRS)) toks <- toks[-length(toks)]          # post-direction dropped
  if (length(toks) > 1 && toks[length(toks)] %in% names(TYPES)) { suf <- TYPES[[toks[length(toks)]]]; toks <- toks[-length(toks)] }
  toks <- vapply(toks, function(t) ordfix(sub("^(\\d+)N0$", "\\1ND", sub("^(\\d+)(5T|SI)$", "\\1ST", t))), "", USE.NAMES = FALSE)
  list(pre = pre, core = paste(toks, collapse = " "), suf = suf)
}

parse_addr <- function(s) {
  s <- trimws(toupper(as.character(s)))
  tk <- regmatches(s, regexpr(" ", s), invert = TRUE)[[1]]
  glued_dir <- grepl("^\\d+[NSEW]$", tk[1]) && length(tk) > 1 && !(strsplit(tk[2], " ", fixed = TRUE)[[1]][1] %in% names(DIRS))
  if (length(tk) && nchar(tk[1]) <= 6 && nchar(gsub("\\D", "", tk[1])) >= max(1, nchar(tk[1]) - 2) && !grepl("(ST|ND|RD|TH)$", tk[1]) &&
      !grepl("^I\\d+$", tk[1]) && !glued_dir) {           # OCR letters in the house number; not interstates (I70), not a glued direction ('1731S WADSWORTH')
    tk[1] <- chartr("OQDCcIlLSBZGo", "0000011158260", tk[1]); s <- paste(tk, collapse = " ")
  }
  # house number, an optional range end ('125-7'), an optional glued direction letter ('123N MAIN' = 123 N MAIN; any other glued letter is
  # a unit, '1234A'), an optional 1/2
  m <- regmatches(s, regexec("^(\\d+)(?:-\\d+)?([NSEW])?[A-Z]?(?:\\s*1/2)?\\s+(.*)$", s, perl = TRUE))[[1]]
  if (!length(m)) return(list(num = NA_real_, core = "", pre = "", suf = ""))
  rest0 <- m[4]
  if (nzchar(m[3]) && !(strsplit(rest0, " ", fixed = TRUE)[[1]][1] %in% names(DIRS))) rest0 <- paste(m[3], rest0)
  # unit markers; 'NO' only when a number that is not an ordinal follows ('BROADWAY NO 5', 'AVE NO 21'), so that 'NO 5TH ST' keeps its direction
  rest <- strsplit(rest0, "(?:\\b(?:STE|SUITE|UNIT|APT|BLDG|FL|RM)\\b|\\bNO\\b(?=\\s*\\d+(?!\\d*(?:ST|ND|RD|TH)\\b))|#)", perl = TRUE)[[1]]
  rest <- if (length(rest)) rest[1] else ""
  # a bare number after the street type is a unit ('2505 W 2ND AVE 7'); roads and highways keep their numbers
  rest <- sub("\\b(ST|STREET|AVE|AV|AVENUE|BLVD|BOULEVARD|DR|DRIVE|PL|PLACE|CT|COURT|WAY|LN|LANE|CIR|CIRCLE|PKWY|PARKWAY|TER|TERRACE)\\s+\\d+[A-Z]?\\s*$",
              "\\1", trimws(rest), perl = TRUE)
  p <- parse_name(rest)
  list(num = as.numeric(m[2]), core = p$core, pre = p$pre, suf = p$suf)
}

# ---------------------------------------------------------------------------------------------- index
seg_mid <- function(co) co[length(co[, 1]) %/% 2 + 1, ]        # == Python coords[len // 2]
km_from_cross <- function(lat, lon) 6371 * sqrt(((lat - ELLS) * pi / 180)^2 + ((lon - BWAY) * pi / 180 * cos(ELLS * pi / 180))^2)

grid_info <- function(dt) {
  # Denver-grid ZIPs and the half of the grid each lies in, from TIGER alone (see pipeline/tiger_geocode.py grid_info): a ZIP is on the
  # grid when its segments lie within GRID_KM of the Ellsworth/Broadway crossing and >= 95% of its prefixed segments agree with the
  # baselines (>= 5 on an axis). half["zip|NS"] is "N"/"S" when >= 80% of its segments (50 or more) lie on one side of Ellsworth, likewise EW.
  mids <- t(vapply(dt$coords, seg_mid, numeric(2))); i <- seq_len(nrow(dt))
  D <- rbind(data.table(i = i, z = dt$ZIPL, pre = dt$pre, lat = mids[, 2], lon = mids[, 1]), data.table(i = i, z = dt$ZIPR, pre = dt$pre, lat = mids[, 2], lon = mids[, 1]))
  D <- unique(D[!is.na(z) & z != ""], by = c("i", "z"))   # Python iterates the set {ZIPL, ZIPR}: a segment counts once per distinct ZIP
  D[, dk := km_from_cross(lat, lon)]; D[, south := lat < ELLS]; D[, east := lon > BWAY]
  gridzips <- character(); half <- list()
  for (zz in sort(unique(D$z), method = "radix")) {
    g <- D[z == zz]
    if (stats::median(g$dk) > GRID_KM) next
    ns <- g[pre %in% c("N", "S")]; ew <- g[pre %in% c("E", "W")]
    ok_ns <- nrow(ns) >= 5 && mean((ns$pre == "S") == ns$south) >= 0.95
    ok_ew <- nrow(ew) >= 5 && mean((ew$pre == "E") == ew$east) >= 0.95
    if (!(ok_ns || ok_ew)) next
    gridzips <- c(gridzips, zz)
    if (nrow(g) < 50) next
    s <- mean(g$south); e <- mean(g$east)
    if (s >= 0.8) half[[paste0(zz, "|NS")]] <- "S" else if (s <= 0.2) half[[paste0(zz, "|NS")]] <- "N"
    if (e >= 0.8) half[[paste0(zz, "|EW")]] <- "E" else if (e <= 0.2) half[[paste0(zz, "|EW")]] <- "W"
  }
  list(gridzips = gridzips, half = half)
}

tiger_geocoder <- function(tiger_dir = "work/tiger", zip_city_csv = "data/geocoder/zip_city.csv",
                           zip_centroid_csv = "data/geocoder/zip_centroids.csv", max_km = 15,
                           cache = file.path(tiger_dir, "tiger_index_r.rds")) {
  if (!is.null(cache) && file.exists(cache)) { g <- readRDS(cache); g$max_km <- max_km; if (!is.null(g$gridzips)) return(g) }
  files <- sort(Sys.glob(file.path(tiger_dir, "*_addrfeat.shp")))
  if (!length(files)) stop("no ADDRFEAT shapefiles in ", tiger_dir, "; run fetch_tiger_addrfeat()")
  segs <- lapply(files, function(f) {
    g <- st_transform(st_read(f, quiet = TRUE)[, c("FULLNAME", "LFROMHN", "LTOHN", "RFROMHN", "RTOHN", "ZIPL", "ZIPR")], 4326)
    g[!is.na(g$FULLNAME), ]
  })
  G <- do.call(rbind, segs)
  num <- function(x) suppressWarnings(as.numeric(gsub("\\D", "", as.character(x))))
  P <- lapply(G$FULLNAME, parse_name)
  dt <- data.table(FULLNAME = G$FULLNAME, LFROMHN = num(G$LFROMHN), LTOHN = num(G$LTOHN), RFROMHN = num(G$RFROMHN), RTOHN = num(G$RTOHN),
                   ZIPL = as.character(G$ZIPL), ZIPR = as.character(G$ZIPR),
                   pre = vapply(P, `[[`, "", "pre"), core = vapply(P, `[[`, "", "core"), suf = vapply(P, `[[`, "", "suf"))
  xy <- st_coordinates(G)                          # all vertices; last column indexes the feature
  fid <- xy[, ncol(xy)]
  co <- vector("list", nrow(dt)); spl <- split(seq_len(nrow(xy)), fid)
  for (k in names(spl)) co[[as.integer(k)]] <- xy[spl[[k]], 1:2, drop = FALSE]
  dt$coords <- co
  # (ZIP, core) -> segment rows, in row order
  key <- rbind(data.table(i = seq_len(nrow(dt)), z = dt$ZIPL, core = dt$core), data.table(i = seq_len(nrow(dt)), z = dt$ZIPR, core = dt$core))
  key <- unique(key[!is.na(z) & z != ""])[order(i)]
  idx <- split(key$i, paste(key$z, key$core, sep = "|"))
  cores <- lapply(split(key$core, key$z), function(x) sort(unique(x), method = "radix"))
  gi <- grid_info(dt)
  zc <- fread(zip_city_csv, colClasses = "character")
  zcent <- fread(zip_centroid_csv, colClasses = c(zip5 = "character"))
  zc_mat <- setNames(lapply(seq_len(nrow(zcent)), function(k) c(zcent$zlat[k], zcent$zlon[k])), zcent$zip5)
  A <- cbind(zcent$zlat, zcent$zlon) * pi / 180
  nbr <- lapply(seq_len(nrow(A)), function(k) {
    d <- 6371 * acos(pmin(1, pmax(-1, sin(A[k, 1]) * sin(A[, 1]) + cos(A[k, 1]) * cos(A[, 1]) * cos(A[, 2] - A[k, 2]))))
    o <- order(d); zcent$zip5[o][d[o] < 12 & zcent$zip5[o] != zcent$zip5[k]]
  })
  names(nbr) <- zcent$zip5
  g <- list(G = dt, idx = idx, cores = cores, gridzips = gi$gridzips, half = gi$half, city_zips = split(zc$z, zc$CITY_NAME),
            zip_city = setNames(zc$CITY_NAME, zc$z), zcent = zc_mat, nbr = nbr, max_km = max_km)
  if (!is.null(cache)) saveRDS(g, cache)            # building the index takes ~20 min; later calls load it in seconds
  g
}

# ---------------------------------------------------------------------------------------------- matching
interp_line <- function(co, t, side = "") {              # point at fraction t; moved OFFSET_M to the left/right (side) of the from->to direction
  c0 <- cos(co[1, 2] * pi / 180)
  dx <- diff(co); dxm <- dx; dxm[, 1] <- dxm[, 1] * c0    # metres-proportional steps
  d <- c(0, cumsum(sqrt(rowSums(dxm^2))))
  if (d[length(d)] == 0) return(co[1, ])
  x <- t * d[length(d)]
  k <- findInterval(x, d, left.open = TRUE)            # == numpy searchsorted(d, x) - 1 (side='left')
  k <- min(max(k, 1), length(d) - 1)
  f <- (x - d[k]) / max(d[k + 1] - d[k], 1e-12)
  p <- co[k, ] + f * (co[k + 1, ] - co[k, ])
  if (side %in% c("L", "R")) {
    ex <- dxm[k, 1]; ey <- dxm[k, 2]; n <- sqrt(ex^2 + ey^2)
    if (n > 0) { s <- OFFSET_M / (n * 111320) * (if (side == "L") 1 else -1); p <- p + c(-ey * s / c0, ex * s) }   # left of travel is (-ey, ex)
  }
  p
}

grid_conflict <- function(g, r, pre) {
  # a prefixed address may use an unprefixed segment only when that segment lies on the prefix's side of the Denver grid
  if (!(nzchar(pre) && !nzchar(r$pre))) return(FALSE)
  m <- seg_mid(r$coords[[1]]); d <- substr(pre, 1, 1)
  if (!((r$ZIPL %in% g$gridzips) || (r$ZIPR %in% g$gridzips) || km_from_cross(m[2], m[1]) < GRID_CORE_KM)) return(FALSE)
  (d == "S" && m[2] > ELLS) || (d == "N" && m[2] < ELLS) || (d == "W" && m[1] > BWAY) || (d == "E" && m[1] < BWAY)
}

place <- function(g, ids, num, pre, suf, strict = TRUE) {
  # returns list(pt, q, mpre, msuf): point, quality, prefix and type of the matched segment; NULL if nothing matched
  best <- NULL
  for (i in ids) {
    r <- g$G[i]
    if (nzchar(pre) && nzchar(r$pre) && r$pre != pre) next
    if (strict && r$pre != pre) next
    if (grid_conflict(g, r, pre)) next
    for (sd in c("L", "R")) {
      ab <- if (sd == "L") c(r$LFROMHN, r$LTOHN) else c(r$RFROMHN, r$RTOHN)
      a <- ab[1]; b <- ab[2]
      if (is.na(a) || is.na(b)) next
      if (min(a, b) <= num && num <= max(a, b)) {
        sufbad <- nzchar(suf) && nzchar(r$suf) && r$suf != suf            # street type disagrees (ST vs AVE)
        score <- (if (sufbad) 1 else 0) + (if (num %% 2 == a %% 2) 0 else 0.5)
        t <- if (a == b) 0.5 else (num - a) / (b - a)
        if (is.null(best) || score < best$score)
          best <- list(score = score, pt = interp_line(r$coords[[1]], t, sd), q = if (sufbad) "range_interp_sufloose" else "range_interp", mpre = r$pre, msuf = r$suf)
      }
    }
  }
  if (!is.null(best)) return(best)
  bd <- NULL
  for (i in ids) {
    r <- g$G[i]
    if (strict && r$pre != pre) next
    if (nzchar(pre) && nzchar(r$pre) && r$pre != pre) next
    if (grid_conflict(g, r, pre)) next
    for (sd in c("L", "R")) { ab <- if (sd == "L") c(r$LFROMHN, r$LTOHN) else c(r$RFROMHN, r$RTOHN)
      for (j in 1:2) {
        v <- ab[j]; if (is.na(v)) next
        dd <- abs(v - num)
        if (is.null(bd) || dd < bd$d) bd <- list(d = dd, pt = interp_line(r$coords[[1]], j - 1, sd), mpre = r$pre, msuf = r$suf)
      } }
  }
  if (!is.null(bd) && bd$d <= 300) return(list(pt = bd$pt, q = "street_nearest", mpre = bd$mpre, msuf = bd$msuf))
  NULL
}

indel_ratio <- function(a, b) {                         # rapidfuzz.fuzz.ratio
  d <- drop(utils::adist(a, b, costs = list(insertions = 1, deletions = 1, substitutions = 2)))
  100 * (1 - d / (nchar(a) + nchar(b)))
}

geocode_one <- function(g, street, city = "", zip5 = "") {
  p <- parse_addr(street)
  zip5 <- if (!is.na(zip5) && grepl("^8[01]\\d{3}$", zip5)) zip5 else ""
  city <- toupper(trimws(ifelse(is.na(city), "", city)))
  zips <- if (nzchar(zip5)) zip5 else character()
  cz <- if (nzchar(city) && city %in% names(g$city_zips)) g$city_zips[[city]] else NULL
  if (is.null(cz) && nzchar(zip5) && zip5 %in% names(g$zip_city) && g$zip_city[[zip5]] %in% names(g$city_zips)) cz <- g$city_zips[[g$zip_city[[zip5]]]]
  if (is.null(cz)) cz <- character()
  # neighbouring ZIPs (12 km): of the printed ZIP, or, when none is printed, of the town's ZIPs
  nb <- if (nzchar(zip5)) setdiff(if (!is.null(g$nbr[[zip5]])) g$nbr[[zip5]] else character(), cz)
        else setdiff(unique(unlist(g$nbr[cz], use.names = FALSE)), cz)
  variants <- character()
  if (nzchar(p$core)) { toks <- strsplit(p$core, " ")[[1]]
    variants <- p$core
    # a leading one-character token, or a one-digit ordinal in front of a street name when no direction was read, is junk: drop it first,
    # and never trim such a name down to the bare ordinal
    junk <- length(toks) > 1 && (nchar(toks[1]) == 1 || (!nzchar(p$pre) && grepl("^\\d(ST|ND|RD|TH)$", toks[1]) && grepl("^[A-Z]{4,}", toks[2])))
    if (junk) variants <- c(variants, paste(toks[-1], collapse = " "))
    for (k in rev(seq_len(length(toks) - 1))) { c2 <- paste(toks[1:k], collapse = " ")
      if (c2 %in% variants || (k == 1 && junk)) next
      variants <- c(variants, c2) }
    variants <- variants[seq_len(min(3, length(variants)))] }
  refz <- do.call(rbind, g$zcent[intersect(if (length(cz)) cz else zips, names(g$zcent))])
  ref <- if (!is.null(refz)) apply(refz, 2, stats::median) else NULL
  # a big town's outer ZIPs lie more than max_km from that median (Denver's 80249 is 25 km out), so a point is also accepted
  # when it is within max_km of the printed ZIP's own centroid (same rule as pipeline/tiger_geocode.py)
  zref <- if (nzchar(zip5)) g$zcent[[zip5]] else NULL
  dk <- function(pt, r) 6371 * sqrt(((pt[2] - r[1]) * pi / 180)^2 + ((pt[1] - r[2]) * pi / 180 * cos(r[1] * pi / 180))^2)
  far <- function(pt) !is.null(ref) && dk(pt, ref) > g$max_km && (is.null(zref) || dk(pt, zref) > g$max_km)
  out <- function(pt, q) list(lat = unname(pt[2]), lon = unname(pt[1]), quality = q)
  allzs <- sort(unique(c(zips, cz, unlist(g$nbr[if (length(zips)) zips else cz], use.names = FALSE))), method = "radix")
  cands <- function(zs, core) unlist(g$idx[paste(zs, core, sep = "|")], use.names = FALSE)
  holders <- function(zs, core) {                  # list(prefix -> street types) of the versions of this street holding the number in ZIPs zs
    h <- list()
    for (i in cands(zs, core)) { r <- g$G[i]
      for (ab in list(c(r$LFROMHN, r$LTOHN), c(r$RFROMHN, r$RTOHN)))
        if (!is.na(ab[1]) && !is.na(ab[2]) && min(ab) <= p$num && p$num <= max(ab)) { k <- r$pre; h[[if (nzchar(k)) k else "_"]] <- union(h[[if (nzchar(k)) k else "_"]], r$suf) } }
    h }
  dirs_of <- function(h) { n <- setdiff(names(h), "_"); if (length(n)) sort(n, method = "radix") else character() }
  zip_half <- function(axis) {                     # side of the Denver grid of the printed ZIP; else the town's, when all its ZIPs with a known side agree
    if (nzchar(zip5)) { v <- g$half[[paste0(zip5, "|", axis)]]; return(if (is.null(v)) "" else v) }
    hs <- unique(unlist(g$half[paste0(cz, "|", axis)], use.names = FALSE))
    if (length(hs) == 1) hs else "" }
  move_to <- function(core, d) {                   # the same number on the version of the street with prefix d, in the town or its neighbours
    r <- place(g, cands(allzs, core), p$num, d, p$suf, TRUE)
    if (!is.null(r) && startsWith(r$q, "range_interp") && !far(r$pt)) r else NULL }
  resolve <- function(pt, q, core, msuf) {
    allh <- holders(allzs, core); dirs <- dirs_of(allh)
    if (!length(dirs)) return(list(pt = pt, q = q))
    # different street types: the printed type decides; with none printed, Denver's avenues carry E/W, so plain means the street
    if (all(vapply(dirs, function(d) length(allh[[d]]) > 0 && !(msuf %in% allh[[d]]), TRUE))) {
      if (nzchar(p$suf) && p$suf != msuf) for (d in dirs) if (p$suf %in% allh[[d]]) {
        m <- move_to(core, d); if (!is.null(m) && m$q == "range_interp") return(list(pt = m$pt, q = paste0(m$q, "_dirtype"))) }
      return(list(pt = pt, q = paste0(q, "_dirtype")))
    }
    if (length(zips)) {                            # the printed ZIP's own ranges: which version holds the number there?
      own <- holders(zips, core); od <- dirs_of(own)
      if ("_" %in% names(own) && !length(od)) return(list(pt = pt, q = paste0(q, "_dirzip")))
      if (length(od) == 1 && !("_" %in% names(own))) { m <- move_to(core, od[1])
        if (!is.null(m) && (m$q == "range_interp" || m$q == q)) return(list(pt = m$pt, q = paste0(m$q, "_dirzip"))) }
    }
    decided <- NA
    for (d in dirs) {
      h <- zip_half(if (d %in% c("N", "S")) "NS" else "EW")
      if (!nzchar(h)) next
      if (h == d) { m <- move_to(core, d)          # the ZIP is on the directional street's side: use it
        if (!is.null(m) && (m$q == "range_interp" || m$q == q)) return(list(pt = m$pt, q = paste0(m$q, "_dirzip")))
        decided <- FALSE
      } else decided <- TRUE                        # the ZIP is on the plain street's side
    }
    list(pt = pt, q = paste0(q, if (isTRUE(decided)) "_dirzip" else "_dirambig"))
  }
  try_place <- function(ids, core_used, pre2, strict, tagq) {
    r <- place(g, ids, p$num, pre2, p$suf, strict)
    if (is.null(r) || far(r$pt)) return(NULL)
    pt <- r$pt; q <- r$q
    # plain street matched (or, the number being outside its ranges, its nearest end); a directional version may hold the number
    if (!nzchar(pre2) && (startsWith(q, "range_interp") || q == "street_nearest") && !nzchar(r$mpre)) { rr <- resolve(pt, q, core_used, r$msuf); pt <- rr$pt; q <- rr$q }
    else if (!nzchar(pre2) && startsWith(q, "range_interp") && nzchar(r$mpre)) {     # direction-free pass put a plain address on a directional street
      dirs <- dirs_of(holders(allzs, core_used))
      if (length(dirs) > 1) {
        h <- zip_half(if (substr(r$mpre, 1, 1) %in% c("N", "S")) "NS" else "EW")
        if (nzchar(h) && h %in% dirs) {
          if (h != r$mpre) { m <- move_to(core_used, h); if (!is.null(m)) { pt <- m$pt; q <- m$q } }
          q <- paste0(q, "_dirzip")
        } else q <- paste0(q, "_dirambig")
      }
    }
    out(pt, tagq(q))
  }
  if (!is.na(p$num)) for (strict in c(TRUE, FALSE)) for (vi in seq_along(variants)) {
    core <- variants[vi]
    for (tier in list(list(zips, ""), list(setdiff(cz, zips), "_cityzips"), list(nb, "_nearzips"))) {
      zs <- tier[[1]]; if (!length(zs)) next
      sfx <- paste0(tier[[2]], if (vi > 1) "_trim" else "", if (strict) "" else "_dirloose")
      ids <- cands(zs, core)
      if (length(ids)) { res <- try_place(ids, core, p$pre, strict, function(q) paste0(q, sfx)); if (!is.null(res)) return(res) }
      # a direction letter glued to the name ('SBANNOCK' for 'S BANNOCK'): split it off when the rest is a known street here
      if (!length(ids) && !nzchar(p$pre) && nchar(core) > 3 && substr(core, 1, 1) %in% c("N", "S", "E", "W") && substr(core, 2, 2) != " ") {
        ids2 <- cands(zs, substr(core, 2, nchar(core)))
        if (length(ids2)) { res <- try_place(ids2, substr(core, 2, nchar(core)), substr(core, 1, 1), strict, function(q) paste0(q, "_dirsplit", sfx)); if (!is.null(res)) return(res) }
      }
      allc <- unique(unlist(g$cores[zs], use.names = FALSE))
      dg <- regmatches(core, gregexpr("\\d+", core))[[1]]           # a fuzzy match may not change the street number
      if (length(allc)) allc <- allc[vapply(regmatches(allc, gregexpr("\\d+", allc)), function(x) identical(x, dg), TRUE)]
      if (length(allc)) {
        allc <- sort(allc, method = "radix")                           # Python (code-point) order
        sc <- indel_ratio(core, allc)
        if (max(sc) >= 86) {
          m <- allc[which.max(sc)]; pre2 <- p$pre
          if (!nzchar(p$pre) && m == substr(core, 2, nchar(core)) && substr(core, 1, 1) %in% c("N", "S", "E", "W")) pre2 <- substr(core, 1, 1)   # the 'misread' letter was the direction
          res <- try_place(cands(zs, m), m, pre2, strict, function(q) paste0("fuzzy_", q, sfx)); if (!is.null(res)) return(res)
        }
      }
    }
  }
  if (nzchar(zip5) && !is.null(g$zcent[[zip5]])) return(list(lat = g$zcent[[zip5]][1], lon = g$zcent[[zip5]][2], quality = "zip_centroid"))
  pts <- do.call(rbind, g$zcent[intersect(cz, names(g$zcent))])
  if (!is.null(pts)) return(list(lat = stats::median(pts[, 1]), lon = stats::median(pts[, 2]), quality = "city_centroid"))
  list(lat = NA_real_, lon = NA_real_, quality = "none")
}

geocode_level <- function(q) {
  ifelse(grepl("dirambig", q), "zip_centroid",
  ifelse(grepl("range_interp", q) & !grepl("fuzzy|nearzips|trim|dirloose|sufloose|dirsplit", q), "address",
  ifelse(grepl("range_interp|street_nearest", q), "address_approx",
  ifelse(q %in% c("zip_centroid", "city_centroid"), q, "none"))))
}

geocode_many <- function(g, df, street = "street", city = "city", zip = "zip", progress = TRUE) {
  n <- nrow(df); res <- vector("list", n)
  for (k in seq_len(n)) {
    res[[k]] <- geocode_one(g, df[[street]][k], df[[city]][k], df[[zip]][k])
    if (progress && k %% 2000 == 0) message(k, " / ", n)
  }
  df$lat <- vapply(res, `[[`, 0, "lat"); df$lon <- vapply(res, `[[`, 0, "lon")
  df$geo_quality <- vapply(res, `[[`, "", "quality"); df$geo_level <- geocode_level(df$geo_quality)
  df
}
