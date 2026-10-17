# R port of pipeline/health/build_exposures.py: site-density exposures at block-group points, averaged to tracts.
#   Rscript R/build_exposures.R      -> work/health/tract_analysis_R.csv, work/health/bg_exposures_R.csv
# Inputs: work/health/enviroscreen_v2_blockgroups.geojson (CDPHE EnviroScreen 2.0 block groups), app/data/sites.csv,
# app/data/tri_facilities.csv, app/data/cleanup_sites.csv, app/data/historical_sites.csv, app/data/enviroscreen_tracts.geojson,
# data/results/CO_directory_listings_1961-2002.csv (for the non-hazardous placebo manufacturers).
suppressPackageStartupMessages({ library(sf); library(data.table) })
UTM <- 26913; SIG <- 500; CUT <- 2000

bg <- st_transform(st_read("work/health/enviroscreen_v2_blockgroups.geojson", quiet = TRUE), UTM)
bg$GEOID <- formatC(as.character(bg$GEOID), width = 12, flag = "0"); bg$tract <- substr(bg$GEOID, 1, 11)
cent <- st_coordinates(suppressWarnings(st_point_on_surface(st_geometry(bg))))

xy <- function(df) { df <- df[!is.na(df$lat) & !is.na(df$lon), ]
  st_coordinates(st_transform(st_as_sf(df, coords = c("lon", "lat"), crs = 4326), UTM)) }

# sites and records: the Python outputs by default, or R/build_sites.R outputs (Rscript R/build_exposures.R work/inv/sites_app_R.csv work/inv/records_sites_R.csv)
args <- commandArgs(trailingOnly = TRUE)
sites_f <- if (length(args) >= 1) args[1] else "app/data/sites.csv"
recs_f <- if (length(args) >= 2) args[2] else "data/results/CO_directory_listings_1961-2002.csv"
S0 <- fread(sites_f); S <- S0[fe_hazard == TRUE]
L <- fread(recs_f)
hz_ids <- S0$site_id
nh <- L[geo_level == "address" & !(fe_hazard | ext_hazard) & !(site_id %in% hz_ids)]
nh <- nh[!duplicated(paste0(sprintf("%.4f", lat), sprintf("%.4f", lon)))]
Pn <- xy(as.data.frame(nh)); Hx <- xy(as.data.frame(S))
dmin <- apply(Pn, 1, function(p) sqrt(min((Hx[, 1] - p[1])^2 + (Hx[, 2] - p[2])^2)))
H <- fread("app/data/historical_sites.csv")
groups <- list(
  hidden = S[radar == "Not on any list"], hidden_hiconf = S[radar == "Not on any list" & confidence == "high"],
  known_hist = S[radar != "Not on any list"], hist_all = S,
  hidden_persist10 = S[radar == "Not on any list" & (last_year - first_year) >= 10],
  tri = fread("app/data/tri_facilities.csv"), cleanup = fread("app/data/cleanup_sites.csv"),
  placebo = nh[dmin > 100], pre1960 = H[precision != "town"])

out <- data.table(GEOID = bg$GEOID, tract = bg$tract)
for (nm in names(groups)) {
  P <- xy(as.data.frame(groups[[nm]])); kd <- n1k <- numeric(nrow(cent))
  for (i in seq_len(nrow(cent))) {
    d <- sqrt((P[, 1] - cent[i, 1])^2 + (P[, 2] - cent[i, 2])^2); d <- d[d <= CUT]
    if (length(d)) { kd[i] <- sum(exp(-0.5 * (d / SIG)^2)); n1k[i] <- sum(d <= 1000) }
  }
  out[[paste0(nm, "_kd")]] <- kd; out[[paste0(nm, "_n1k")]] <- n1k
  message(nm, ": ", nrow(P), " sites")
}
num <- function(c) suppressWarnings(as.numeric(bg[[c]]))
cov <- c(low_income = "Prcnt_lw_", people_of_color = "Prc___", less_than_hs = "Pr_____", ling_iso = "Prcnt_ln_", over64 = "Pp__64",
         under5 = "Pp__5", prox_hazwaste = "Prxmty_t_h", prox_npl = "Pr__N_P_L_", prox_rmp = "Pr__R_M_P_", prox_mining = "Prx___",
         prox_oilgas = "Prxmty_t_l", diesel_pm = "Ds____PM_", traffic = "Tr____", pm25 = "Fn_p_", ozone = "Ozone", air_toxics = "Ar_t_")
for (k in names(cov)) out[[k]] <- num(cov[[k]])
out$area_km2 <- as.numeric(st_area(bg)) / 1e6
fwrite(out, "work/health/bg_exposures_R.csv")

outc <- c(asthma_hosp = "Ast__", low_birth_wt = "Lw_b_", life_exp = "Lf_xp", heart_dis = "Hr___", cancer = "Cncr_", diabetes = "Dbts_",
          mental_health = "Mnt__")
O <- data.table(tract = bg$tract); for (k in names(outc)) O[[k]] <- num(outc[[k]])
O <- O[, lapply(.SD, `[`, 1), by = tract]                      # identical within a tract
mcols <- setdiff(names(out), c("GEOID", "tract", "area_km2"))
X <- out[, c(lapply(.SD, mean), list(area_km2 = sum(area_km2), n_bg = .N)), by = tract, .SDcols = mcols]
TT <- st_drop_geometry(st_read("app/data/enviroscreen_tracts.geojson", quiet = TRUE))[, c("GEOID", "population", "county")]
TT$tract <- formatC(as.character(TT$GEOID), width = 11, flag = "0"); TT$GEOID <- NULL
A <- merge(merge(O, X, by = "tract"), as.data.table(TT), by = "tract", all.x = TRUE)
A$pop_density <- A$population / A$area_km2
fwrite(A, "work/health/tract_analysis_R.csv")
message("tracts: ", nrow(A))
