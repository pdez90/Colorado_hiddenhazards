# Changes to Denver's zone map, 1925-1956, read from the ordinances themselves.
#
#   Rscript R/fetch_denver_ordinances.R      (ordinance texts -> data/raw/ordinances/text/)
#   Rscript R/fetch_denver_property.R        (work/property/legal.csv: parcels' lot, block and subdivision)
#   Rscript R/rezoning_denver.R
#
# 1. Changes. Every "changed from <district> to <district>" in an ordinance amending the 1925 zone map (Ordinance No. 14, Series of 1925)
#    or, from 1955, the zoning chapter of the Revised Municipal Code ("changed from R-2 to B-4"), and every newly annexed area "classified
#    as" or "established as" a district. The scans' OCR is rough ("Reshlence HA11 District", "Cormnercial"), so district words are matched allowing two wrong
#    letters, and the letter in quotes is read from the characters that follow. Text after the publisher's affidavit (the newspaper
#    reprint of the same ordinance) is ignored, and a change repeated within an ordinance is kept once.
# 2. Place. The description that follows each change is searched for (a) lots, blocks and subdivisions ("Block 4, West Lawn Gardens"),
#    placed at today's parcels with the same subdivision and block in the Assessor's legal descriptions, and otherwise (b) the streets
#    named in the metes-and-bounds ("the center line of 47th Avenue... Milwaukee Street"), placed at the crossings of those streets on
#    today's TIGER streets (the tightest cluster of crossings, within 800 m of its medoid). Each change records how it was placed.
# 3. Context at that place: 1938 HOLC grade, 1929 zoning district, the 1940 and 1950 census tract (share Black, foreign-born, owner-
#    occupied; 2010 tract geography), and hazardous trades listed before the change within 400 m.
# 4. Summaries: changes by period and direction (residential to business or industrial, to residential, and so on), and the direction
#    of changes by HOLC grade and by the tract's share of Black residents.
# Outputs: data/results/rezoning/changes.csv (one row per change; ordinances are public records), summary tables and summary.md;
# app/data/rezoning_1925_1956.geojson and rezoning_*.csv.
for (p in c("data.table", "sf")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(data.table); library(sf) })
sf_use_s2(FALSE); UTM <- 26913; A <- "app/data"; TXD <- "data/raw/ordinances/text"; O <- "data/results/rezoning"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
FILES <- sort(list.files(TXD, "\\.txt$", full.names = TRUE)); if (!length(FILES)) stop("run Rscript R/fetch_denver_ordinances.R first")
# ---------------------------------------------------------------- 1. find the changes
ZW <- c(residence = "Residential", business = "Business or commercial", commercial = "Business or commercial", industrial = "Industrial")
fuzzy_zone <- function(x) {                                            # first word in x within two letters of a district type, and its letter
  w <- regmatches(x, gregexpr("[A-Za-z.;:]{6,13}", x))[[1]]; if (!length(w)) return(c(NA, NA))
  for (k in seq_along(w)) { t <- tolower(gsub("[^A-Za-z]", "", w[k])); if (nchar(t) < 6) next
    d <- adist(t, names(ZW)); j <- which.min(d); if (d[j] <= 2) {
      pos <- regexpr(w[k], x, fixed = TRUE); rem <- substr(x, pos + nchar(w[k]), nchar(x))
      rem <- sub("^\\W*(?:tt|11|1|n|u|H|\")?\\W*", "", rem, perl = TRUE); ch <- substr(rem, 1, 1)
      ch <- chartr("abcde38", "ABCDEBB", ch); return(c(names(ZW)[j], if (grepl("^[A-E]$", ch)) ch else NA)) } }
  c(NA, NA) }
new_code <- function(x) { m <- regmatches(x, regexpr("\\b([RBIPCM])\\s?[-~—–]\\s?([0-9OIl])", x, perl = TRUE)); if (!length(m)) return(NA_character_)
  paste0(substr(m, 1, 1), "-", chartr("OIl", "011", sub(".*[-~—–]\\s?", "", m))) }
group_of <- function(type, code) fcase(!is.na(code) & substr(code, 1, 1) == "R", "Residential", !is.na(code) & substr(code, 1, 1) %in% c("B", "C"), "Business or commercial",
                                       !is.na(code) & substr(code, 1, 1) %in% c("I", "M"), "Industrial", !is.na(code) & substr(code, 1, 1) == "P", "Parking",
                                       !is.na(type), ZW[type], default = NA_character_)
CHG <- "\\b\\S{0,2}ha[nm]g\\S{0,3}\\s+from\\s+"
parse_doc <- function(f) {
  raw <- paste(readLines(f, warn = FALSE), collapse = " "); t <- gsub("\\s+", " ", raw)
  cut <- regexpr("PUBLISHER'?S AFFIDAVIT|AFFIDAVIT OF PUBLICATION|Daily Journal|PUBLISHERS? AFFIDAVIT", t, ignore.case = TRUE)
  out <- list()
  for (part in unique(c(if (cut > 0) substr(t, 1, cut - 1), t))) {
    m <- gregexpr(CHG, part, perl = TRUE, ignore.case = TRUE)[[1]]
    a <- gregexpr("classified\\s+as\\s+an?\\s+|(?:is|be)\\s+established\\s+as\\s+(?:an?\\s+)?", part, perl = TRUE, ignore.case = TRUE)[[1]]   # land zoned for the first time (annexations)
    starts <- sort(c(if (m[1] > 0) m + attr(m, "match.length") else integer(0), if (a[1] > 0) -(a + attr(a, "match.length")) else integer(0)))
    ends <- abs(starts)
    for (k in seq_along(starts)) { s0 <- abs(starts[k]); s <- substr(part, s0, s0 + 140)
      if (starts[k] > 0) { sp <- regexpr("\\s(t[o0])\\s", s, perl = TRUE); if (sp < 0) next
        fr <- substr(s, 1, sp - 1); to <- substr(s, sp + 4, sp + 70) } else { fr <- ""; to <- substr(s, 1, 60) }
      fz <- if (nzchar(fr)) fuzzy_zone(fr) else c(NA, NA); tz <- fuzzy_zone(to); fc <- if (nzchar(fr)) new_code(fr) else NA; tc <- new_code(to)
      if (is.na(tz[1]) && is.na(tc)) next
      if (nzchar(fr) && is.na(fz[1]) && is.na(fc)) next
      nxt <- ends[ends > s0]; e <- min(c(nxt, s0 + 3000, nchar(part)))
      desc <- substr(part, s0, e); sec <- regexpr("SECTION\\s+[2-9]", desc, ignore.case = TRUE); if (sec > 200) desc <- substr(desc, 1, sec - 1)
      out[[length(out) + 1]] <- data.table(from_type = fz[1], from_letter = fz[2], from_code = fc, to_type = tz[1], to_letter = tz[2], to_code = tc,
                                           annexation = starts[k] < 0, desc = desc) }
    if (length(out)) break }                                             # the ordinance text itself; the reprint only if nothing was found
  if (!length(out)) return(NULL)
  d <- rbindlist(out); d[, ordinance := sub("\\.txt$", "", basename(f))]; d }
CH <- rbindlist(lapply(FILES, parse_doc), fill = TRUE)
CH[, year := as.integer(substr(ordinance, 1, 4))]
CH[, `:=`(from = fcase(annexation, "Newly annexed", !is.na(from_code), from_code, !is.na(from_type), paste(tools::toTitleCase(from_type), fifelse(is.na(from_letter), "?", from_letter)), default = NA_character_),
          to = fcase(!is.na(to_code), to_code, !is.na(to_type), paste(tools::toTitleCase(to_type), fifelse(is.na(to_letter), "?", to_letter)), default = NA_character_))]
CH[, `:=`(from_group = fifelse(annexation, "Newly annexed", group_of(from_type, from_code)), to_group = group_of(to_type, to_code))]
CH <- CH[!(from == to & !annexation)]
message(nrow(CH), " zone changes found in ", uniqueN(CH$ordinance), " of ", length(FILES), " ordinances")
# ---------------------------------------------------------------- 2. place them
TF <- "work/tiger/tl_2023_08031_addrfeat.shp"
if (!file.exists(TF)) { if (!requireNamespace("tigris", quietly = TRUE)) install.packages("tigris", repos = "https://cloud.r-project.org")
  dir.create("work/tiger", showWarnings = FALSE, recursive = TRUE); st_write(tigris::address_ranges("CO", "Denver", year = 2023), TF, quiet = TRUE) }
ORD <- c(FIRST = 1, SECOND = 2, THIRD = 3, FOURTH = 4, FIFTH = 5, SIXTH = 6, SEVENTH = 7, EIGHTH = 8, NINTH = 9, TENTH = 10, ELEVENTH = 11, TWELFTH = 12,
         THIRTEENTH = 13, FOURTEENTH = 14, FIFTEENTH = 15, SIXTEENTH = 16, SEVENTEENTH = 17, EIGHTEENTH = 18, NINETEENTH = 19, TWENTIETH = 20, THIRTIETH = 30, FORTIETH = 40)
TENS <- c(TWENTY = 20, THIRTY = 30, FORTY = 40, FIFTY = 50)
sfx <- function(n) paste0(n, ifelse(n %% 100 %in% 11:13, "TH", c("TH", "ST", "ND", "RD", rep("TH", 6))[n %% 10 + 1]))
st_base <- function(x) { x <- toupper(ifelse(is.na(x), "", x)); x <- gsub("\\(.*?\\)", " ", x); x <- gsub("[.,']", " ", x)
  for (t in names(TENS)) for (o in names(ORD)[1:9]) x <- gsub(paste0("\\b", t, "[- ]", o, "\\b"), sfx(TENS[[t]] + ORD[[o]]), x)
  for (o in names(ORD)) x <- gsub(paste0("\\b", o, "\\b"), sfx(ORD[[o]]), x)
  x <- gsub("\\b(\\d+)(ST|ND|RD|TH|D)?\\b", "\\1", x); x <- gsub("\\b(\\d+)\\b", "N\\1", x)
  x <- gsub("\\b(AVENUE|AVE|AV|STREET|ST|PLACE|PL|BOULEVARD|BLVD|COURT|CT|DRIVE|DR|LANE|LN|ROAD|RD|WAY|TERRACE|PARKWAY|PKWY|CIRCLE|CIR|PROPOSED|NOT OPENED|NORTH|SOUTH|EAST|WEST|S|N|E|W)\\b", " ", x)
  x <- gsub("\\bN(\\d+)\\b", "\\1", x); gsub("\\s+", " ", trimws(x)) }
RO <- st_transform(st_read(TF, quiet = TRUE), UTM); RO$base <- st_base(RO$FULLNAME); RO <- RO[RO$base != "", ]
dir_of <- function(x) { m <- regmatches(toupper(x), regexpr("^\\s*(NORTH|SOUTH|EAST|WEST|N|S|E|W)\\b", toupper(x))); d <- substr(trimws(m), 1, 1); d[!nzchar(d)] <- ""; out <- rep("", length(x)); out[grepl("^\\s*(NORTH|SOUTH|EAST|WEST|N|S|E|W)\\b", toupper(x))] <- d; out }
RO$dkey <- trimws(paste(dir_of(RO$FULLNAME), RO$base))
RO <- aggregate(RO["dkey"], by = list(b = RO$dkey), FUN = function(z) z[1]); RO$dkey <- RO$b; RO$b <- NULL; RO$base <- sub("^[NSEW] ", "", RO$dkey)
CX <- new.env()
crossings <- function(a, b) { k <- paste(sort(c(a, b)), collapse = "|"); if (!is.null(CX[[k]])) return(CX[[k]])
  sel <- function(k) if (grepl("^[NSEW] ", k)) RO[RO$dkey == k, ] else RO[RO$base == k, ]
  la <- sel(a); lb <- sel(b); m <- matrix(numeric(0), 0, 2)
  if (nrow(la) && nrow(lb)) { p <- suppressWarnings(st_intersection(st_geometry(la), st_geometry(lb))); if (length(p)) m <- st_coordinates(st_cast(st_sfc(p), "POINT"))[, 1:2, drop = FALSE] }
  CX[[k]] <- m; m }
STX <- "\\b(?:(?:North|South|East|West|N\\.|S\\.|E\\.|W\\.)\\s+)?([A-Z0-9][A-Za-z0-9']*(?:\\s[A-Z][A-Za-z']+)?)\\s+(?i:Street|Avenue|Boulevard|Place|Drive|Parkway|Way|Court|Road|Lane|St\\.|Ave\\.|Blvd\\.)"
street_names <- function(desc) { m <- regmatches(desc, gregexpr(STX, desc, perl = TRUE))[[1]]; if (!length(m)) return(character(0))
  k <- trimws(paste(dir_of(m), st_base(m))); k <- ifelse(k %in% RO$dkey, k, sub("^[NSEW] ", "", k))   # "West 50th Avenue" is W 50th, not E 50th
  k <- unique(k); k[nzchar(k) & (k %in% RO$dkey | k %in% RO$base)] }
place_streets <- function(desc) {
  nm <- street_names(desc); if (length(nm) < 2) return(NULL)
  P <- do.call(rbind, lapply(combn(nm, 2, simplify = FALSE), function(pr) crossings(pr[1], pr[2]))); if (is.null(P) || !nrow(P)) return(NULL)
  D <- as.matrix(dist(P)); md <- which.max(rowSums(D <= 800)); keep <- D[md, ] <= 800; Q <- P[keep, , drop = FALSE]
  list(x = mean(Q[, 1]), y = mean(Q[, 2]), n = nrow(Q), names = length(nm), spread = if (nrow(Q) > 1) max(dist(Q)) else 0) }
LEG <- "work/property/legal.csv"; SUBX <- NULL
ABBR <- c(HEIGHTS = "HTS", HGTS = "HTS", MOUNTAIN = "MTN", PLACE = "PL", ADDITION = "ADD", ADDN = "ADD", SUBDIVISION = "SUB", SUBD = "SUB", FILING = "FLG", FILG = "FLG",
          GARDENS = "GDNS", GARDEN = "GDN", TERRACE = "TER", AVENUE = "AVE", STREET = "ST", SQUARE = "SQ", NORTH = "N", SOUTH = "S", EAST = "E", WEST = "W",
          FIRST = "1ST", SECOND = "2ND", THIRD = "3RD", FOURTH = "4TH", FIFTH = "5TH", RESUBDIVISION = "RESUB", AMENDED = "AMD", BOULEVARD = "BLVD", HIGHLANDS = "HIGHLANDS", MOUNT = "MT", SAINT = "ST")
canon <- function(x) { x <- toupper(gsub("[^A-Za-z0-9 ]", " ", gsub("['’`]", "", x))); for (w in names(ABBR)) x <- gsub(paste0("\\b", w, "\\b"), ABBR[[w]], x); gsub("\\s+", " ", trimws(x)) }
GENERIC <- c("SUB", "ADD", "FLG", "RESUB", "AMD", "NO", "THE", "OF", "AND", "TO", "CITY", "DENVER", "CONDOS", "CONDO", "CONDOMINIUM", "CONDOMINIUMS", "TOWNHOMES", "UNIT", "BLDG", "APT", "PRK", "STR",
             "LOT", "LOTS", "BLK", "BLOCK", "BLOCKS", "POINT", "STREETS", "LINE", "CENTER", "FEET", "PT", "EXC", "EX", "FT", "REAR", "ALL", "AKA", "TH", "COM", "COR", "BEG", "INC", "LESS", "PLUS", "VAC", "VACATED", "ALLEY", "ADJ", "ST", "AVE")
legal_name <- function(x) { x <- canon(sub("\\b(EXC|EX|TH|COM|BEG|LESS|AKA)\\b.*$", "", toupper(x)))
  w <- strsplit(x, " ")[[1]]; w <- w[grepl("^[A-Z]{2,}$|^[0-9]+(ST|ND|RD|TH)$", w) & !w %in% GENERIC & !grepl("^(L|B|U|S|N|E|W)[0-9]", w)]
  paste(w, collapse = " ") }
if (file.exists(LEG)) {
  L <- fread(LEG, colClasses = "character")[!is.na(LEGAL_DESC) & nzchar(LEGAL_DESC)]
  L[, `:=`(x = as.numeric(SITUS_X_COORD), y = as.numeric(SITUS_Y_COORD))]; L <- L[!is.na(x) & x > 0]
  xy <- st_coordinates(st_transform(st_as_sf(L[, .(x, y)], coords = c("x", "y"), crs = 2877), UTM)); L[, `:=`(ux = xy[, 1], uy = xy[, 2])]
  L[, ld := toupper(gsub("\\s+", " ", LEGAL_DESC))]
  L[, blk := fifelse(grepl("\\bBLK\\s*[0-9]+|\\bB\\s?[0-9]+\\b", ld), sub("^.*?\\b(?:BLK\\s*|B\\s?)([0-9]+)\\b.*$", "\\1", ld, perl = TRUE), NA_character_)]
  L[, skey := vapply(ld, legal_name, "")]
  SUBX <- L[nchar(skey) >= 5, .(ux = median(ux), uy = median(uy), parcels = .N), by = .(skey, blk)]
  SUBS <- SUBX[, .(n = sum(parcels)), by = skey][n >= 3][order(-nchar(skey))]
  message(nrow(SUBS), " subdivision names in today's legal descriptions")
}
blocks_in <- function(d) { m <- regmatches(d, gregexpr("BLOCKS?\\s+([0-9]+)(?:\\s*(?:TO|-|THROUGH|THRU)\\s*([0-9]+))?", d, perl = TRUE))[[1]]
  unique(unlist(lapply(m, function(z) { n <- as.integer(regmatches(z, gregexpr("[0-9]+", z))[[1]]); if (length(n) == 2 && n[2] > n[1] && n[2] - n[1] < 60) seq(n[1], n[2]) else n[1] }))) }
# subdivisions are read only where the text names one after a block ("Block 4, Ivanhoe", "Lots 5 to 8, Block 56, Evanston, 2nd Filing",
# "Block 7 ... all in Sherman Subdivision"); the longest run of words that matches a subdivision in today's legal descriptions is used
SUBX_REF <- "(?i:blocks?)\\s+[0-9][0-9 ,&to-]*(?i:and\\s+[0-9]+)?\\s*(?:,|\\s(?i:of|in))\\s+(?:(?i:all\\s+in)\\s+)?([A-Z0-9][A-Za-z0-9'.]*(?:,?\\s+(?:to|of|the|and|[A-Z0-9][A-Za-z0-9'.]*)){0,7})"
place_subdiv <- function(desc) {
  if (is.null(SUBX)) return(NULL)
  d <- gsub("\\s+", " ", desc); m <- regmatches(d, gregexpr(SUBX_REF, d, perl = TRUE))[[1]]
  m2 <- regmatches(d, gregexpr("(?i:all\\s+in)\\s+([A-Z][A-Za-z0-9'.]*(?:\\s+(?:to|of|the|and|[A-Z0-9][A-Za-z0-9'.]*)){0,6})", d, perl = TRUE))[[1]]
  cands <- c(sub(SUBX_REF, "\\1", m, perl = TRUE), sub("^(?i:all\\s+in)\\s+", "", m2, perl = TRUE)); if (!length(cands)) return(NULL)
  hit <- unique(unlist(lapply(cands, function(cn) { w <- strsplit(legal_name(cn), " ")[[1]]; w <- w[nzchar(w)]
    for (k in rev(seq_along(w))) { key <- paste(w[1:k], collapse = " "); if (key %in% SUBS$skey) return(key) }; NULL })))
  if (!length(hit)) return(NULL)
  bl <- as.character(blocks_in(toupper(d)))
  P <- if (length(bl)) SUBX[skey %in% hit & blk %in% bl] else SUBX[0]; wb <- nrow(P) > 0; if (!nrow(P)) P <- SUBX[skey %in% hit]
  if (!nrow(P)) return(NULL)
  D <- as.matrix(dist(as.matrix(P[, .(ux, uy)]))); md <- which.max(rowSums(D <= 1500)); P <- P[D[md, ] <= 1500]
  list(x = weighted.mean(P$ux, P$parcels), y = weighted.mean(P$uy, P$parcels), n = nrow(P), names = length(hit), spread = if (nrow(P) > 1) max(dist(as.matrix(P[, .(ux, uy)]))) else 0,
       with_block = wb) }
PL <- rbindlist(lapply(seq_len(nrow(CH)), function(i) { d <- CH$desc[i]; s1 <- place_subdiv(d); s2 <- place_streets(d)
  agree <- if (!is.null(s1) && !is.null(s2)) round(sqrt((s1$x - s2$x)^2 + (s1$y - s2$y)^2)) else NA_real_
  # subdivision with its block first; then the crossings of the named streets; a subdivision named without a block last
  if (!is.na(agree) && agree > 1000) { s <- if (s2$n >= 2 || !isTRUE(s1$with_block)) s2 else s1; how <- "uncertain: subdivision and streets disagree by over 1 km"
  } else if (!is.null(s1) && isTRUE(s1$with_block)) { s <- s1; how <- if (!is.na(agree)) "subdivision and block (streets agree)" else "subdivision and block"
  } else if (!is.null(s2)) { s <- s2; how <- "street crossings" } else if (!is.null(s1)) { s <- s1; how <- "subdivision" } else s <- NULL
  if (is.null(s)) return(data.table(i = i, ux = NA_real_, uy = NA_real_, placed_by = "not placed", n_points = 0L, spread_m = NA_real_, m_between_methods = agree))
  data.table(i = i, ux = s$x, uy = s$y, placed_by = how, n_points = s$n, spread_m = round(s$spread), m_between_methods = agree) }))
CH <- cbind(CH, PL[, !"i"])
# dedupe: the same change repeated within an ordinance (e.g. quoted in the Board of Adjustment's letter)
CH[, near := 0]; CH <- CH[order(ordinance)]
CH[, dup := { r <- rep(FALSE, .N); if (.N > 1) for (a in 2:.N) for (b in 1:(a - 1)) if (!r[b] && from[a] == from[b] && to[a] == to[b] &&
  (is.na(ux[a]) || is.na(ux[b]) || sqrt((ux[a] - ux[b])^2 + (uy[a] - uy[b])^2) < 300)) { r[a] <- TRUE; break }; r }, by = ordinance]
CH <- CH[dup == FALSE][, c("near", "dup") := NULL]
print(CH[, .N, by = placed_by])
# ---------------------------------------------------------------- 3. context at the place
CH[, direction := fcase(annexation, paste("Annexed as", tolower(to_group)),
                        from_group == "Residential" & to_group == "Industrial", "Residential to industrial",
                        from_group == "Residential" & to_group == "Business or commercial", "Residential to business",
                        from_group == "Business or commercial" & to_group == "Industrial", "Business to industrial",
                        from_group %in% c("Industrial", "Business or commercial") & to_group == "Residential", "Business or industrial to residential",
                        from_group == "Industrial" & to_group == "Business or commercial", "Industrial to business",
                        from_group == to_group, paste("Within", tolower(from_group), "districts"), to_group == "Parking", "To parking", default = "Other")]
G <- CH[!is.na(ux)]; pts <- st_as_sf(G[, .(ux, uy)], coords = c("ux", "uy"), crs = UTM)
HOLC <- st_make_valid(st_transform(st_read(file.path(A, "holc_denver.geojson"), quiet = TRUE), UTM)); HOLC <- HOLC[HOLC$grade %in% c("A", "B", "C", "D"), "grade"]
G[, holc := { w <- st_within(pts, HOLC); vapply(w, function(i) if (length(i)) HOLC$grade[i[1]] else "Not graded", "") }]
Z29 <- st_make_valid(st_transform(st_read(file.path(A, "zoning_1929.geojson"), quiet = TRUE), UTM))
G[, zone_1929 := { w <- st_within(pts, Z29); vapply(w, function(i) if (length(i)) as.character(Z29$zone[i[1]]) else "Residence or business (not mapped)", "") }]
TR <- st_transform(st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE), UTM)
G[, GEOID := TR$GEOID[vapply(st_within(pts, TR), function(i) if (length(i)) i[1] else NA_integer_, 1L)]]
TP <- fread(file.path(A, "tract_panel.csv"), colClasses = c(GEOID = "character"))[census %in% c(1940, 1950), .(GEOID, census, p_black, p_fb, p_owner, pop)]
G[, census := fifelse(year < 1946, 1940L, 1950L)]
G <- merge(G, TP, by = c("GEOID", "census"), all.x = TRUE)
HS <- fread(file.path(A, "historical_sites.csv"))[fe_hazard %in% c(TRUE, "True") & precision != "town" & !is.na(lat) & town == "DENVER"]
hs <- st_transform(st_as_sf(HS[, .(first_year, lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)
G[, haz_trades_400m := { w <- st_is_within_distance(st_as_sf(.SD, coords = c("ux", "uy"), crs = UTM), hs, 400); vapply(seq_along(w), function(k) sum(HS$first_year[w[[k]]] <= year[k]), 1L) }, .SDcols = c("ux", "uy")]
ll <- st_coordinates(st_transform(st_as_sf(G[, .(ux, uy)], coords = c("ux", "uy"), crs = UTM), 4326)); G[, `:=`(lon = round(ll[, 1], 5), lat = round(ll[, 2], 5))]
CH <- merge(CH, G[, .(ordinance, desc, holc, zone_1929, GEOID, census, p_black, p_fb, p_owner, haz_trades_400m, lon, lat)], by = c("ordinance", "desc"), all.x = TRUE)
# ---------------------------------------------------------------- 4. summaries
CH[, period := fcase(year < 1946, "1925-1945", year < 1955, "1946-1954", default = "1955-1956 (new code)")]
BY_DIR <- dcast(CH[, .N, by = .(period, direction)], direction ~ period, value.var = "N", fill = 0)
BY_HOLC <- CH[!is.na(holc) & !annexation, .(changes = .N, pct_res_to_business_or_industrial = round(100 * mean(direction %in% c("Residential to business", "Residential to industrial")), 1),
                                            pct_to_industrial = round(100 * mean(to_group == "Industrial"), 1), pct_to_residential = round(100 * mean(to_group == "Residential"), 1)), by = holc][order(holc)]
# the same, keeping only changes placed by a block or by streets that agree (none whose two placements disagree)
SURE <- CH[!annexation & !is.na(holc) & !grepl("^uncertain|^subdivision$", placed_by)]
BY_HOLC_SURE <- SURE[, .(changes = .N, pct_res_to_business_or_industrial = round(100 * mean(direction %in% c("Residential to business", "Residential to industrial")), 1),
                         pct_to_residential = round(100 * mean(to_group == "Residential"), 1)), by = holc][order(holc)]
ft <- function(d) { d <- d[holc %in% c("A", "B", "D")]; if (length(unique(d$holc == "D")) < 2) return(NA_real_)
  fisher.test(table(d$holc == "D", d$direction %in% c("Residential to business", "Residential to industrial")))$p.value }
TEST <- rbind(data.table(period = "1925-1956", comparison = "Share of rezonings from residential to business or industrial, HOLC D vs A and B (Fisher's exact test)",
                         p_all_placed = signif(ft(CH[!annexation & !is.na(holc)]), 3), p_sure_placements = signif(ft(SURE), 3)),
              rbindlist(lapply(c("1925-1945", "1946-1954", "1955-1956 (new code)"), function(pp) data.table(period = pp, comparison = "Same, within the period",
                         p_all_placed = signif(ft(CH[!annexation & !is.na(holc) & period == pp]), 3), p_sure_placements = signif(ft(SURE[period == pp]), 3)))))
# the share of residential-to-business changes rose over time, and D areas' changes cluster late: compare within periods (Mantel-Haenszel)
mh <- function(d) { d <- d[holc %in% c("A", "B", "D")]; tb <- table(factor(d$holc == "D", c(FALSE, TRUE)), factor(d$direction %in% c("Residential to business", "Residential to industrial"), c(FALSE, TRUE)), d$period)
  tb <- tb[, , apply(tb, 3, function(z) all(rowSums(z) > 0)), drop = FALSE]; if (dim(tb)[3] < 1) return(c(NA, NA))
  r <- tryCatch(mantelhaen.test(tb, exact = TRUE), error = function(e) NULL); if (is.null(r)) c(NA, NA) else c(signif(r$estimate, 3), signif(r$p.value, 3)) }
m1 <- mh(CH[!annexation & !is.na(holc)]); m2 <- mh(SURE)
TEST <- rbind(TEST, data.table(period = "1925-1956, within periods", comparison = sprintf("Same, comparing within each period (exact Mantel-Haenszel; common odds ratio %s, sure placements %s)", m1[1], m2[1]),
                               p_all_placed = m1[2], p_sure_placements = m2[2]))
BY_HOLC_PERIOD <- CH[!is.na(holc) & !annexation, .(changes = .N, res_to_business_or_industrial = sum(direction %in% c("Residential to business", "Residential to industrial")),
                                                   to_residential = sum(to_group == "Residential")), by = .(period, holc)][order(period, holc)]
CH[, black_band := fcase(is.na(p_black), NA_character_, p_black < 1, "Under 1% Black", p_black < 10, "1-10% Black", default = "10%+ Black")]
BY_RACE <- CH[!is.na(black_band) & !annexation, .(changes = .N, pct_res_to_business_or_industrial = round(100 * mean(direction %in% c("Residential to business", "Residential to industrial")), 1),
                                                  pct_to_industrial = round(100 * mean(to_group == "Industrial"), 1), pct_to_residential = round(100 * mean(to_group == "Residential"), 1),
                                                  mean_haz_trades_400m = round(mean(haz_trades_400m, na.rm = TRUE), 1)), by = black_band]
PLACED <- CH[, .(changes = .N, median_spread_m = median(spread_m, na.rm = TRUE), checked_both_ways = sum(!is.na(m_between_methods)),
                 median_m_between_methods = median(m_between_methods, na.rm = TRUE)), by = .(placed_by)][, pct := round(100 * changes / sum(changes), 1)]
print(BY_DIR); print(BY_HOLC); print(BY_HOLC_SURE); print(TEST); print(BY_RACE); print(PLACED)
NODE <- if (file.exists("data/raw/ordinances/zoning_candidates.csv")) fread("data/raw/ordinances/zoning_candidates.csv", colClasses = "character")[, .(ordinance, node_id)] else data.table(ordinance = character(), node_id = character())
CH <- merge(CH, NODE, by = "ordinance", all.x = TRUE)
CH[, link := fifelse(is.na(node_id), NA_character_, paste0("https://library.municode.com/co/denver/munidocs/munidocs?nodeId=", node_id))]
OUT <- CH[, .(ordinance, year, link, from, to, from_group, to_group, direction, annexation, placed_by, n_points, spread_m, m_between_methods, lon, lat, holc, zone_1929, GEOID, census_used = census,
              p_black, p_fb, p_owner, haz_trades_400m, description = substr(gsub("\\s+", " ", desc), 1, 600))][order(ordinance)]
fwrite(OUT, file.path(O, "changes.csv"))
for (nm in c("BY_DIR", "BY_HOLC", "BY_HOLC_SURE", "BY_HOLC_PERIOD", "TEST", "BY_RACE", "PLACED")) { fwrite(get(nm), file.path(O, paste0(tolower(nm), ".csv"))); fwrite(get(nm), file.path(A, paste0("rezoning_", tolower(nm), ".csv"))) }
GJ <- file.path(A, "rezoning_1925_1956.geojson"); if (file.exists(GJ)) file.remove(GJ)
st_write(st_as_sf(OUT[!is.na(lon), !"description"], coords = c("lon", "lat"), crs = 4326, remove = FALSE), GJ, quiet = TRUE)
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
writeLines(c("# Changes to Denver's zone map, 1925-1956", "", sprintf("%d changes in %d ordinances (%d ordinance texts read).", nrow(CH), uniqueN(CH$ordinance), length(FILES)), "",
             "## How the changes were placed", "", kab(PLACED), "", "## Direction of change by period", "", kab(BY_DIR), "",
             "## By 1938 HOLC grade (rezonings, not annexations)", "", kab(BY_HOLC), "", "Only changes placed by a block or by agreeing streets:", "", kab(BY_HOLC_SURE), "", kab(TEST), "",
             "By period:", "", kab(BY_HOLC_PERIOD), "", "## By the census tract's share of Black residents (1940 for changes to 1945, 1950 after)", "", kab(BY_RACE)),
           file.path(O, "summary.md"))
message("wrote ", O)
