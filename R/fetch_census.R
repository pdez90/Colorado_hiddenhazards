# Download the historical census data for R/ej_panel.R through the IPUMS NHGIS API (needs a free NHGIS account + API key).
#
#   1. Get an API key at https://account.ipums.org/api_keys  (log in with your NHGIS account, "Create API key").
#   2. In Terminal:   export IPUMS_API_KEY=paste_your_key_here
#                     Rscript R/fetch_census.R
#   The key is read from the environment only; it is never written to disk or to the repository.
#
# What it requests (everything at the census-tract level, Colorado only, into work/census/):
#   A. Time-series tables STANDARDIZED TO 2010 TRACT BOUNDARIES, 1970-2020: total population, persons by race, persons by Hispanic
#      origin, nativity (foreign born) and poverty where NHGIS offers them standardized. These replace Brown's LTDB.
#   B. The 2010 tract boundary file (for the panel's geography and areal interpolation).
#   C. 1940, 1950 and 1960 tract tables for Denver (population, race / nonwhite, foreign-born white, median rent or income) plus the
#      tract boundary files of those years (NHGIS has tracts for Denver in all three).
# It then builds work/census/denver_tract_panel.csv (GEOID, census, pop, nhblk, hisp, fb, ppov) which R/ej_panel.R reads first.
# NHGIS table codes change; the script finds tables by their descriptions and prints what it chose - check that list.
if (!requireNamespace("ipumsr", quietly = TRUE)) install.packages("ipumsr")
suppressPackageStartupMessages({ library(ipumsr); library(data.table); library(sf) })
key <- Sys.getenv("IPUMS_API_KEY"); if (!nzchar(key)) stop("set IPUMS_API_KEY first (see header)")
set_ipums_api_key(key, overwrite = TRUE)
dir.create("work/census", showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------- A+B. standardized time series, 1970-2020
tst <- get_metadata_nhgis("time_series_tables")
std <- tst[grepl("2010", tst$geographic_integration) & grepl("tract", sapply(tst$geog_levels, function(g) paste(g$name, collapse = " ")), ignore.case = TRUE), ]
pick_tst <- function(pattern) { m <- std[grepl(pattern, std$description, ignore.case = TRUE), ]; if (!nrow(m)) return(NULL)
  m <- m[order(-sapply(m$years, nrow)), ][1, ]; message("  ", m$name, ": ", m$description, " [", paste(range(m$years[[1]]$name), collapse = "-"), "]"); m$name }
message("Standardized (2010 tract) time-series tables chosen:")
want <- c(total = "^Total Population$", race = "^Persons by Race", hisp = "Hispanic or Latino Origin$", fb = "Nativity|Foreign", pov = "Poverty")
codes <- sapply(want, pick_tst); codes <- codes[!sapply(codes, is.null)]
ext_a <- define_extract_nhgis(description = "Colorado tracts 1970-2020, standardized to 2010",
  time_series_tables = lapply(codes, function(cd) tst_spec(cd, geog_levels = "tract")), tst_layout = "time_by_row_layout",
  geographic_extents = "080", shapefiles = "us_tract_2010_tl2010")
sub_a <- submit_extract(ext_a); message("submitted extract ", sub_a$number, " (standardized 1970-2020)")

# ---------------------------------------------------------------- C. 1940-1960 tract tables (nominal boundaries of each year)
ds <- get_metadata_nhgis("datasets")
old_ds <- ds[grepl("^(1940|1950|1960)", ds$group) & grepl("tract", sapply(ds$geog_levels, function(g) paste(g$name, collapse = " ")), ignore.case = TRUE), ]
specs <- list(); shp <- character()
for (dname in unique(old_ds$name)) {
  md <- get_metadata_nhgis(dataset = dname); if (!"tract" %in% md$geog_levels$name) next
  tabs <- md$data_tables
  keep <- tabs[grepl("^Total Population$|Race|Nonwhite|Negro|Nativity|Foreign|Median (Contract |Gross )?Rent|Median (Family )?Income|Country of Birth", tabs$description, ignore.case = TRUE), ]
  if (!nrow(keep)) next
  message(dname, ": ", paste(keep$name, keep$description, sep = " = ", collapse = "; "))
  specs[[dname]] <- ds_spec(dname, data_tables = keep$name, geog_levels = "tract")
  yr <- substr(dname, 1, 4); shp <- union(shp, md$shapefiles$name[grepl(paste0("tract_", yr), md$shapefiles$name)][1])
}
ext_c <- define_extract_nhgis(description = "Colorado tracts 1940-1960", datasets = unname(specs), shapefiles = shp[!is.na(shp)], geographic_extents = "080")
sub_c <- submit_extract(ext_c); message("submitted extract ", sub_c$number, " (1940-1960)")

# ---------------------------------------------------------------- wait, download, unpack
for (sb in list(sub_a, sub_c)) { sb <- wait_for_extract(sb); files <- download_extract(sb, download_dir = "work/census", overwrite = TRUE)
  for (f in files) unzip(f, exdir = "work/census", overwrite = TRUE) }
message("downloaded to work/census/")

# ---------------------------------------------------------------- build the harmonized 1970-2020 panel (2010 tracts)
csvs <- Sys.glob("work/census/*/*_ts_geog2010_tract.csv"); if (!length(csvs)) csvs <- Sys.glob("work/census/**/*ts*tract*.csv")
D <- read_nhgis(csvs[1], verbose = FALSE); D <- as.data.table(D)
lab <- sapply(D, function(x) attr(x, "label")); lab[is.na(lab)] <- names(D)[is.na(lab)]
col_by <- function(pattern, exclude = NULL) { k <- names(lab)[grepl(pattern, lab, ignore.case = TRUE) & !grepl(paste(c("^$", exclude), collapse = "|"), lab, ignore.case = TRUE) & !grepl("MOE|margin", lab, ignore.case = TRUE)]; k[1] }
m <- c(pop = col_by("^Persons: Total$|^Total population$|^Persons$"), nhblk = col_by("Black|Negro", exclude = "Not"), hisp = col_by("^Persons: Hispanic or Latino$|Hispanic or Latino \\(any race\\)|^Persons: Hispanic", exclude = "Not Hispanic"),
       fb = col_by("Foreign born|Foreign-born"), ppov = col_by("below poverty|Income .* below"))
message("column mapping (check!): ", paste(names(m), m, sep = " = ", collapse = "; "))
yrcol <- grep("^YEAR$", names(D), value = TRUE); geo <- grep("^GISJOIN", names(D), value = TRUE)[1]
P <- data.table(GEOID = sub("^G(\\d{2})0(\\d{3})0(\\d{6})$", "\\1\\2\\3", D[[geo]]), census = as.integer(substr(D[[yrcol]], 1, 4)))
for (k in names(m)) P[[k]] <- if (!is.na(m[[k]])) as.numeric(D[[m[[k]]]]) else NA_real_
P <- P[substr(GEOID, 1, 2) == "08"]
fwrite(P, "work/census/denver_tract_panel.csv"); message("wrote work/census/denver_tract_panel.csv: ", nrow(P), " tract-years, ", paste(sort(unique(P$census)), collapse = " "))
shp10 <- Sys.glob("work/census/**/*tract_2010*.shp"); if (length(shp10)) file.copy(Sys.glob(sub("\\.shp$", ".*", shp10[1])), "work/census/", overwrite = TRUE)
message("Now run:  Rscript R/ej_panel.R")
