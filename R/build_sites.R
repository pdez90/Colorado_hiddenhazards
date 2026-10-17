# R port of pipeline/build_sites.py: cluster geocoded directory records into sites (30 m) and compare every site with the
# regulatory inventories (EPA FRS/TRI/RCRA/Superfund, CDPHE cleanup programs) -> "Not on any list" etc.
#   Rscript R/build_sites.R [geocodes.csv]
# Inputs : work/inv/records_linked.csv (directory records with establishment IDs; written by pipeline/link.py)
#          work/geo/tiger_results.csv  (geo_key, lat, lon, geo_quality; or the output of R/geocode_tiger.R in the same layout)
#          work/inv/reg.csv            (regulatory inventories; written by pipeline/build_reg.py)
# Output : work/inv/sites_R.csv, work/inv/records_sites_R.csv
suppressPackageStartupMessages({ library(data.table); library(sf); library(igraph) })
source("R/fuzz.R")
args <- commandArgs(trailingOnly = TRUE); geo_f <- if (length(args)) args[1] else "work/geo/tiger_results.csv"
RE <- 6371000; rad <- function(x) x * pi / 180
hav <- function(la1, lo1, la2, lo2) { a <- sin((rad(la2) - rad(la1)) / 2)^2 + cos(rad(la1)) * cos(rad(la2)) * sin((rad(lo2) - rad(lo1)) / 2)^2; 2 * RE * asin(pmin(1, sqrt(a))) }

df <- fread("work/inv/records_linked.csv", colClasses = c(zip5 = "character", sic = "character", est = "character", size = "character"), na.strings = "")
geo <- fread(geo_f, na.strings = "")
df$row <- seq_len(nrow(df)); df <- merge(df, geo, by = "geo_key", all.x = TRUE); setorder(df, row)   # keep record order (ties as in Python)
q <- fifelse(is.na(df$geo_quality), "none", df$geo_quality)
df$geo_level <- fifelse(grepl("range_interp", q) & !grepl("fuzzy|nearzips|trim|dirloose|sufloose|dirambig", q), "address",
                fifelse(grepl("range_interp|street_nearest", q), "address_approx",
                fifelse(q %in% c("zip_centroid", "city_centroid"), q, "none")))
df$placed_loose <- grepl("fuzzy|nearzips|trim|dirloose|sufloose|street_nearest", q)   # dirambig alone keeps the exact-match search radius
df$located <- df$geo_level %in% c("address", "address_approx")
df$hazard_any <- df$fe_hazard | df$ext_hazard

# ---- sites: connected components of geocoded points within 30 m of each other
pts <- unique(df[located == TRUE, .(geo_key, lat, lon)], by = "geo_key")
o <- order(pts$lat); P <- pts[o]; edges <- list(); dlat <- 30 / RE * 180 / pi
for (i in seq_len(nrow(P))) {
  j <- i + 1; while (j <= nrow(P) && P$lat[j] - P$lat[i] <= dlat) j <- j + 1
  if (j > i + 1) { k <- (i + 1):(j - 1); k <- k[hav(P$lat[i], P$lon[i], P$lat[k], P$lon[k]) <= 30]; if (length(k)) edges[[length(edges) + 1]] <- cbind(i, k) }
}
E <- if (length(edges)) do.call(rbind, edges) else matrix(integer(), 0, 2)
gr <- make_empty_graph(nrow(P), directed = FALSE) |> add_edges(as.vector(t(E)))
P$comp <- components(gr)$membership
P$site_id <- sprintf("S%05d", match(P$comp, unique(P$comp[order(P$geo_key)])) - 1L)   # IDs are arbitrary; compare by geo_key
df <- merge(df, P[, .(geo_key, site_id)], by = "geo_key", all.x = TRUE); setorder(df, row)

splitsec <- function(x) { x <- unlist(strsplit(x[!is.na(x)], "; ", fixed = TRUE)); sort(unique(x[nzchar(x)])) }
S <- df[!is.na(site_id), {
  la <- mean(lat); lo <- mean(lon); lvl <- c(address = 1, address_approx = 2)[geo_level]; b <- order(lvl, year)[1]
  h <- .SD[hazard_any == TRUE]
  .(lat = la, lon = lo, spread_m = max(RE * sqrt(rad(lat - la)^2 + (rad(lon - lo) * cos(rad(la)))^2)),
    address = street_n[b], city = city_g[b], zip = zip5[b],
    geo_level = if (any(geo_level == "address")) "address" else "address_approx",
    placed_loose = all(placed_loose | !located),
    first_year = min(year), last_year = max(year), n_editions = uniqueN(year),
    n_establishments = uniqueN(estab_id), n_hazard_establishments = uniqueN(h$estab_id),
    fe_hazard = any(fe_hazard), ext_hazard = any(ext_hazard),
    fe_sectors = paste(splitsec(fe_sectors), collapse = "; "), ext_sectors = paste(splitsec(ext_sectors), collapse = "; "),
    hazard_years = paste(sort(unique(h$year)), collapse = ";"),
    industry_evidence = if (any(h$sic_source %in% c("directory", "naics"))) "printed" else "inferred",
    names_n = list(sort(unique(name_n[!is.na(name_n) & nzchar(name_n)]), method = "radix")))
}, by = site_id]

# ---- regulatory comparison
reg <- fread("work/inv/reg.csv", colClasses = c(zip = "character"), na.strings = "")
STOP <- "\\b(THE|INC|CO|CORP|CORPORATION|COMPANY|LLC|LTD|MFG|MANUFACTURING|OF|AND|DIV|DIVISION|INDUSTRIES|PRODUCTS|COLORADO|DENVER|INCORPORATED)\\b"
nn <- function(s) { s <- gsub("[^A-Z0-9 ]", " ", toupper(ifelse(is.na(s), "", s))); s <- gsub(STOP, " ", s, perl = TRUE); trimws(gsub("\\s+", " ", s)) }
REP <- c(STREET = "ST", AVENUE = "AVE", AV = "AVE", BOULEVARD = "BLVD", ROAD = "RD", DRIVE = "DR", PLACE = "PL", COURT = "CT", NORTH = "N",
         SOUTH = "S", EAST = "E", WEST = "W", HIGHWAY = "HWY", PARKWAY = "PKWY", CIRCLE = "CIR", LANE = "LN")
norm_street <- function(s) vapply(strsplit(gsub("[^A-Z0-9 ]", " ", toupper(ifelse(is.na(s), "", s))), " "), function(t) {
  t <- t[nzchar(t)]; r <- REP[t]; paste(ifelse(is.na(r), t, r), collapse = " ") }, "")
reg$nn <- nn(reg$name); reg$street_n <- norm_street(reg$address); reg$zip5 <- substr(ifelse(is.na(reg$zip), "", reg$zip), 1, 5)
reg$city_u <- toupper(trimws(ifelse(is.na(reg$city), "", reg$city)))
src_lab <- function(x) sub("CDPHE_", "CDPHE ", sub("EPA_", "", x))
R <- reg[!is.na(lat) & !is.na(lon)][order(lat)]
sf_use_s2(FALSE)
PG <- reg[!is.na(geom_wkt)]
PGs <- if (nrow(PG)) suppressWarnings(st_buffer(st_as_sfc(PG$geom_wkt, crs = 4326), 0.0004)) else NULL   # ~40 m, planar degrees as in Python
spts <- st_as_sfc(lapply(seq_len(nrow(S)), function(i) st_point(c(S$lon[i], S$lat[i]))), crs = 4326)
inside <- if (!is.null(PGs)) suppressMessages(st_within(spts, PGs)) else replicate(nrow(S), integer(), simplify = FALSE)
RULES <- c(cleanup = 75, tri = 100, rcra_handler = 40, other_epa = 40, solid_waste = 75)
key_zip <- paste(reg$street_n, reg$zip5, sep = "|"); key_city <- paste(reg$street_n, reg$city_u, sep = "|")
dl <- 250 / RE * 180 / pi
res <- vector("list", nrow(S))
for (k in seq_len(nrow(S))) {
  s <- S[k]; lo_i <- findInterval(s$lat - dl, R$lat) + 1; hi_i <- findInterval(s$lat + dl, R$lat)
  ii <- if (hi_i >= lo_i) lo_i:hi_i else integer()
  if (length(ii)) { d <- hav(s$lat, s$lon, R$lat[ii], R$lon[ii]); keep <- d <= 250; ii <- ii[keep]; d <- d[keep]; o2 <- order(d); ii <- ii[o2]; d <- d[o2] } else d <- numeric()
  names <- nn(unlist(s$names_n))
  am <- if (!is.na(s$zip) && nzchar(s$zip)) which(key_zip == paste(s$address, s$zip, sep = "|")) else integer()
  if (!length(am)) am <- which(key_city == paste(s$address, toupper(trimws(ifelse(is.na(s$city), "", s$city))), sep = "|"))
  rec <- list()
  for (tier in names(RULES)) {
    ct <- R$tier[ii] == tier; cj <- ii[ct]; cd <- d[ct]
    r_eff <- if (s$placed_loose) max(RULES[[tier]], 250) else min(250, RULES[[tier]] + s$spread_m)
    nmok <- vapply(seq_along(cj), function(m) length(names) > 0 && nzchar(R$nn[cj[m]]) && max(vapply(names, function(n) fz_token_set_ratio(R$nn[cj[m]], n), 0)) >= 88, TRUE)
    hits <- c(sprintf("%s [%s; name match, %d m]", R$name[cj[nmok]], src_lab(R$source[cj[nmok]]), as.integer(cd[nmok])),
              sprintf("%s [%s; %d m]", R$name[cj[!nmok & cd <= r_eff]], src_lab(R$source[cj[!nmok & cd <= r_eff]]), as.integer(cd[!nmok & cd <= r_eff])))
    a <- am[reg$tier[am] == tier]; hits <- c(hits, if (length(a)) sprintf("%s [%s] (address match)", reg$name[a], src_lab(reg$source[a])))
    if (tier == "cleanup" && length(inside[[k]])) hits <- c(hits, sprintf("%s [%s] (inside site boundary)", PG$name[inside[[k]]], sub("CDPHE_", "CDPHE ", PG$source[inside[[k]]])))
    rec[[paste0(tier, "_match")]] <- substr(paste(unique(hits), collapse = " | "), 1, 400)
    rec[[paste0(tier, "_nearest_m")]] <- if (length(cj)) round(cd[1]) else NA_real_
  }
  res[[k]] <- rec
}
M <- rbindlist(res)
S <- cbind(S[, !"names_n"], M)
S$radar_status <- fcase(S$cleanup_match != "", "1 Cleanup / contamination list", S$tri_match != "", "2 TRI reporter",
                        S$rcra_handler_match != "", "3 RCRA hazardous-waste handler", S$solid_waste_match != "", "4 Solid waste facility",
                        S$other_epa_match != "", "5 Other EPA permit only", default = "6 Not on any list")
S$confidence <- fifelse(S$geo_level == "address" & S$industry_evidence == "printed", "high",
                fifelse(S$geo_level == "address" | S$industry_evidence == "printed", "medium", "low"))
S$radar <- sub("^\\d ", "", S$radar_status)
fwrite(S, "work/inv/sites_R.csv")
fwrite(S[fe_hazard | ext_hazard], "work/inv/sites_app_R.csv")      # same rows as app/data/sites.csv
fwrite(df[, .(geo_key, year, name, estab_id, site_id, lat, lon, geo_level, fe_hazard, ext_hazard)], "work/inv/records_sites_R.csv")
H <- S[fe_hazard == TRUE]
fwrite(H[, .N, by = radar_status][order(radar_status)], "work/inv/sites_R_summary.csv")
cat("located records", sum(df$located), "of", nrow(df), "\nsites", nrow(S), "F&E hazardous sites", nrow(H), "\n")
print(H[, .N, by = radar_status][order(radar_status)])
