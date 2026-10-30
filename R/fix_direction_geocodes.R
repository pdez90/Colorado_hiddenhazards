# Remove geocodes that contradict the address's own direction on the Denver street grid.
#   Rscript R/fix_direction_geocodes.R        (idempotent; run once, then the downstream scripts)
# Denver's grid numbers north/south from Ellsworth Avenue and east/west from Broadway. A listing such as "4000 S. KALAMATH, DENVER"
# lies south of Ellsworth (latitude about 39.64), but the geocoder's direction-loose pass can place it on the unprefixed north
# Kalamath Street (latitude about 39.77) — in the north Denver industrial corridor. Audit (Oct 2026) found Denver listings of this kind, nearly all in the 1965 edition. Rule: a Denver listing whose street starts with an explicit direction
# (S, N, E, W, or the word) and whose point lies more than about 500 m on the wrong side of the baseline is set to unlocated
# (lat/lon/site removed, geo_level "none"); sites left with no located listing are dropped; the others keep their remaining years.
# Files changed in place: data/results/CO_directory_listings_1961-2002.csv, data/by_year/*.csv, app/data/{sites, site_years,
# site_firms}.csv, and the same in data/full_inventory/ when present. The removed listings are written to
# data/results/geocode_direction_conflicts.csv.
if (!exists("TESTING") && !nzchar(Sys.getenv("AUDIT_TESTING"))) for (p in c("data.table", "openxlsx", "readxl")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages(library(data.table))
ELLS <- 39.7163; BWAY <- -104.9875; TOL <- 0.005   # baselines (Ellsworth Ave latitude, Broadway longitude); ~500 m tolerance
dir_of <- function(street) { s <- toupper(trimws(ifelse(is.na(street), "", street)))
  m <- regmatches(s, regexec("^[0-9]+[A-Z]?\\s+(SOUTH|NORTH|EAST|WEST|S|N|E|W)\\.?\\s", s)); vapply(m, function(x) if (length(x) == 2) substr(x[2], 1, 1) else "", "") }
conflict <- function(street, city, lat, lon, level) { d <- dir_of(street); den <- toupper(trimws(ifelse(is.na(city), "", city))) == "DENVER" & !is.na(lat) & level %in% c("address", "address_approx")   # street-level points only
  den & ((d == "S" & lat > ELLS + TOL) | (d == "N" & lat < ELLS - TOL) | (d == "W" & lon > BWAY + TOL) | (d == "E" & lon < BWAY - TOL)) }
# every file is read through rd(): OCR quote characters are stripped from text columns. data.table::fread misreads a field that begins
# or ends with escaped quotes and each fread/fwrite round trip doubled them, so this script was not idempotent on such fields; the
# pipeline now strips quotes at source (pipeline/consolidate.py), and rd() cleans files written before that.
rd <- function(f, ...) { D <- fread(f, ...); for (j in names(D)) if (is.character(D[[j]])) set(D, j = j, value = gsub('"', "", D[[j]], fixed = TRUE)); D }
fix_set <- function(listings_f, sites_f, years_f = NULL, firms_f = NULL, by_year_dir = NULL, label = "") {
  if (!file.exists(listings_f)) return(invisible(NULL))
  L <- rd(listings_f, colClasses = c(sic = "character", zip = "character", est = "character", size = "character"))
  bad <- conflict(L$street, L$city, L$lat, L$lon, L$geo_level); message(label, ": ", sum(bad), " listings with a direction conflict")
  if (!any(bad)) return(invisible(NULL))
  out <- L[bad, .(year, name, street, city, lat, lon, site_id, fe_hazard)][, file := label]
  of <- "data/results/geocode_direction_conflicts.csv"; fwrite(if (file.exists(of)) unique(rbind(rd(of), out, fill = TRUE)) else out, of)
  hit <- unique(L$site_id[bad & !is.na(L$site_id) & nzchar(L$site_id)])
  L[bad, `:=`(lat = NA_real_, lon = NA_real_, site_id = NA_character_, geo_level = "none")]; fwrite(L, listings_f)
  if (!is.null(by_year_dir) && dir.exists(by_year_dir)) for (f in list.files(by_year_dir, "\\.csv$", full.names = TRUE)) {
    B <- rd(f, colClasses = c(zip = "character", sic_codes = "character")); b <- conflict(B$street_address, B$city, B$latitude, B$longitude, if ("geocode_level" %in% names(B)) B$geocode_level else rep("address", nrow(B)))
    if (any(b)) { B[b, `:=`(latitude = NA_real_, longitude = NA_real_, site_id = NA_character_)]; if ("geocode_level" %in% names(B)) B[b, geocode_level := "none"]; fwrite(B, f) } }
  if (file.exists(sites_f) && length(hit)) {
    S <- rd(sites_f, colClasses = c(GEOID = "character", zip = "character")); keep_years <- L[site_id %in% hit, .(yrs = list(sort(unique(year)))), by = site_id]
    gone <- setdiff(hit, keep_years$site_id); message(label, ": ", length(gone), " sites dropped (no located listing left), ", nrow(keep_years), " sites keep other years")
    S <- S[!site_id %in% gone]
    for (i in seq_len(nrow(keep_years))) { id <- keep_years$site_id[i]; y <- keep_years$yrs[[i]]; S[site_id == id, `:=`(first_year = min(y), last_year = max(y))] }
    fwrite(S, sites_f)
    if (!is.null(years_f) && file.exists(years_f)) { Y <- rd(years_f); ly <- unique(L[site_id %in% hit, .(site_id, year)])
      Y <- Y[!site_id %in% hit | paste(site_id, year) %in% paste(ly$site_id, ly$year)]; fwrite(Y, years_f) }
    if (!is.null(firms_f) && file.exists(firms_f)) { Fm <- rd(firms_f); if ("site_id" %in% names(Fm)) fwrite(Fm[!site_id %in% gone], firms_f) } }
}
# ---- rebuild every site that lost a listing from the listings it kept: point (mean of the remaining listings), address, years,
# hazardous years, sectors, firm lists and counts. Sites are taken from the conflict log, so this also repairs sites patched by an
# earlier run of this script (which only reset their first and last year). Inventory matches are left as they are: the point
# moves by a few metres at most, within the 30 m site radius.
rebuild <- function(listings_f, sites_f, years_f = NULL, firms_f = NULL, geojson_f = NULL, xlsx_f = NULL, label = "complete editions") {
  of <- "data/results/geocode_direction_conflicts.csv"; if (!file.exists(listings_f) || !file.exists(of)) return(invisible(NULL))
  lg <- rd(of, colClasses = c(site_id = "character")); hit <- unique(na.omit(lg[file == label]$site_id)); hit <- hit[nzchar(hit)]; if (!length(hit)) return(invisible(NULL))
  L <- rd(listings_f, colClasses = c(sic = "character", zip = "character", est = "character", size = "character"))[site_id %in% hit & !is.na(lat)]
  L[, fe := fe_hazard %in% c(TRUE, "TRUE", "True")]; L[, ext := ext_hazard %in% c(TRUE, "TRUE", "True")]; L[, hz := fe | ext]   # hazardous = F&E or extended sectors, as in pipeline/build_sites.py
  if (file.exists("R/geocode_tiger.R")) { e <- new.env(); sys.source("R/geocode_tiger.R", envir = e)              # the geocoder's address parser, for the normalised "2950 S FOX ST" form
    norm <- function(x) vapply(x, function(a) { p <- e$parse_addr(a); if (is.na(p$num)) toupper(gsub("\\s+", " ", gsub("[.,]", " ", a))) else trimws(gsub("\\s+", " ", paste(p$num, p$pre, p$core, p$suf))) }, "", USE.NAMES = FALSE)
  } else norm <- function(x) toupper(gsub("\\s+", " ", gsub("[.,]", " ", x)))
  yr <- function(y) { y <- sort(unique(y)); if (length(y) == 1) as.character(y) else paste0(min(y), "-", max(y)) }
  firms <- function(d, sic = TRUE) { if (!nrow(d)) return(""); f <- d[, .(nm = name[1], y = yr(year), s = paste(unique(na.omit(sic[nzchar(sic)])), collapse = ","), y0 = min(year)), by = estab_id][order(y0, nm)]
    paste(if (sic) sprintf("%s (%s%s)", f$nm, f$y, ifelse(nzchar(f$s), paste0("; SIC ", f$s), "")) else sprintf("%s (%s)", f$nm, f$y0), collapse = " | ") }
  secs <- function(v) paste(sort(unique(unlist(strsplit(v[!is.na(v) & nzchar(v)], "\\s*;\\s*")))), collapse = "; ")
  N <- L[, { m <- which.min((lat - mean(lat))^2 + (lon - mean(lon))^2)
    .(lat = mean(lat), lon = mean(lon), address = norm(street[m]), city = city[m], zip = zip[m], first_year = min(year), last_year = max(year),
      hazard_years = paste(sort(unique(year[hz])), collapse = ";"), fe_hazard = any(fe), ext_hazard = any(ext), fe_sectors = secs(fe_sectors[fe]), ext_sectors = secs(ext_sectors[ext]),
      n_editions = uniqueN(year), n_establishments = uniqueN(estab_id), n_hazard_establishments = uniqueN(estab_id[hz]),
      hazard_firms = firms(.SD[hz]), all_firms = firms(.SD, FALSE)) }, by = site_id]
  gone <- c(setdiff(hit, N$site_id), N[!fe_hazard & !ext_hazard, site_id])          # no located listing left, or none in a hazardous sector: not a hazard site any more
  N <- N[fe_hazard | ext_hazard]
  upd <- function(S) { S <- S[!site_id %in% gone]; cols <- intersect(setdiff(names(N), "site_id"), names(S)); if (!nrow(S)) return(S)
    for (cc in cols) { v <- N[[cc]][match(S$site_id, N$site_id)]; i <- which(!is.na(match(S$site_id, N$site_id)))
      if (length(i)) { cl <- class(S[[cc]])[1]; set(S, i, cc, switch(cl, logical = as.logical(v[i]), integer = as.integer(v[i]), numeric = as.numeric(v[i]), as.character(v[i]))) } }
    S }
  if (file.exists(sites_f)) { S <- rd(sites_f, colClasses = c(GEOID = "character", zip = "character", site_id = "character")); fwrite(upd(S), sites_f) }
  if (!is.null(years_f) && file.exists(years_f)) { Y <- rd(years_f, colClasses = c(site_id = "character"))
    # one row per site and year with a hazardous listing (as pipeline/app_inputs.py writes it): sectors joined by ";", "Extended sectors" for the extended set
    NY <- L[hz & site_id %in% N$site_id, .(sectors = paste(sort(unique(c(unlist(strsplit(fe_sectors[fe & nzchar(fe_sectors)], "\\s*;\\s*")), if (any(ext)) "Extended sectors"))), collapse = ";"),
                                           firms = substr(paste(unique(name), collapse = " | "), 1, 300)), by = .(site_id, year)]
    Y <- rbind(Y[!site_id %in% hit], NY[, names(Y), with = FALSE][order(site_id, year)]); setorder(Y, site_id, year); fwrite(Y, years_f) }
  if (!is.null(firms_f) && file.exists(firms_f)) { Fm <- rd(firms_f, colClasses = c(site_id = "character")); if ("estab_id" %in% names(Fm))
    fwrite(Fm[!site_id %in% gone & (!site_id %in% hit | paste(site_id, estab_id) %in% paste(L$site_id, L$estab_id))], firms_f) }
  if (!is.null(geojson_f) && file.exists(geojson_f) && requireNamespace("sf", quietly = TRUE)) {
    G <- sf::st_read(geojson_f, quiet = TRUE); A <- as.data.table(sf::st_drop_geometry(G)); A[, site_id := as.character(site_id)]
    keep <- !A$site_id %in% gone; A <- upd(A); k <- match(A$site_id, N$site_id)
    xy <- sf::st_coordinates(G[keep, ]); xy[!is.na(k), 1] <- N$lon[k[!is.na(k)]]; xy[!is.na(k), 2] <- N$lat[k[!is.na(k)]]
    out <- sf::st_as_sf(cbind(as.data.frame(A), x = xy[, 1], y = xy[, 2]), coords = c("x", "y"), crs = sf::st_crs(G))
    file.remove(geojson_f); sf::st_write(out, geojson_f, quiet = TRUE) }
  if (!is.null(xlsx_f) && file.exists(xlsx_f) && requireNamespace("openxlsx", quietly = TRUE) && requireNamespace("readxl", quietly = TRUE)) {
    # the workbook is rebuilt in full (same sheets, formulas and layout as pipeline/export.py); editing it in place with openxlsx
    # loses parts Excel needs
    rdx <- function(sh) as.data.table(readxl::read_excel(xlsx_f, sh, guess_max = 1e6, trim_ws = FALSE))   # readxl reads text exactly (openxlsx::read.xlsx mangles some)
    SH <- c("Hidden sites", "All F&E hazardous sites", "Extended-sector sites")
    D <- setNames(lapply(SH, function(sh) { X <- rdx(sh); X[, site_id := as.character(site_id)]; X <- upd(X)
      if (sh != "Extended-sector sites") X <- X[!site_id %in% N$site_id[!N$fe_hazard]]
      k <- match(X$site_id, N$site_id); if ("lat" %in% names(X)) X[!is.na(k), `:=`(lat = N$lat[k[!is.na(k)]], lon = N$lon[k[!is.na(k)]])]; X }), SH)
    RM <- rdx("Read me"); CV <- rdx("Coverage by edition")
    RM[grepl("^Method", Item), Description := sub("[0-9]+ editions 1961", paste(uniqueN(CV$year), "editions 1961"), Description)]
    wb <- openxlsx::createWorkbook(); hs <- openxlsx::createStyle(fontName = "Arial", fontSize = 10, textDecoration = "bold", fgFill = "#DDE5DD")
    put <- function(sh, X) { openxlsx::addWorksheet(wb, sh); openxlsx::writeData(wb, sh, X, headerStyle = hs); openxlsx::freezePane(wb, sh, firstRow = TRUE)
      openxlsx::setColWidths(wb, sh, seq_along(X), pmin(60, pmax(10, vapply(X, function(v) max(nchar(c("", as.character(head(v, 200)))), na.rm = TRUE), 1) + 2))) }
    put("Read me", RM); openxlsx::setColWidths(wb, "Read me", 2, 120); openxlsx::addStyle(wb, "Read me", openxlsx::createStyle(wrapText = TRUE, valign = "top"), rows = 2:(nrow(RM) + 1), cols = 2)
    RA <- c("Cleanup / contamination list", "TRI reporter", "RCRA hazardous-waste handler", "Solid waste facility", "Other EPA permit only", "Not on any list", "Total")
    put("Summary", data.table(radar = RA, `F&E sites` = NA, share = NA, `high confidence` = NA, medium = NA, low = NA)); n <- nrow(D[["All F&E hazardous sites"]]) + 1
    rg <- function(c) sprintf("'All F&E hazardous sites'!$%s$2:$%s$%d", c, c, n)
    cf <- LETTERS[match("confidence", names(D[["All F&E hazardous sites"]]))]   # confidence column letter (D since match_basis was added after radar)
    for (i in 2:7) { openxlsx::writeFormula(wb, "Summary", sprintf("COUNTIF(%s,A%d)", rg("B"), i), startCol = 2, startRow = i)
      for (j in 1:3) openxlsx::writeFormula(wb, "Summary", sprintf("COUNTIFS(%s,$A%d,%s,\"%s\")", rg("B"), i, rg(cf), c("high", "medium", "low")[j]), startCol = 3 + j, startRow = i) }
    for (i in 2:8) openxlsx::writeFormula(wb, "Summary", sprintf("IFERROR(B%d/$B$8,0)", i), startCol = 3, startRow = i)
    for (j in c(2, 4:6)) openxlsx::writeFormula(wb, "Summary", sprintf("SUM(%s2:%s7)", LETTERS[j], LETTERS[j]), startCol = j, startRow = 8)
    openxlsx::addStyle(wb, "Summary", openxlsx::createStyle(numFmt = "0.0%"), rows = 2:8, cols = 3)
    openxlsx::writeData(wb, "Summary", "Counts recalculate from the All F&E hazardous sites sheet.", startCol = 1, startRow = 10)
    for (sh in SH) put(sh, D[[sh]]); put("Coverage by edition", CV)
    openxlsx::addStyle(wb, "Coverage by edition", openxlsx::createStyle(numFmt = "0%"), rows = 2:(nrow(CV) + 1), cols = 4:5, gridExpand = TRUE)
    openxlsx::modifyBaseFont(wb, fontSize = 10, fontName = "Arial"); openxlsx::saveWorkbook(wb, xlsx_f, overwrite = TRUE)
    # some openxlsx/zip versions leave sheet links to drawing files they did not write, which strict readers refuse: drop those links
    td <- tempfile(); utils::unzip(xlsx_f, exdir = td)
    for (rf in list.files(file.path(td, "xl", "worksheets", "_rels"), full.names = TRUE)) { x <- paste(readLines(rf, warn = FALSE), collapse = "")
      rel <- regmatches(x, gregexpr("<Relationship [^>]*/>", x))[[1]]; tgt <- sub('.*Target="([^"]+)".*', "\\1", rel)
      miss <- !file.exists(file.path(td, "xl", "worksheets", tgt)); if (any(miss)) { for (r in rel[miss]) x <- sub(r, "", x, fixed = TRUE); writeLines(x, rf) } }
    for (sf in list.files(file.path(td, "xl", "worksheets"), "\\.xml$", full.names = TRUE)) { x <- paste(readLines(sf, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
      for (id in regmatches(x, gregexpr('<(drawing|legacyDrawing) r:id="[^"]+"/>', x))[[1]]) { rid <- sub('.*r:id="([^"]+)".*', "\\1", id)
        rf <- file.path(td, "xl", "worksheets", "_rels", paste0(basename(sf), ".rels")); if (!file.exists(rf) || !grepl(paste0('Id="', rid, '"'), paste(readLines(rf, warn = FALSE), collapse = ""))) x <- sub(id, "", x, fixed = TRUE) }
      writeLines(x, sf, useBytes = TRUE) }
    f <- normalizePath(xlsx_f); file.remove(f); old <- setwd(td); utils::zip(f, list.files(".", recursive = TRUE, all.files = TRUE), flags = "-qX9"); setwd(old) }
  message("rebuilt ", nrow(N), " sites from their remaining listings; ", length(gone), " sites with no hazardous listing left removed") }
if (!exists("TESTING") && !nzchar(Sys.getenv("AUDIT_TESTING"))) {   # the run; tests/geocoding source the functions above with TESTING defined
  fix_set("data/results/CO_directory_listings_1961-2002.csv", "app/data/sites.csv", "app/data/site_years.csv", "app/data/site_firms.csv", "data/by_year", "complete editions")
  fix_set("data/full_inventory/CO_directory_listings_1961-2002.csv", "data/full_inventory/sites.csv", NULL, "data/full_inventory/site_firms.csv", "data/full_inventory/by_year", "full inventory")
  rebuild("data/results/CO_directory_listings_1961-2002.csv", "app/data/sites.csv", "app/data/site_years.csv", "app/data/site_firms.csv",
          "data/results/CO_historical_industrial_sites.geojson", "data/results/CO_hazardous_sites_1961-2002.xlsx")
  rebuild("data/full_inventory/CO_directory_listings_1961-2002.csv", "data/full_inventory/sites.csv", NULL, "data/full_inventory/site_firms.csv", label = "full inventory")
}
