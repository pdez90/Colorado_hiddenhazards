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
#     type (ST/AVE/...). OCR slips in the house number (O->0, l->1, S->5 ...) and in street types are corrected.
#   * Candidate segments share the street core and a ZIP, searched in this order: the listed ZIP, the other ZIPs of
#     the listed city, then ZIPs within 12 km. The prefix direction must match exactly in a first pass; a second,
#     "direction-loose" pass is used only if the first fails, and is flagged (_dirloose, an approximate geocode).
#   * The house number is interpolated along the segment whose range contains it (preferring the side with the same
#     odd/even parity). A segment of a different street type (16TH AVE vs 16TH ST) is used only as a last resort and
#     flagged _sufloose (approximate). If no range contains it, the nearest segment end within 300
#     numbers is used (street_nearest). OCR-garbled street names are matched to the closest name in the same ZIPs
#     (Indel similarity >= 86, as rapidfuzz.fuzz.ratio; numbers in the name must agree, so 20TH never becomes 120TH). Trailing tokens of the street name are dropped one by one
#     (_trim) if the full name is not found.
#   * A match more than 15 km from the listed city is rejected. Failing everything, the ZIP centroid, then the city's
#     median ZIP centroid, is returned.
# Quality codes -> geocode level (as in pipeline/build_sites.py):
#   address         range_interp (optionally _cityzips), no fuzzy / nearzips / trim / dirloose / sufloose
#   address_approx  any other range_interp or street_nearest
#   zip_centroid, city_centroid, none
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
          WE = "W", WH = "W", WW = "W", WWW = "W", HW = "W", EE = "E", SS = "S", NN = "N")
TYPES <- c(ST = "ST", STREET = "ST", AVE = "AVE", AV = "AVE", AVENUE = "AVE", BLVD = "BLVD", BOULEVARD = "BLVD", RD = "RD", ROAD = "RD",
           DR = "DR", DRIVE = "DR", PL = "PL", PLACE = "PL", CT = "CT", COURT = "CT", WAY = "WAY", LN = "LN", LANE = "LN", CIR = "CIR",
           CIRCLE = "CIR", PKWY = "PKWY", PARKWAY = "PKWY", HWY = "HWY", HIGHWAY = "HWY", TER = "TER", TERRACE = "TER", TRL = "TRL",
           TRAIL = "TRL", LOOP = "LOOP", SQ = "SQ", ALY = "ALY", PIKE = "PIKE", EXPY = "EXPY", FWY = "FWY", RUN = "RUN", PT = "PT", XING = "XING",
           # OCR variants
           OR = "DR", ORIVE = "DR", SI = "ST", `5T` = "ST", PI = "PL", AVF = "AVE", AYE = "AVE", AVL = "AVE", BIVD = "BLVD", BLVO = "BLVD",
           `8LVD` = "BLVD", RO = "RD", R0 = "RD", CI = "CT", LA = "LN")
ORD <- c(FIRST = "1ST", SECOND = "2ND", THIRD = "3RD", FOURTH = "4TH", FIFTH = "5TH", SIXTH = "6TH", SEVENTH = "7TH", EIGHTH = "8TH",
         NINTH = "9TH", TENTH = "10TH")

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
  if (length(tk) && nchar(tk[1]) <= 6 && nchar(gsub("\\D", "", tk[1])) >= max(1, nchar(tk[1]) - 2) && !grepl("(ST|ND|RD|TH)$", tk[1]) &&
      !grepl("^I\\d+$", tk[1])) {                         # OCR letters in the house number; not interstates (I70)
    tk[1] <- chartr("OQDCcIlLSBZGo", "0000011158260", tk[1]); s <- paste(tk, collapse = " ")
  }
  m <- regmatches(s, regexec("^(\\d+)[A-Z]?(?:\\s*1/2)?\\s+(.*)$", s, perl = TRUE))[[1]]
  if (!length(m)) return(list(num = NA_real_, core = "", pre = "", suf = ""))
  rest <- strsplit(m[3], "(?:\\b(?:STE|SUITE|UNIT|NO|APT|BLDG|FL|RM)\\b|#)", perl = TRUE)[[1]]
  rest <- if (length(rest)) rest[1] else ""
  # a bare number after the street type is a unit ('2505 W 2ND AVE 7'); roads and highways keep their numbers
  rest <- sub("\\b(ST|STREET|AVE|AV|AVENUE|BLVD|BOULEVARD|DR|DRIVE|PL|PLACE|CT|COURT|WAY|LN|LANE|CIR|CIRCLE|PKWY|PARKWAY|TER|TERRACE)\\s+\\d+[A-Z]?\\s*$",
              "\\1", trimws(rest), perl = TRUE)
  p <- parse_name(rest)
  list(num = as.numeric(m[2]), core = p$core, pre = p$pre, suf = p$suf)
}

# ---------------------------------------------------------------------------------------------- index
tiger_geocoder <- function(tiger_dir = "work/tiger", zip_city_csv = "data/geocoder/zip_city.csv",
                           zip_centroid_csv = "data/geocoder/zip_centroids.csv", max_km = 15,
                           cache = file.path(tiger_dir, "tiger_index_r.rds")) {
  if (!is.null(cache) && file.exists(cache)) { g <- readRDS(cache); g$max_km <- max_km; return(g) }
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
  zc <- fread(zip_city_csv, colClasses = "character")
  zcent <- fread(zip_centroid_csv, colClasses = c(zip5 = "character"))
  zc_mat <- setNames(lapply(seq_len(nrow(zcent)), function(k) c(zcent$zlat[k], zcent$zlon[k])), zcent$zip5)
  A <- cbind(zcent$zlat, zcent$zlon) * pi / 180
  nbr <- lapply(seq_len(nrow(A)), function(k) {
    d <- 6371 * acos(pmin(1, pmax(-1, sin(A[k, 1]) * sin(A[, 1]) + cos(A[k, 1]) * cos(A[, 1]) * cos(A[, 2] - A[k, 2]))))
    o <- order(d); zcent$zip5[o][d[o] < 12 & zcent$zip5[o] != zcent$zip5[k]]
  })
  names(nbr) <- zcent$zip5
  g <- list(G = dt, idx = idx, cores = cores, city_zips = split(zc$z, zc$CITY_NAME), zip_city = setNames(zc$CITY_NAME, zc$z),
            zcent = zc_mat, nbr = nbr, max_km = max_km)
  if (!is.null(cache)) saveRDS(g, cache)            # building the index takes ~20 min; later calls load it in seconds
  g
}

# ---------------------------------------------------------------------------------------------- matching
interp_line <- function(co, t) {                       # distance along the segment in metres-proportional units
  dx <- diff(co); dx[, 1] <- dx[, 1] * cos(co[1, 2] * pi / 180)
  d <- c(0, cumsum(sqrt(rowSums(dx^2))))
  if (d[length(d)] == 0) return(co[1, ])
  x <- t * d[length(d)]
  k <- findInterval(x, d, left.open = TRUE)            # == numpy searchsorted(d, x) - 1 (side='left')
  k <- min(max(k, 1), length(d) - 1)
  f <- (x - d[k]) / max(d[k + 1] - d[k], 1e-12)
  co[k, ] + f * (co[k + 1, ] - co[k, ])
}

place <- function(g, ids, num, pre, suf, strict = TRUE) {
  best <- NULL; other_dir <- FALSE
  for (i in ids) {
    r <- g$G[i]
    if (nzchar(pre) && nzchar(r$pre) && r$pre != pre) next
    skip <- strict && r$pre != pre
    for (ab in list(c(r$LFROMHN, r$LTOHN), c(r$RFROMHN, r$RTOHN))) {
      a <- ab[1]; b <- ab[2]
      if (is.na(a) || is.na(b)) next
      if (min(a, b) <= num && num <= max(a, b)) {
        if (skip) { other_dir <- TRUE; next }           # a directional segment also holds this number
        sufbad <- nzchar(suf) && nzchar(r$suf) && r$suf != suf            # street type disagrees (ST vs AVE)
        score <- (if (sufbad) 1 else 0) + (if (num %% 2 == a %% 2) 0 else 0.5)
        t <- if (a == b) 0.5 else (num - a) / (b - a)
        if (is.null(best) || score < best$score)
          best <- list(score = score, pt = interp_line(r$coords[[1]], t), q = if (sufbad) "range_interp_sufloose" else "range_interp")
      }
    }
  }
  if (!is.null(best)) { if (!nzchar(pre) && other_dir) best$q <- paste0(best$q, "_dirambig"); return(best) }   # ambiguous: plain vs directional street
  bd <- NULL
  for (i in ids) {
    r <- g$G[i]
    if (strict && r$pre != pre) next
    if (nzchar(pre) && nzchar(r$pre) && r$pre != pre) next
    for (ab in list(c(r$LFROMHN, r$LTOHN), c(r$RFROMHN, r$RTOHN))) for (j in 1:2) {
      v <- ab[j]; if (is.na(v)) next
      dd <- abs(v - num)
      if (is.null(bd) || dd < bd$d) bd <- list(d = dd, pt = interp_line(r$coords[[1]], j - 1))
    }
  }
  if (!is.null(bd) && bd$d <= 300) return(list(pt = bd$pt, q = "street_nearest"))
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
  nb <- if (nzchar(zip5) && !is.null(g$nbr[[zip5]])) setdiff(g$nbr[[zip5]], cz) else character()
  variants <- character()
  if (nzchar(p$core)) { toks <- strsplit(p$core, " ")[[1]]
    for (k in length(toks):1) { variants <- c(variants, paste(toks[1:k], collapse = " ")); if (length(variants) >= 3) break } }
  refz <- do.call(rbind, g$zcent[intersect(if (length(cz)) cz else zips, names(g$zcent))])
  ref <- if (!is.null(refz)) apply(refz, 2, stats::median) else NULL
  far <- function(pt) !is.null(ref) && 6371 * sqrt(((pt[2] - ref[1]) * pi / 180)^2 + ((pt[1] - ref[2]) * pi / 180 * cos(ref[1] * pi / 180))^2) > g$max_km
  out <- function(pt, q) list(lat = unname(pt[2]), lon = unname(pt[1]), quality = q)
  other_direction <- function(core) {              # same number on a directional version of the street in the town or neighbouring ZIPs
    zs <- union(union(zips, cz), unlist(g$nbr[if (length(zips)) zips else cz], use.names = FALSE))
    for (i in unlist(g$idx[paste(sort(unique(zs), method = "radix"), core, sep = "|")], use.names = FALSE)) {
      r <- g$G[i]; if (!nzchar(r$pre)) next
      for (ab in list(c(r$LFROMHN, r$LTOHN), c(r$RFROMHN, r$RTOHN)))
        if (!is.na(ab[1]) && !is.na(ab[2]) && min(ab) <= p$num && p$num <= max(ab)) return(TRUE)
    }
    FALSE
  }
  if (!is.na(p$num)) for (strict in c(TRUE, FALSE)) for (vi in seq_along(variants)) {
    core <- variants[vi]
    for (tier in list(list(zips, ""), list(setdiff(cz, zips), "_cityzips"), list(nb, "_nearzips"))) {
      zs <- tier[[1]]; if (!length(zs)) next
      tag <- paste0(tier[[2]], if (vi > 1) "_trim" else "", if (strict) "" else "_dirloose")
      ids <- unlist(g$idx[paste(zs, core, sep = "|")], use.names = FALSE)
      if (length(ids)) { r <- place(g, ids, p$num, p$pre, p$suf, strict)
        if (!is.null(r) && !far(r$pt)) { if (!nzchar(p$pre) && r$q == "range_interp" && other_direction(core)) r$q <- "range_interp_dirambig"
          return(out(r$pt, paste0(r$q, tag))) } }
      allc <- unique(unlist(g$cores[zs], use.names = FALSE))
      dg <- regmatches(core, gregexpr("\\d+", core))[[1]]           # a fuzzy match may not change the street number
      if (length(allc)) allc <- allc[vapply(regmatches(allc, gregexpr("\\d+", allc)), function(x) identical(x, dg), TRUE)]
      if (length(allc)) {
        allc <- sort(allc, method = "radix")                           # Python (code-point) order
        sc <- indel_ratio(core, allc)
        if (max(sc) >= 86) {
          m <- allc[which.max(sc)]
          r <- place(g, unlist(g$idx[paste(zs, m, sep = "|")], use.names = FALSE), p$num, p$pre, p$suf, strict)
          if (!is.null(r) && !far(r$pt)) return(out(r$pt, paste0("fuzzy_", r$q, tag)))
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
  ifelse(grepl("range_interp", q) & !grepl("fuzzy|nearzips|trim|dirloose|sufloose|dirambig", q), "address",
  ifelse(grepl("range_interp|street_nearest", q), "address_approx",
  ifelse(q %in% c("zip_centroid", "city_centroid"), q, "none")))
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
