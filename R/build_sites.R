# R port of pipeline/build_sites.py: cluster geocoded directory records into sites (30 m) and compare every site with the
# regulatory inventories (EPA FRS/TRI/RCRA/Superfund, CDPHE cleanup programs) -> "Not on any list" etc.
#   Rscript R/build_sites.R [geocodes.csv]
# Inputs : work/inv/records_linked.csv (directory records with establishment IDs; written by pipeline/link.py)
#          work/geo/tiger_results.csv  (geo_key, lat, lon, geo_quality; or the output of R/geocode_tiger.R in the same layout)
#          work/inv/reg.csv            (regulatory inventories; written by pipeline/build_reg.py)
# Output : work/inv/sites_R.csv, work/inv/records_sites_R.csv
suppressPackageStartupMessages({ library(data.table); library(sf); library(igraph) })
source("R/fuzz.R")
RE <- 6371000; rad <- function(x) x * pi / 180
hav <- function(la1, lo1, la2, lo2) { a <- sin((rad(la2) - rad(la1)) / 2)^2 + cos(rad(la1)) * cos(rad(la2)) * sin((rad(lo2) - rad(lo1)) / 2)^2; 2 * RE * asin(pmin(1, sqrt(a))) }
# connected components of points within 30 m, with the across-the-street parity rule. P: data.table ordered by lat with lat, lon,
# base (direction + street core) and num (house number). Returns the component membership (same logic as the union-find in Python).
cluster_points <- function(P) {
  edges <- list(); dlat <- 30 / RE * 180 / pi
  for (i in seq_len(nrow(P))) {
    j <- i + 1; while (j <= nrow(P) && P$lat[j] - P$lat[i] <= dlat) j <- j + 1
    if (j > i + 1) { k <- (i + 1):(j - 1); k <- k[hav(P$lat[i], P$lon[i], P$lat[k], P$lon[k]) <= 30]
      across <- P$base[k] == P$base[i] & !is.na(P$num[k]) & !is.na(P$num[i]) & (P$num[k] %% 2) != (P$num[i] %% 2); k <- k[!across]
      if (length(k)) edges[[length(edges) + 1]] <- cbind(i, k) }
  }
  E <- if (length(edges)) do.call(rbind, edges) else matrix(integer(), 0, 2)
  gr <- make_empty_graph(nrow(P), directed = FALSE) |> add_edges(as.vector(t(E)))
  components(gr)$membership
}
# words that carry no identity: legal forms, generic trade words and Colorado place names (two-word names first, so 'COLORADO SPRINGS'
# goes before 'COLORADO' can match alone). Identical to STOP in pipeline/build_sites.py.
STOP <- paste0("\\b(GRAND JUNCTION|FORT COLLINS|COLORADO SPRINGS|THE|INC|CO|CORP|CORPORATION|COMPANY|LLC|LTD|MFG|MANUFACTURING|OF|AND|DIV|DIVISION|INCORPORATED",
               "|INDUSTRIES|SYSTEMS|PRODUCTS|CASTINGS|PRECISION|ENTERPRISES|SERVICES|SUPPLY",
               "|COLORADO|DENVER|AURORA|BOULDER|PUEBLO|MONTROSE|ENGLEWOOD|LITTLETON|GOLDEN|LAKEWOOD|ARVADA|WESTMINSTER|LONGMONT|LOVELAND|GREELEY)\\b")
nn <- function(s) { s <- gsub("[^A-Z0-9 ]", " ", toupper(ifelse(is.na(s), "", s))); s <- gsub(STOP, " ", s, perl = TRUE); trimws(gsub("\\s+", " ", s)) }
# Same firm? token_set_ratio scores 100 whenever one token set is a subset of the other, so one shared word ('CRYSTAL', 'SERUM') used to
# match. A match needs either (a) token_set_ratio >= 88 AND at least two shared informative tokens, or (b) token_sort_ratio >= 88 (the
# whole names agree up to word order and OCR noise). Identical to name_match() in pipeline/build_sites.py.
name_match <- function(a, b) { if (!nzchar(a) || !nzchar(b)) return(FALSE); if (fz_token_sort_ratio(a, b) >= 88) return(TRUE)
  fz_token_set_ratio(a, b) >= 88 && fz_shared_tokens(a, b) >= 2 }
BASIS <- c("same entity (name or address)", "inside a cleanup boundary", "nearby record only", "none")
match_basis <- function(b) if ("entity" %in% b) BASIS[1] else if ("boundary" %in% b) BASIS[2] else if ("prox" %in% b) BASIS[3] else BASIS[4]
REP <- c(STREET = "ST", AVENUE = "AVE", AV = "AVE", BOULEVARD = "BLVD", ROAD = "RD", DRIVE = "DR", PLACE = "PL", COURT = "CT", NORTH = "N",
         SOUTH = "S", EAST = "E", WEST = "W", HIGHWAY = "HWY", PARKWAY = "PKWY", CIRCLE = "CIR", LANE = "LN")
norm_street <- function(s) vapply(strsplit(gsub("[^A-Z0-9 ]", " ", toupper(ifelse(is.na(s), "", s))), " "), function(t) {
  t <- t[nzchar(t)]; r <- REP[t]; paste(ifelse(is.na(r), t, r), collapse = " ") }, "")

# The run (inputs from work/, outputs to work/inv/sites_R.csv). Skipped when TESTING is defined, so tests/geocoding can source the
# functions above without the pipeline inputs.
if (!exists("TESTING") && !nzchar(Sys.getenv("AUDIT_TESTING"))) {
  args <- commandArgs(trailingOnly = TRUE); geo_f <- if (length(args)) args[1] else "work/geo/tiger_results.csv"
  df <- fread("work/inv/records_linked.csv", colClasses = c(zip5 = "character", sic = "character", est = "character", size = "character"), na.strings = "")
  # edition set: config/editions.json restricts the directory to the editions whose scans are complete (see R/edition_coverage.R)
  if (file.exists("config/editions.json")) { ED <- jsonlite::fromJSON("config/editions.json")
    if (identical(ED$mode, "complete")) { n0 <- nrow(df); df <- df[year %in% ED$complete_editions]; message("edition set 'complete': ", nrow(df), " of ", n0, " records kept from ", length(ED$complete_editions), " editions") } }
  geo <- fread(geo_f, na.strings = "")
  df$row <- seq_len(nrow(df)); df <- merge(df, geo, by = "geo_key", all.x = TRUE); setorder(df, row)   # keep record order (ties as in Python)
  q <- fifelse(is.na(df$geo_quality), "none", df$geo_quality)
  # as in pipeline/build_sites.py: an unresolved plain-vs-directional street (_dirambig) is not placed (zip_centroid); _dirzip / _dirtype
  # resolved it (exact); _dirsplit (glued direction letter split off) is approximate
  df$geo_level <- fifelse(grepl("dirambig", q), "zip_centroid",
                  fifelse(grepl("range_interp", q) & !grepl("fuzzy|nearzips|trim|dirloose|sufloose|dirsplit", q), "address",
                  fifelse(grepl("range_interp|street_nearest", q), "address_approx",
                  fifelse(q %in% c("zip_centroid", "city_centroid"), q, "none"))))
  df$placed_loose <- grepl("fuzzy|nearzips|trim|dirloose|sufloose|street_nearest", q)
  df$located <- df$geo_level %in% c("address", "address_approx")
  df$hazard_any <- df$fe_hazard | df$ext_hazard
  # ---- sites: connected components of geocoded points within 30 m of each other; points on the same street with odd and even house
  # numbers (opposite sides of the street, 24 m apart after the geocoder's 12 m offset) are never linked directly
  e <- new.env(); sys.source("R/geocode_tiger.R", envir = e)        # the geocoder's address parser
  pts <- unique(df[located == TRUE, .(geo_key, lat, lon, street_n)], by = "geo_key")
  pp <- lapply(pts$street_n, e$parse_addr)
  pts$num <- vapply(pp, function(a) a$num, 0); pts$base <- vapply(pp, function(a) trimws(paste(a$pre, a$core)), "")
  o <- order(pts$lat); P <- pts[o]
  P$comp <- cluster_points(P)
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
      # names for the inventory name match: the hazardous firms' names only (a retailer or office that later shared the address must not
      # make the site 'known' through its own RCRA notification); a site without a hazardous firm keeps all names (as in Python)
      names_n = list(sort(unique({ nm <- if (nrow(h)) h$name_n else name_n; nm[!is.na(nm) & nzchar(nm)] }), method = "radix")))
  }, by = site_id]
  # ---- regulatory comparison
  reg <- fread("work/inv/reg.csv", colClasses = c(zip = "character"), na.strings = "")
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
    rec <- list(); basis <- character()   # evidence behind every hit, over all tiers: 'entity' (name or address), 'boundary', 'prox'
    for (tier in names(RULES)) {
      ct <- R$tier[ii] == tier; cj <- ii[ct]; cd <- d[ct]
      # the radius grows by the spread of the site's member points. Approximately located sites used to get the full 250 m radius for this
      # proximity test; that did not make their point more accurate, it only let any record in the neighbourhood (a pharmacy's RCRA
      # notification) make the site 'known'; name and address matches do not depend on the point. Base radii for every site, as in Python.
      r_eff <- min(250, RULES[[tier]] + s$spread_m)
      nmok <- vapply(seq_along(cj), function(m) length(names) > 0 && nzchar(R$nn[cj[m]]) && any(vapply(names, function(n) name_match(R$nn[cj[m]], n), TRUE)), TRUE)
      hits <- c(sprintf("%s [%s; name match, %d m]", R$name[cj[nmok]], src_lab(R$source[cj[nmok]]), as.integer(cd[nmok])),
                sprintf("%s [%s; %d m]", R$name[cj[!nmok & cd <= r_eff]], src_lab(R$source[cj[!nmok & cd <= r_eff]]), as.integer(cd[!nmok & cd <= r_eff])))
      a <- am[reg$tier[am] == tier]; hits <- c(hits, if (length(a)) sprintf("%s [%s] (address match)", reg$name[a], src_lab(reg$source[a])))
      if (tier == "cleanup" && length(inside[[k]])) hits <- c(hits, sprintf("%s [%s] (inside site boundary)", PG$name[inside[[k]]], sub("CDPHE_", "CDPHE ", PG$source[inside[[k]]])))
      if (any(nmok) || length(a)) basis <- c(basis, "entity")
      if (tier == "cleanup" && length(inside[[k]])) basis <- c(basis, "boundary")
      if (any(!nmok & cd <= r_eff)) basis <- c(basis, "prox")
      # per-tier evidence for R/known_hidden_sensitivity.R (same as pipeline/build_sites.py): strongest basis in this tier and the
      # distance to the nearest differently named record inside the tier's radius
      po <- cd[!nmok & cd <= r_eff]
      rec[[paste0(tier, "_basis")]] <- if (any(nmok) || length(a)) "entity" else if (tier == "cleanup" && length(inside[[k]])) "boundary" else if (length(po)) "prox" else ""
      rec[[paste0(tier, "_prox_m")]] <- if (length(po)) round(min(po)) else NA_real_
      rec[[paste0(tier, "_match")]] <- substr(paste(unique(hits), collapse = " | "), 1, 400)
      rec[[paste0(tier, "_nearest_m")]] <- if (length(cj)) round(cd[1]) else NA_real_
    }
    # what the match rests on, strongest first; 'nearby record only' = a differently named record within the radius and nothing else
    rec$match_basis <- match_basis(basis)
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
  print(dcast(H[, .N, by = .(radar_status, match_basis)], radar_status ~ match_basis, value.var = "N", fill = 0))
}
