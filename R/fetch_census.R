# Download the historical census data for R/ej_panel.R through the IPUMS NHGIS API (free NHGIS account + API key in ~/.Renviron
# as IPUMS_API_KEY, or exported in the shell). ipumsr >= 0.9.   Re-running skips extracts whose files are already in work/census/.
#
#   Rscript R/fetch_census.R
#
# Extracts (census tracts, Colorado only -> work/census/):
#   A. 1990-2020 time-series tables standardized to 2010 tract boundaries: population, race, Hispanic origin (+ 2010 tract shapefile).
#   B. 1970 and 1980 tract tables (race, Spanish origin, nativity, poverty, total population) in their own boundaries.
#   C. 1940, 1950 and 1960: every tract table NHGIS has (they are small), in their own boundaries.
#   D. Tract boundary files for 1940, 1950, 1960, 1970, 1980.
#   F. County boundary files 1880-1940 (NHGIS), for the statewide IPUMS full-count county layer (R/county_panel_1880_1940.R).
#   E. Foreign born and poverty for 1990-2020, which the standardized series lack: 1990 STF3 and 2000 SF3 tract tables, ACS 5-year
#      2008-2012 and 2016-2020 tract tables (nativity, poverty status), with the 1990, 2000 and 2020 tract boundaries.
# Then work/census/denver_tract_panel.csv: one row per 2010 tract and census year 1940-2020 with pop, nhblk (Negro / Black /
# nonwhite as reported that year), hisp (Spanish surname 1960, Spanish American 1970, Spanish origin 1980, Hispanic 1990+),
# fb (foreign born; foreign-born WHITE in 1940-1950), ppov (persons below poverty, 1970+; 1970 = persons in poor families plus
# poor unrelated individuals; 2010 = ACS 2008-12, 2020 = ACS 2016-20 estimates). Counts not on 2010 tracts are AREA-WEIGHTED from
# each year's tracts onto 2010 tracts; the script prints the
# NHGIS variables used for every year - keep that list for the methods section.
if (!requireNamespace("ipumsr", quietly = TRUE)) install.packages("ipumsr")
suppressPackageStartupMessages({ library(ipumsr); library(data.table); library(sf) })
sf_use_s2(FALSE); UTM <- 26913; W <- "work/census"
key <- Sys.getenv("IPUMS_API_KEY"); if (!nzchar(key)) stop("set IPUMS_API_KEY (in ~/.Renviron or: export IPUMS_API_KEY=...)")
set_ipums_api_key(key, overwrite = TRUE, save = FALSE)
dir.create(W, showWarnings = FALSE, recursive = TRUE); CO <- "080"
have <- function(pattern) length(Sys.glob(file.path(W, "*", pattern))) > 0
get_and_unpack <- function(sub, what) { sub <- wait_for_extract(sub); files <- download_extract(sub, download_dir = W, overwrite = TRUE)
  for (f in files) unzip(f, exdir = W, overwrite = TRUE); message("downloaded ", what) }

# ---------------------------------------------------------------- A. standardized 1990-2020
if (!have("*_ts_geog2010_tract.csv")) {
  tst <- as.data.table(get_metadata_catalog("nhgis", metadata_type = "time_series_tables"))[grepl("2010", geographic_integration)]
  codes <- sapply(c("^Total Population", "^Persons by Race", "Hispanic or Latino"), function(p) tst[grepl(p, description, ignore.case = TRUE)]$name[1])
  message("standardized tables: ", paste(codes, collapse = ", "))
  ext <- define_extract_agg("nhgis", description = "Colorado tracts 1990-2020 standardized to 2010",
    time_series_tables = lapply(unname(codes), function(cd) tst_spec(cd, geog_levels = "tract")), tst_layout = "time_by_row_layout",
    geographic_extents = CO, shapefiles = "us_tract_2010_tl2010")
  get_and_unpack(submit_extract(ext), "A: 1990-2020 standardized")
}
# ---------------------------------------------------------------- B + C. 1940-1980 tables
ds <- as.data.table(get_metadata_catalog("nhgis", metadata_type = "datasets"))
tract_tables <- function(dname, pattern = NULL) {
  md <- tryCatch(get_metadata("nhgis", dataset = dname), error = function(e) NULL)
  if (is.null(md) || !"tract" %in% md$geog_levels$name) return(NULL)
  tabs <- as.data.table(md$data_tables); if (!is.null(pattern)) tabs <- tabs[grepl(pattern, description, ignore.case = TRUE)]
  if (!nrow(tabs)) return(NULL); tabs$name }
done <- function(tag) file.exists(file.path(W, paste0(".done_", tag)))
if (!done("C")) {
  specs <- list()
  for (dname in ds[grepl("^(1940|1950|1960)", group)]$name) { tb <- tract_tables(dname); if (length(tb)) { message(dname, ": ", length(tb), " tables"); specs[[dname]] <- ds_spec(dname, data_tables = tb, geog_levels = "tract") } }
  get_and_unpack(submit_extract(define_extract_agg("nhgis", description = "Colorado tracts 1940-1960, all tables", datasets = unname(specs), geographic_extents = CO)), "C: 1940-1960")
  file.create(file.path(W, ".done_C"))
}
if (!done("B")) {
  pat <- "^Total Population$|^Persons$|^Population$|^Total Persons$|Persons by Race|^Race by Sex$|^Race$|Race by Age|Nativity|Foreign|Spanish|Hispanic|Poverty Status|Persons .*Below Poverty"
  specs <- list()
  for (dname in ds[grepl("^(1970|1980)", group)]$name) { tb <- tract_tables(dname, pat); if (length(tb)) { message(dname, ": ", paste(tb, collapse = " ")); specs[[dname]] <- ds_spec(dname, data_tables = tb, geog_levels = "tract") } }
  get_and_unpack(submit_extract(define_extract_agg("nhgis", description = "Colorado tracts 1970-1980", datasets = unname(specs), geographic_extents = CO)), "B: 1970-1980")
  file.create(file.path(W, ".done_B"))
}
# ---------------------------------------------------------------- D. boundaries
for (z in Sys.glob(file.path(W, "*", "*.zip"))) unzip(z, exdir = dirname(z), overwrite = TRUE)   # NHGIS nests the shapefile zips
if (!have("*tract_1940*.shp") || !have("*tract_1980*.shp")) {
  shp <- as.data.table(get_metadata_catalog("nhgis", metadata_type = "shapefiles"))
  want <- shp[grepl("^us_tract_(1940|1950|1960|1970|1980)_tl2000$", name)]$name
  if (!length(want)) want <- shp[grepl("^us_tract_(1940|1950|1960|1970|1980)", name)][, .SD[1], by = .(yr = sub(".*(19\\d0).*", "\\1", name))]$name
  message("boundary files: ", paste(want, collapse = ", "))
  get_and_unpack(submit_extract(define_extract_agg("nhgis", description = "Colorado tract boundaries 1940-1980", shapefiles = want, geographic_extents = CO)), "D: boundaries")
  for (z in Sys.glob(file.path(W, "*", "*.zip"))) unzip(z, exdir = dirname(z), overwrite = TRUE)
}
# ---------------------------------------------------------------- F. county boundaries 1880-1940 (for the statewide full-count layer)
if (!done("F")) {
  shp <- as.data.table(get_metadata_catalog("nhgis", metadata_type = "shapefiles"))
  want <- shp[grepl("^us_county_(1880|1900|1910|1920|1930|1940)_tl2000$", name)]$name
  message("county boundary files: ", paste(want, collapse = ", "))
  get_and_unpack(submit_extract(define_extract_agg("nhgis", description = "Colorado county boundaries 1880-1940", shapefiles = want, geographic_extents = CO)), "F: county boundaries 1880-1940")
  for (z in Sys.glob(file.path(W, "*", "*.zip"))) unzip(z, exdir = dirname(z), overwrite = TRUE)
  file.create(file.path(W, ".done_F"))
}
# ---------------------------------------------------------------- E. 1990-2020 nativity and poverty (nominal tracts + ACS)
if (!done("E2")) {                                            # (E2: the first version of this extract, marker .done_E, missed the ACS tables)
  specs <- list()
  if (!done("E")) for (dname in c("1990_STF3", "2000_SF3a")) { tb <- tract_tables(dname, "^Nativity|Place of Birth|^Foreign|Poverty Status( in \\d{4})?( by Age)?$|^Age by Poverty|Persons .*Below Poverty")
    if (length(tb)) { message(dname, ": ", paste(tb, collapse = " ")); specs[[dname]] <- ds_spec(dname, data_tables = tb, geog_levels = "tract") } }
  # ACS: NHGIS spreads the detailed tables over several datasets (ACS5a, ACS5b, ...); ask every one for the tables by code
  ACS_TABLES <- c("B01003", "B05012", "B05002", "B17001")   # total population, nativity, place of birth, poverty status by sex by age
  for (dname in ds[grepl("^(2008_2012|2016_2020)_ACS5", name)]$name) {
    md <- tryCatch(get_metadata("nhgis", dataset = dname), error = function(e) NULL); if (is.null(md) || !"tract" %in% md$geog_levels$name) next
    tb <- intersect(ACS_TABLES, md$data_tables$name); if (length(tb)) { message(dname, ": ", paste(tb, collapse = " ")); specs[[dname]] <- ds_spec(dname, data_tables = tb, geog_levels = "tract") } }
  shp <- as.data.table(get_metadata_catalog("nhgis", metadata_type = "shapefiles"))
  want <- c(shp[grepl("^us_tract_1990_tl2000$|^us_tract_1990_tl2008$", name)]$name[1], shp[grepl("^us_tract_2000_tl2010$|^us_tract_2000_tl2000$", name)]$name[1], shp[grepl("^us_tract_2020_tl2020$", name)]$name[1])
  want <- want[!is.na(want)]; if (done("E")) want <- NULL else message("boundary files: ", paste(want, collapse = ", "))
  if (length(specs) || length(want)) {
    get_and_unpack(submit_extract(define_extract_agg("nhgis", description = "Colorado tracts 1990-2020 nativity and poverty", datasets = unname(specs), shapefiles = want, geographic_extents = CO)), "E: 1990-2020 nativity/poverty")
    for (z in Sys.glob(file.path(W, "*", "*.zip"))) unzip(z, exdir = dirname(z), overwrite = TRUE) } else message("E: no ACS tables found in the NHGIS catalog - fb/ppov for 2010-2020 stay NA")
  file.create(file.path(W, ".done_E"), file.path(W, ".done_E2"))
}

# ---------------------------------------------------------------- codebook parser: variable -> (table title, universe, label)
read_codebook <- function(f) {
  L <- readLines(f, warn = FALSE); title <- ""; uni <- ""; out <- list()
  for (l in L) {
    if (grepl("^\\s*(Table )?\\d+[.:]\\s+\\S", l) && !grepl("^\\s+[A-Z0-9]{3}\\d{3}[LU]?:", l)) { title <- trimws(sub("^\\s*(Table )?\\d+[.:]\\s+(\\(\\w+\\)\\s*)?", "", l)); uni <- ""; next }
    if (grepl("^\\s*Universe:", l)) { uni <- trimws(sub("^\\s*Universe:\\s*", "", l)); next }
    m <- regmatches(l, regexec("^\\s+([A-Z0-9]{3}[A-Z0-9]{2,4}[LU]?):\\s+(.+)$", l))[[1]]   # ABC001, ABC001L, ACS: ABCE001 / ABCM001
    if (length(m) == 3 && !grepl("bound:", m[3])) out[[length(out) + 1]] <- data.table(var = m[2], table = title, universe = uni, label = trimws(m[3]))
  }
  rbindlist(out)
}
gj <- function(g) sub("^G(\\d{2})0(\\d{3})0(\\d{6})$", "\\1\\2\\3", g)
# a rule is c(table regex, universe regex, label regex); the first rule with a match wins; matching columns are summed
pick <- function(cb, rules) { for (r in rules) { m <- cb[grepl(r[1], table, ignore.case = TRUE) & grepl(r[2], universe, ignore.case = TRUE) & grepl(r[3], label, ignore.case = TRUE)]
    if (nrow(m)) return(if (all(grepl("Below Poverty Level$|^Poverty Status by Age$", m$table))) m else m[substr(var, 1, 3) == substr(m$var[1], 1, 3)]) }; cb[0] }   # one NHGIS table only (1980 ships the same table in STF1, STF3 and PL94-171); except 1970 poverty = poor family members + poor unrelated individuals
RULES <- list(
  pop   = list(c("^Total Population$|^Persons$|^Population$|^Total Persons$", "^Persons$|^$", "^Total$|^Persons: Total$"), c("^Persons by Race( by Age)?( by Sex)?$|^Race by Sex$|^Race$|^Race by Age$", "^Persons$", "."),
               c("^Nativity$", "^Persons", "^(Native|Foreign born)$")),      # 1970: native + foreign born = all persons
  nhblk = list(c("", "", "^Persons: Black"), c("^Race by Sex$|^Nonwhite Persons by Race by Sex$|^Race$|^Persons by Race$", "^Persons$|^Non-?[Ww]hite Persons$", "^(Negro|Negroes|Black)( >> (Male|Female))?$"),
               c("^Race by Age$", "^Persons$", "^Black >>"), c("Race", "^Persons", "^(Negro|Black)( >> .*)?$"), c("Race|Nonwhite|Non-white|Color", "", "^(Nonwhite|Non-white|Negro)( >> .*)?$")),
  hisp  = list(c("", "", "^Persons: Hispanic or Latino$"), c("^Persons of Spanish Origin$|^Spanish American Persons$|Spanish Surname Population$|^Spanish Origin$", "", "^Total$|^Mexican$|^Puerto Rican$|^Cuban$|^Other Spanish$"),
               c("^Spanish Indicator$", "", "Spanish language|Spanish surname")),
  fb    = list(c("^Nativity( and Place of Birth)?$|^Nativity in the United States$", "^Persons|^Total population", "^Foreign[- ]born$"), c("Nativity and Parentage", "", "^Foreign Born$"), c("^Foreign.Born White Population( by Sex)?$", "", "^(Total|Male|Female)$"),
               c("Nativity|Place of Birth|Citizenship", "", "^Foreign[- ]born$|^Foreign >> (Male|Female)$|^Foreign[- ]born( \\(.*\\))?( >> .*)?$")),
  ppov  = list(c("^Poverty Status( in \\d{4})?$|Poverty Status in the Past 12 Months", "^Persons for Whom Poverty|Population for whom poverty", "^(Income in .* )?below poverty level$"),   # a total cell (ACS tables carry subtotals, so never sum their breakdowns)
               c("^Poverty Status( in \\d{4})?( by Age)?$|^Age by Poverty Status( in \\d{4})?$", "^Persons for Whom Poverty", "below poverty"),
               c("Persons in Families Below Poverty|^Poverty Status by Age$", "Persons in Families|Unrelated Individuals 14", "Aggregate number of persons|^Below poverty level >>")))
summarise_year <- function(csvs, yr) {
  tabs <- lapply(csvs, function(f) { d <- as.data.table(read_ipums_agg(f, verbose = FALSE)); d[, c("GISJOIN", grep("^[A-Z0-9]{3}[EM]?\\d{3}$", names(d), value = TRUE)), with = FALSE] })
  D <- Reduce(function(a, b) merge(a, b[, c("GISJOIN", setdiff(names(b), names(a))), with = FALSE], by = "GISJOIN", all = TRUE), tabs)
  cb <- unique(rbindlist(lapply(sub("\\.csv$", "_codebook.txt", csvs), read_codebook)), by = "var"); cb <- cb[var %in% names(D)]   # the same table may sit in two extracts
  cb <- cb[!(substr(var, 4, 4) == "M" & sub("^(...)M", "\\1E", var) %in% var)]                                          # ACS: keep estimates, drop margins of error
  out <- data.table(GISJOIN = D$GISJOIN, census = yr)
  for (k in names(RULES)) { m <- pick(cb, RULES[[k]])
    message(yr, " ", k, ": ", if (nrow(m)) paste0(m$var, " (", m$table, " / ", m$label, ")", collapse = " + ") else "-")
    out[[k]] <- if (nrow(m)) rowSums(as.matrix(D[, m$var, with = FALSE]), na.rm = TRUE) else NA_real_ }
  out[grepl("^G08", GISJOIN)]
}
# ---------------------------------------------------------------- build the panel
P <- list()
csv_a <- Sys.glob(file.path(W, "*", "*_ts_geog2010_tract.csv"))
if (length(csv_a)) { D <- as.data.table(read_ipums_agg(csv_a[1], verbose = FALSE)); cb <- read_codebook(sub("\\.csv$", "_codebook.txt", csv_a[1]))
  ycol <- intersect(c("DATAYEAR", "YEAR"), names(D))[1]; D[, census := as.integer(substr(as.character(get(ycol)), 1, 4))]
  for (yr in sort(unique(D$census))) { d <- D[census == yr]; out <- data.table(GEOID = gj(d$GISJOIN), census = yr)
    for (k in c("pop", "nhblk", "hisp")) { m <- pick(cb[var %in% names(d)], RULES[[k]]); out[[k]] <- if (nrow(m)) rowSums(as.matrix(d[, m$var, with = FALSE]), na.rm = TRUE) else NA_real_
      if (yr == min(D$census)) message("1990+ ", k, ": ", paste(m$var, collapse = "+")) }
    out$fb <- NA_real_; out$ppov <- NA_real_; P[[as.character(yr)]] <- out[substr(GEOID, 1, 2) == "08"] } }
tr10 <- Sys.glob(file.path(W, "*", "*tract_2010*.shp")); if (!length(tr10)) stop("2010 tract shapefile not found under work/census")
T10 <- st_make_valid(st_transform(st_read(tr10[1], quiet = TRUE), UTM)); T10 <- T10[substr(T10$GISJOIN, 1, 3) == "G08", ]; T10$GEOID <- gj(T10$GISJOIN)
for (yr in c(1940, 1950, 1960, 1970, 1980)) {
  csvs <- Sys.glob(file.path(W, "*", sprintf("*_%d_tract.csv", yr))); shpf <- Sys.glob(file.path(W, "*", sprintf("*tract_%d*.shp", yr)))
  if (!length(csvs) || !length(shpf)) { message(yr, ": tables or boundaries missing, skipped"); next }
  S <- summarise_year(csvs, yr)
  Ty <- st_make_valid(st_transform(st_read(shpf[1], quiet = TRUE), UTM)); Ty <- Ty[Ty$GISJOIN %in% S$GISJOIN, ]; Ty$a_src <- as.numeric(st_area(Ty))
  ov <- suppressWarnings(st_intersection(Ty[, c("GISJOIN", "a_src")], T10[, "GEOID"])); ov$w <- as.numeric(st_area(ov)) / ov$a_src
  M <- merge(as.data.table(st_drop_geometry(ov))[, .(GISJOIN, GEOID, w)], S, by = "GISJOIN")
  P[[as.character(yr)]] <- M[, lapply(.SD, function(v) if (all(is.na(v))) NA_real_ else sum(v * w, na.rm = TRUE)), by = .(GEOID, census), .SDcols = c("pop", "nhblk", "hisp", "fb", "ppov")]
}
# E. fill foreign born and poverty for 1990-2020: 1990/2000/2020 tables area-weighted onto 2010 tracts; the 2008-12 ACS is on 2010 tracts
aw <- function(S, shpf) { Ty <- st_make_valid(st_transform(st_read(shpf, quiet = TRUE), UTM)); Ty <- Ty[Ty$GISJOIN %in% S$GISJOIN, ]; Ty$a_src <- as.numeric(st_area(Ty))
  ov <- suppressWarnings(st_intersection(Ty[, c("GISJOIN", "a_src")], T10[, "GEOID"])); ov$w <- as.numeric(st_area(ov)) / ov$a_src
  M <- merge(as.data.table(st_drop_geometry(ov))[, .(GISJOIN, GEOID, w)], S, by = "GISJOIN")
  M[, .(fb = if (all(is.na(fb))) NA_real_ else sum(fb * w, na.rm = TRUE), ppov = if (all(is.na(ppov))) NA_real_ else sum(ppov * w, na.rm = TRUE)), by = GEOID] }
for (yr in c(1990, 2000, 2010, 2020)) {
  csvs <- Sys.glob(file.path(W, "*", switch(as.character(yr), "1990" = "*_1990_tract.csv", "2000" = "*_2000_tract.csv", "2010" = "*_20125_tract.csv", "2020" = "*_20205_tract.csv")))
  csvs <- csvs[!grepl("_ts_", csvs)]; if (!length(csvs) || is.null(P[[as.character(yr)]])) { message(yr, ": nativity/poverty tables missing, fb and ppov stay NA"); next }
  S <- summarise_year(csvs, yr)
  F <- if (yr == 2010) S[, .(GEOID = gj(GISJOIN), fb, ppov)] else { shpf <- Sys.glob(file.path(W, "*", sprintf("*tract_%d*.shp", yr))); if (!length(shpf)) { message(yr, ": boundaries missing"); next }; aw(S, shpf[1]) }
  P[[as.character(yr)]] <- merge(P[[as.character(yr)]][, .(GEOID, census, pop, nhblk, hisp)], F, by = "GEOID", all.x = TRUE)
}
panel <- rbindlist(P, fill = TRUE)[, .(GEOID, census, pop, nhblk, hisp, fb, ppov)][order(GEOID, census)]
fwrite(panel, file.path(W, "denver_tract_panel.csv"))
message("wrote ", file.path(W, "denver_tract_panel.csv"), ": ", nrow(panel), " tract-years; years ", paste(sort(unique(panel$census)), collapse = " "))
file.copy(Sys.glob(sub("\\.shp$", ".*", tr10[1])), W, overwrite = TRUE)
message("Now run:  Rscript R/ej_panel.R")
