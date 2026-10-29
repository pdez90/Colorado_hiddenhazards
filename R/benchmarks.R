# Benchmarks: how do the Colorado directories compare with the public national manufacturing series?
#   Rscript R/benchmarks.R
# Three comparisons, all at the county level (the finest geography any public national series offers):
#   1. 1975-2002: County Business Patterns (CBP) establishment counts by county and 2-digit SIC (1975-97) / NAICS (1998-2002),
#      from the raw county files redistributed by Eckert, Fort, Schott & Yang (2021, NBER WP 26632; github.com/fpeckert/website release
#      "cbp-data", efsy_<year>.zip; 1975-85 are the National Archives files, 1986+ the Census CBP files). Establishment counts are never
#      suppressed in CBP (only employment is). Compared with the Directory of Colorado Manufacturers editions of the same years: all
#      manufacturers and Frickel & Elliott's hazardous sectors (SIC 28, 29, 30, 33, 34, 35, 37 = NAICS 325, 324, 326, 331, 332, 333, 336).
#   2. 1880-1940: NHGIS county tables of manufacturing establishments (Census of Manufactures as tabulated by the decennial census),
#      via the NHGIS API (IPUMS_API_KEY in ~/.Renviron, as for fetch_census.R), compared with the Colorado State Business Directory's
#      hazardous trades by county around each census year (the directory lists only the hazardous trades, so this is a coverage floor).
#   3. 1870 and 1880: Atack-Bateman-Weiss Census of Manufactures establishment samples (Vanderbilt 'State Samples' workbooks; the same
#      data are deposited at ICPSR). The script downloads them if work/benchmarks/atack/ is empty; Colorado rows (if any) are tabulated by
#      county and industry. These are samples of surviving schedules, not a complete census, and carry no street addresses.
# Outputs: data/results/benchmarks/{cbp_vs_directory_state.csv, cbp_vs_directory_county.csv, nhgis_mfg_vs_directory.csv,
#          atack_colorado.csv, benchmarks_summary.md}; the first three are copied to app/data/ for the Benchmarks tab.
# every edition, including the partial ones set aside by config/editions.json (data/full_inventory/ keeps the all-editions files)
LISTINGS_ALL <- if (file.exists("data/full_inventory/CO_directory_listings_1961-2002.csv")) "data/full_inventory/CO_directory_listings_1961-2002.csv" else "data/results/CO_directory_listings_1961-2002.csv"
suppressPackageStartupMessages({ library(data.table); library(sf) })
sf_use_s2(FALSE); W <- "work/benchmarks"; O <- "data/results/benchmarks"; A <- "app/data"
for (d in c(W, file.path(W, "cbp"), file.path(W, "atack"), O)) dir.create(d, showWarnings = FALSE, recursive = TRUE)
HAZ_SIC <- c("28", "29", "30", "33", "34", "35", "37"); HAZ_NAICS <- c("325", "324", "326", "331", "332", "333", "336")
# NHGIS county GISJOIN = "G" + state (3 digits, "080") + county (4 digits, FIPS x 10, e.g. "G0801010" = Pueblo 08101): characters 5-8 are NHGISCTY
gisjoin_county <- function(g) sprintf("%03d", as.integer(substr(g, 5, 8)) %/% 10)
# a census is compared only when a directory edition was printed within two years of it (none between 1892 and 1910, so 1900 is left out:
# a firm listed in 1892 and again in 1910 is not evidence of a 1900 listing)
has_edition <- function(cy, ed_yrs, within = 2) any(abs(ed_yrs - cy) <= within)
cty_names <- c("001"="Adams","003"="Alamosa","005"="Arapahoe","007"="Archuleta","009"="Baca","011"="Bent","013"="Boulder","014"="Broomfield","015"="Chaffee","017"="Cheyenne","019"="Clear Creek","021"="Conejos","023"="Costilla","025"="Crowley","027"="Custer","029"="Delta","031"="Denver","033"="Dolores","035"="Douglas","037"="Eagle","039"="Elbert","041"="El Paso","043"="Fremont","045"="Garfield","047"="Gilpin","049"="Grand","051"="Gunnison","053"="Hinsdale","055"="Huerfano","057"="Jackson","059"="Jefferson","061"="Kiowa","063"="Kit Carson","065"="Lake","067"="La Plata","069"="Larimer","071"="Las Animas","073"="Lincoln","075"="Logan","077"="Mesa","079"="Mineral","081"="Moffat","083"="Montezuma","085"="Montrose","087"="Morgan","089"="Otero","091"="Ouray","093"="Park","095"="Phillips","097"="Pitkin","099"="Prowers","101"="Pueblo","103"="Rio Blanco","105"="Rio Grande","107"="Routt","109"="Saguache","111"="San Juan","113"="San Miguel","115"="Sedgwick","117"="Summit","119"="Teller","121"="Washington","123"="Weld","125"="Yuma")

# ---------------------------------------------------------------- directory 1961-2002 by county and edition
L <- fread(LISTINGS_ALL, colClasses = c(sic = "character", naics = "character", zip = "character"))
L <- L[!is.na(lat)]
tr <- st_make_valid(st_read("app/data/enviroscreen_tracts.geojson", quiet = TRUE)[, "GEOID"]); tr$county <- substr(tr$GEOID, 3, 5)
cty <- suppressWarnings(st_make_valid(aggregate(tr[, "county"], by = list(county = tr$county), FUN = function(x) x[1])))   # dissolve to counties
pts <- st_as_sf(unique(L[, .(lat, lon)]), coords = c("lon", "lat"), crs = 4326, remove = FALSE)
ix <- suppressWarnings(st_intersects(pts, cty, sparse = TRUE)); pts$county <- cty$county[vapply(ix, function(i) if (length(i)) i[1] else NA_integer_, 1L)]
L <- merge(L, as.data.table(st_drop_geometry(pts))[, .(lat, lon, county)], by = c("lat", "lon"))
L[, mfg := grepl("^[23][0-9]", sic) | grepl("^3[123]", naics)]   # manufacturing by SIC (20-39) or NAICS (31-33); the later editions carry NAICS only
DIR <- L[!is.na(county), .(dir_all = uniqueN(estab_id), dir_mfg = uniqueN(estab_id[mfg]), dir_haz = uniqueN(estab_id[fe_hazard %in% c(TRUE, "True")]),
                          dir_street = uniqueN(estab_id[geo_level %in% c("address", "address_approx")])), by = .(year, county)]
message("directory: ", nrow(L), " listings with a county in ", uniqueN(L$year), " editions")

# ---------------------------------------------------------------- 1. CBP 1975-2002
cbp_year <- function(y) {
  z <- file.path(W, "cbp", sprintf("efsy_%d.zip", y)); out <- file.path(W, "cbp", sprintf("cbp_CO_%d.csv", y)); if (file.exists(out)) return(fread(out, colClasses = c(county = "character", ind = "character")))
  if (!file.exists(z)) { message("downloading CBP ", y, " ..."); download.file(sprintf("https://github.com/fpeckert/website/releases/download/cbp-data/efsy_%d.zip", y), z, mode = "wb", quiet = TRUE) }
  fl <- unzip(z, list = TRUE)$Name; f <- fl[grepl(sprintf("cbp%02dco\\.txt$", y %% 100), fl, ignore.case = TRUE) & !grepl("imputed", fl, ignore.case = TRUE)][1]
  tmp <- tempfile(); unzip(z, files = f, exdir = tmp); p <- file.path(tmp, f)
  if (y < 1986) {   # National Archives layout: FIPS state/county at the end; the numeric block is fixed width (emp 9, qp1 12, ap 12, est 6, 13 size classes x 6) but split on stray commas
    raw <- fread(p, colClasses = "character", header = TRUE); raw <- raw[FIPSTATE == "08" | FIPSTATE == " 08" | trimws(FIPSTATE) == "08"]
    num <- apply(raw[, 7:23], 1, function(r) paste(gsub("[^0-9]", "", r), collapse = ""))
    d <- data.table(county = trimws(raw$FIPSCTY2), ind = trimws(raw$SICCODE), est = as.integer(substr(num, 34, 39)), emp = as.integer(substr(num, 1, 9)))
  } else { raw <- fread(p, colClasses = "character"); raw <- raw[fipstate == "08"]; ic <- intersect(c("sic", "naics"), names(raw))[1]
    d <- data.table(county = raw$fipscty, ind = trimws(raw[[ic]]), est = as.integer(raw$est), emp = as.integer(raw$emp)) }
  d[, year := y]; fwrite(d, out); d }
CBP <- rbindlist(lapply(1975:2002, cbp_year))
CBP[, `:=`(two = substr(ind, 1, 2), three = substr(ind, 1, 3))]
cbpy <- CBP[, {
  if (.BY$year <= 1997) { two <- substr(ind, 1, 2); is2 <- grepl("^[0-9]{2}00$", ind); m <- is2 & two %in% as.character(20:39); h <- is2 & two %in% HAZ_SIC }   # 2-digit SIC totals are coded "2800"; "20--" is the whole manufacturing division (1986-97)
  else { m <- ind %in% c("31----", "32----", "33----"); h <- ind %in% sprintf("%s///", HAZ_NAICS) }
  .(cbp_mfg = sum(est[m]), cbp_haz = sum(est[h]), cbp_mfg_emp = sum(emp[m])) }, by = .(year, county)]
CMP <- merge(cbpy, DIR, by = c("year", "county"), all = TRUE)[year >= 1975]
CMP[, county_name := cty_names[county]]
CMP_state <- CMP[, .(cbp_mfg = sum(cbp_mfg, na.rm = TRUE), cbp_haz = sum(cbp_haz, na.rm = TRUE), dir_mfg = sum(dir_mfg, na.rm = TRUE), dir_haz = sum(dir_haz, na.rm = TRUE), dir_all = sum(dir_all, na.rm = TRUE)), by = year][order(year)]
CMP_state[, `:=`(ratio_mfg = round(dir_mfg / cbp_mfg, 2), ratio_haz = round(dir_haz / cbp_haz, 2))]
CMP_state[dir_all == 0, `:=`(dir_mfg = NA, dir_haz = NA, dir_all = NA, ratio_mfg = NA, ratio_haz = NA)]   # years without a directory edition
# how much of each edition we hold: scanned pages, listings, parts, share without an industry code (the directory line tracks these, not the economy)
L0 <- fread(LISTINGS_ALL, colClasses = c(sic = "character", naics = "character"))
ED <- L0[, .(pages = uniqueN(paste(source_volume, page)), listings = .N, parts = uniqueN(source_volume), pct_no_code = round(100 * mean(sic == "" & naics == ""), 1)), by = year]
CMP_state <- merge(CMP_state, ED, by = "year", all.x = TRUE)
fwrite(CMP_state, file.path(O, "cbp_vs_directory_state.csv"))
CC <- CMP[!is.na(cbp_mfg) & year %in% DIR$year][, .(year, county, county_name, cbp_mfg, cbp_haz, dir_mfg, dir_haz, dir_all, dir_street)][order(year, -cbp_mfg)]
for (k in c("dir_mfg", "dir_haz", "dir_all", "dir_street")) CC[is.na(get(k)), (k) := 0L]
CC[, `:=`(ratio_mfg = round(dir_mfg / cbp_mfg, 2), ratio_haz = round(dir_haz / pmax(cbp_haz, 1), 2))]
fwrite(CC, file.path(O, "cbp_vs_directory_county.csv"))
print(CMP_state[year %in% c(1976, 1980, 1985, 1990, 1993, 1999, 2002)])
# county-level fit in the editions with CBP (the median ratio leaves out county-years with no CBP manufacturer, where the ratio is undefined)
fit <- CC[dir_all > 0, .(editions = uniqueN(year), counties = uniqueN(county), r_mfg = round(cor(log1p(dir_mfg), log1p(cbp_mfg)), 3), r_haz = round(cor(log1p(dir_haz), log1p(cbp_haz)), 3),
                        median_ratio_mfg = round(median((dir_mfg / cbp_mfg)[cbp_mfg > 0]), 2), denver_ratio_mfg = round(median((dir_mfg / cbp_mfg)[county == "031"]), 2))]
print(fit)

# ---------------------------------------------------------------- 2. NHGIS county manufacturing 1880-1940 vs the business directory
NH <- NULL
if (nzchar(Sys.getenv("IPUMS_API_KEY")) && requireNamespace("ipumsr", quietly = TRUE)) {
  library(ipumsr)   # ipumsr reads IPUMS_API_KEY from the environment (~/.Renviron); nothing is written there
  ds <- as.data.table(get_metadata_catalog("nhgis", metadata_type = "datasets"))
  mf <- file.path(W, "nhgis_mfg_county_v3.csv")   # v3: county codes read from the right GISJOIN characters (v2 dropped the hundreds digit)
  if (!length(Sys.glob(file.path(W, "nhgis*_csv", "*_county.csv")))) { specs <- list()
    for (dname in ds[grepl("^(1880|1890|1900|1910|1920|1930|1940)", group)]$name) {
      md <- tryCatch(get_metadata("nhgis", dataset = dname), error = function(e) NULL); if (is.null(md) || !"county" %in% md$geog_levels$name) next
      tb <- as.data.table(md$data_tables)[grepl("Manufactur", description, ignore.case = TRUE) & grepl("Establishment|Wage Earner|Value of Product|Capital", description, ignore.case = TRUE)]
      if (nrow(tb)) { message(dname, ": ", paste(tb$name, collapse = " ")); specs[[dname]] <- ds_spec(dname, data_tables = tb$name, geog_levels = "county") } }
    if (length(specs)) { ex <- wait_for_extract(submit_extract(define_extract_agg("nhgis", description = "Colorado counties: manufacturing 1880-1940", datasets = unname(specs), geographic_extents = "080")))
      z <- download_extract(ex, download_dir = W, overwrite = TRUE); unzip(z, exdir = W) } }
  if (!file.exists(mf)) {
    rows <- rbindlist(lapply(Sys.glob(file.path(W, "nhgis*_csv", "*_county.csv")), function(f) { d <- as.data.table(read_ipums_agg(f, verbose = FALSE)); cbf <- sub("\\.csv$", "_codebook.txt", f); if (!file.exists(cbf)) return(NULL)
      tab <- ""; vars <- list()
      for (ln in readLines(cbf)) { if (grepl("^\\s*Table \\d+:", ln)) tab <- trimws(sub("^\\s*Table \\d+:\\s*", "", ln)); m <- regmatches(ln, regexec("^\\s+([A-Z0-9]{3,6}):\\s+(.*)$", ln))[[1]]; if (length(m) == 3 && m[2] %in% names(d)) vars[[m[2]]] <- c(tab, m[3]) }
      yr <- as.integer(sub(".*_ds\\d+_(\\d{4})_county\\.csv$", "\\1", f)); v <- names(vars); if (!length(v)) return(NULL); tabs <- vapply(vars, `[`, "", 1)
      est <- v[grepl("^(Total Number of |Number of )?Manufacturing Establishments( Reporting)?(, 19\\d\\d)?$", tabs)][1]
      we <- v[grepl("^(Average Number of |Annual Average )?Wage Earners in Manufacturing( Industries)?(, 19\\d\\d)?$|^Average Number of Employees of All Classes", tabs)][1]
      vp <- v[grepl("^(Total )?Value of (All )?Products", tabs)][1]
      message(yr, ": establishments = ", est, " (", if (!is.na(est)) vars[[est]][1], "); wage earners = ", we, "; value of products = ", vp)
      data.table(census = yr, nhgis_cty = as.integer(substr(d$GISJOIN, 5, 8)), county = gisjoin_county(d$GISJOIN), county_nhgis = d$COUNTY, mfg_estab = if (is.na(est)) NA_real_ else as.numeric(d[[est]]), wage_earners = if (is.na(we)) NA_real_ else as.numeric(d[[we]]),
                 value_products = if (is.na(vp)) NA_real_ else as.numeric(d[[vp]]), estab_label = if (is.na(est)) NA_character_ else vars[[est]][1]) }), fill = TRUE)
    fwrite(rows, mf) }
  if (file.exists(mf)) NH <- fread(mf, colClasses = c(county = "character"))
} else message("NHGIS step skipped: no IPUMS_API_KEY in the environment (set it in ~/.Renviron) or ipumsr not installed")
if (!is.null(NH) && nrow(NH)) {
  # each directory firm goes to the county in force at that census, not today's county (Denver County exists only from 1902: a Denver firm of
  # 1880-1900 is in Arapahoe). The firms' points are placed in the census's own NHGIS county polygons (app/data/co_counties_1880_1940.geojson,
  # written by R/county_panel_1880_1940.R; icp = NHGISCTY). 1890 has no polygons there, so it uses the 1900 ones with Teller (1899) put back in El Paso.
  H <- fread("app/data/historical_sites.csv")[fe_hazard %in% c(TRUE, "True") & !is.na(lat)]
  CP <- st_read("app/data/co_counties_1880_1940.geojson", quiet = TRUE)[, c("icp", "census")]; hp <- st_transform(st_as_sf(H[, .(hfirm, lon, lat)], coords = c("lon", "lat"), crs = 4326), st_crs(CP))
  in_force <- function(cy) { by <- if (cy %in% CP$census) cy else if (cy == 1890) 1900 else CP$census[which.min(abs(CP$census - cy))]
    S <- CP[CP$census == by, ]; k <- vapply(suppressMessages(st_intersects(hp, S)), function(i) if (length(i)) i[1] else NA_integer_, 1L)
    v <- S$icp[k]; if (cy < 1899) v[v %in% 1190L] <- 410L; v }
  ED_YRS <- sort(unique(as.integer(unlist(strsplit(as.character(H$years), "[^0-9]+"))))); ED_YRS <- ED_YRS[!is.na(ED_YRS)]
  has_ed <- function(cy) has_edition(cy, ED_YRS)   # see has_edition above: a directory edition within two years of the census
  HD <- rbindlist(lapply(Filter(has_ed, sort(unique(NH$census))), function(cy) H[, nhgis_cty := in_force(cy)][!is.na(nhgis_cty) & first_year <= cy + 2 & last_year >= cy - 2,
    .(census = cy, dir_haz = .N, dir_street = sum(precision != "town")), by = nhgis_cty]))
  NH <- NH[vapply(census, has_ed, TRUE)]; message("NHGIS censuses with a directory edition within two years: ", paste(sort(unique(NH$census)), collapse = " "))
  NH[, county_name := cty_names[county]]; NB <- merge(NH[!is.na(mfg_estab)], HD, by = c("census", "nhgis_cty"), all.x = TRUE)
  for (k in c("dir_haz", "dir_street")) NB[is.na(get(k)), (k) := 0L]
  NB[, ratio_haz_to_census := round(dir_haz / pmax(mfg_estab, 1), 2)]; setorder(NB, census, -mfg_estab)
  fwrite(NB[, .(census, county, county_name, mfg_estab, wage_earners, value_products, dir_haz, dir_street, ratio_haz_to_census, estab_label)], file.path(O, "nhgis_mfg_vs_directory.csv"))
  print(NB[, .(counties = .N, census_mfg_estab = sum(mfg_estab), directory_haz_trades = sum(dir_haz), r_log = round(cor(log1p(mfg_estab), log1p(dir_haz)), 2)), by = census])
}

# ---------------------------------------------------------------- 3. Atack-Bateman-Weiss 1870/1880 establishment samples
AT <- NULL
for (y in c(1870, 1880)) { f <- file.path(W, "atack", sprintf("%dStateSamples.xlsx", y))
  if (!file.exists(f)) tryCatch(download.file(sprintf("https://cdn.vanderbilt.edu/t2-my/my-prd/wp-content/uploads/sites/133/2011/08/%dStateSamples.xlsx", y), f, mode = "wb", quiet = TRUE), error = function(e) message("could not download the Atack ", y, " sample: ", conditionMessage(e)))
  if (file.exists(f) && requireNamespace("readxl", quietly = TRUE)) { sh <- readxl::excel_sheets(f)
    d <- as.data.table(readxl::read_excel(f, sheet = sh[1], guess_max = 50000)); nm <- names(d); message("Atack ", y, ": ", nrow(d), " establishments; columns: ", paste(head(nm, 40), collapse = ", "))
    sc <- nm[grepl("^state", nm, ignore.case = TRUE)][1]; if (is.na(sc)) next
    sv <- as.character(d[[sc]]); co <- d[grepl("colorado|^co$", sv, ignore.case = TRUE) | sv %in% c("8", "08", "62")]   # name, FIPS 08 or ICPSR state code 62 (the samples use ICPSR codes)
    if (!nrow(co)) { message("Atack ", y, ": no Colorado rows (state column '", sc, "', values e.g. ", paste(head(unique(d[[sc]]), 8), collapse = ", "), ")"); next }
    co[, year := y]; AT <- rbindlist(list(AT, co), fill = TRUE) } }
if (!is.null(AT) && nrow(AT)) { fwrite(AT, file.path(O, "atack_colorado.csv")); message("Atack samples: ", nrow(AT), " Colorado establishments written to ", file.path(O, "atack_colorado.csv"))
  # by 2-digit industry (the samples carry SIC-style industry codes), against the business directory's hazardous trades listed 1878-1885 statewide
  ic <- names(AT)[grepl("^industry$", names(AT), ignore.case = TRUE)][1]
  if (!is.na(ic)) { AT[, sic2 := substr(sprintf("%03d", as.integer(get(ic))), 1, 2)]
    SICN <- c("20"="Food","21"="Tobacco","22"="Textiles","23"="Apparel","24"="Lumber & wood","25"="Furniture","26"="Paper","27"="Printing","28"="Chemicals","29"="Petroleum","30"="Rubber & leather goods","31"="Leather","32"="Stone, clay & glass","33"="Primary metals","34"="Fabricated metals","35"="Machinery","36"="Electrical","37"="Transportation equipment","38"="Instruments","39"="Miscellaneous")
    AB <- AT[, .(establishments = .N, workers = sum(suppressWarnings(as.numeric(MEN)) + suppressWarnings(as.numeric(WOMEN)) + suppressWarnings(as.numeric(CHILDREN)), na.rm = TRUE), capital = sum(suppressWarnings(as.numeric(CAPITAL)), na.rm = TRUE)), by = .(year, sic2)]
    AB[, `:=`(sector = ifelse(is.na(SICN[sic2]), paste("SIC", sic2), SICN[sic2]), hazardous = sic2 %in% HAZ_SIC)]; setorder(AB, year, -establishments)
    H80 <- fread("app/data/historical_sites.csv")[fe_hazard %in% c(TRUE, "True") & first_year <= 1885 & last_year >= 1878]
    AB[, directory_haz_1878_85 := NA_integer_]; AB[hazardous == TRUE, directory_haz_1878_85 := nrow(H80)]   # the directory total, repeated on the hazardous rows for the app table
    fwrite(AB, file.path(O, "atack_colorado_by_sector.csv")); file.copy(file.path(O, "atack_colorado_by_sector.csv"), A, overwrite = TRUE)
    message("Atack 1880 Colorado: ", sum(AB$establishments[AB$hazardous & AB$year == 1880]), " sampled establishments in Frickel & Elliott sectors; business directory hazardous trades 1878-85: ", nrow(H80)) } }

# ---------------------------------------------------------------- summary and app copies
file.copy(file.path(O, c("cbp_vs_directory_state.csv", "cbp_vs_directory_county.csv")), A, overwrite = TRUE)
if (file.exists(file.path(O, "nhgis_mfg_vs_directory.csv"))) file.copy(file.path(O, "nhgis_mfg_vs_directory.csv"), A, overwrite = TRUE)
md <- c("# Benchmarks: the Colorado directories against the public national manufacturing series", "",
        "## 1975-2002: County Business Patterns (establishments) vs the Directory of Colorado Manufacturers", "",
        "| year | CBP manufacturing estab. | directory manufacturers | ratio | CBP hazardous-sector estab. | directory hazardous | ratio |", "|---|---|---|---|---|---|---|",
        CMP_state[!is.na(dir_all), sprintf("| %d | %s | %s | %.2f | %s | %s | %.2f |", year, format(cbp_mfg, big.mark = ","), format(dir_mfg, big.mark = ","), ratio_mfg, format(cbp_haz, big.mark = ","), format(dir_haz, big.mark = ","), ratio_haz)], "",
        sprintf("County-level agreement across %d editions and %d counties: r = %.2f (log manufacturers), %.2f (log hazardous sectors); median directory/CBP ratio %.2f (Denver %.2f).",
                fit$editions, fit$counties, fit$r_mfg, fit$r_haz, fit$median_ratio_mfg, fit$denver_ratio_mfg), "",
        "CBP counts every employer establishment with a payroll (from administrative records); the directory lists firms that answered the publisher's questionnaire or were",
        "copied from other lists, so it undercounts the smallest establishments and the ratio is a coverage rate. CBP has no addresses: it cannot replace the directory for siting.",
        "Raw county files from Eckert, Fort, Schott & Yang (2021), NBER WP 26632 (github.com/fpeckert/website, release cbp-data); 1975-85 from the National Archives, 1986+ from the Census Bureau.", "")
if (file.exists(file.path(O, "nhgis_mfg_vs_directory.csv"))) { NBs <- fread(file.path(O, "nhgis_mfg_vs_directory.csv"))[, .(counties = .N, census_estab = sum(mfg_estab), directory_haz = sum(dir_haz)), by = census]
  md <- c(md, "## 1880-1940: census manufacturing establishments by county (NHGIS) vs the business directory's hazardous trades", "",
          "| census | counties | census manufacturing establishments | directory hazardous trades (+/- 2 years) |", "|---|---|---|---|", NBs[, sprintf("| %d | %d | %s | %s |", census, counties, format(census_estab, big.mark = ","), format(directory_haz, big.mark = ","))], "",
          "Censuses with no directory edition within two years are left out (1900: none between 1892 and 1910). The business directory only lists the hazardous trades, so the ratio is a floor on its coverage of all manufacturing; the census counts every establishment above a small output threshold.", "") }
md <- c(md, "## 1870 and 1880: Atack-Bateman-Weiss Census of Manufactures samples", "",
        if (!is.null(AT) && nrow(AT)) sprintf("%d Colorado establishments in the state samples (1870: %d, 1880: %d); see atack_colorado.csv.", nrow(AT), sum(AT$year == 1870), sum(AT$year == 1880)) else "No Colorado rows found in the downloaded state samples, or the files could not be downloaded (see the run log).",
        "These are samples of surviving manuscript schedules (not a complete census) and give the county and industry of each establishment, its capital, workers and output, but no street address.",
        "The Census Longitudinal Business Database (1976+) tracks individual establishments nationally but is restricted-access; it is the only national source at the establishment level for the directory era.")
writeLines(md, file.path(O, "benchmarks_summary.md")); message("wrote ", file.path(O, "benchmarks_summary.md"))
