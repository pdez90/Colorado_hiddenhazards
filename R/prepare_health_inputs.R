# Prepare the inputs of the tract and block-group health models (R/build_exposures.R, R/health_models.R, R/mortality_bg.R) in work/health/.
#   Rscript R/prepare_health_inputs.R                                   (defaults below)
#   Rscript R/prepare_health_inputs.R /path/to/CO_HIA /path/to/enviroscreen_v2_blockgroups.geojson
# Inputs, read in place:
#   CO_HIA/co_deaths_official.csv  Colorado death records 2000-2020 (restricted; yr, fipscoor, tract, bgroup, all_cause, natural_cause)
#   CO_HIA/bgroup_noyr.gpkg        2010 block groups with yearly population (pop_2000-2020) and PM2.5 (pm_YYYY)
#   enviroscreen_v2_blockgroups.geojson  CDPHE Colorado EnviroScreen 2.0 block groups (public; downloaded by hand from CDPHE as a
#                                  shapefile and converted to GeoJSON, which is why its fields carry shapefile-truncated names)
# Outputs (work/ is git-ignored and never committed): work/health/deaths_bg_year.csv (deaths by 2010 block group x year x natural cause,
# aggregated from the records; it stays on this machine), work/health/bgroup_noyr.gpkg and work/health/enviroscreen_v2_blockgroups.geojson
# (copies). Only rate ratios and coefficients leave the machine, through the model scripts.
suppressPackageStartupMessages({ library(data.table) })
args <- commandArgs(trailingOnly = TRUE)
HIA <- path.expand(if (length(args) >= 1) args[1] else "~/Downloads/CO_HIA")
ESF <- path.expand(if (length(args) >= 2) args[2] else "~/Downloads/enviroscreen_v2_blockgroups.geojson")
for (f in c(file.path(HIA, "co_deaths_official.csv"), file.path(HIA, "bgroup_noyr.gpkg"), ESF)) if (!file.exists(f)) stop("missing input: ", f)
for (p in c("sf", "spdep", "spatialreg", "MASS", "sandwich", "lmtest"))
  if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
dir.create("work/health", showWarnings = FALSE, recursive = TRUE)

X <- fread(file.path(HIA, "co_deaths_official.csv"), colClasses = "character", select = c("yr", "fipscoor", "tract", "bgroup", "all_cause", "natural_cause"))
X <- X[all_cause == "1"]
X[, bg := paste0("08", fipscoor, tract, bgroup)]
bad <- X[nchar(bg) != 12 | grepl("[^0-9]", bg), .N]
message(sprintf("%d deaths; %d with an incomplete block-group code are dropped", nrow(X), bad))
X <- X[nchar(bg) == 12 & !grepl("[^0-9]", bg)]
D <- X[, .(deaths = .N), by = .(bg, year = as.integer(yr), natural_cause = as.integer(natural_cause == "1"))]
setorder(D, bg, year, natural_cause); fwrite(D, "work/health/deaths_bg_year.csv")
stopifnot(file.copy(file.path(HIA, "bgroup_noyr.gpkg"), "work/health/bgroup_noyr.gpkg", overwrite = TRUE),
          file.copy(ESF, "work/health/enviroscreen_v2_blockgroups.geojson", overwrite = TRUE))
g <- sf::st_read("work/health/bgroup_noyr.gpkg", quiet = TRUE); need <- c("bg", paste0("pop_", 2015:2019), paste0("pm_", 2015:2019))
if (length(setdiff(need, names(g)))) stop("bgroup_noyr.gpkg lacks: ", paste(setdiff(need, names(g)), collapse = ", "))
message(sprintf("work/health ready: %s block groups, deaths 2015-2019 %s (natural causes %s)", format(nrow(g), big.mark = ","),
                format(D[year %in% 2015:2019, sum(deaths)], big.mark = ","), format(D[year %in% 2015:2019 & natural_cause == 1, sum(deaths)], big.mark = ",")))
