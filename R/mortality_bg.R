# R port of pipeline/health/mortality_bg.py: block-group natural-cause mortality 2015-2019, negative binomial with county
# fixed effects, offset log person-years, tract-clustered SE. Restricted inputs stay on the analyst's machine:
#   work/health/deaths_bg_year.csv (bg, year, natural_cause, deaths), work/health/bgroup_noyr.gpkg (2010 BGs, pop_YYYY, pm_YYYY).
#   Rscript R/mortality_bg.R   -> data/results/mortality_bg_models_R.csv (rate ratios only; no small-area counts)
suppressPackageStartupMessages({ library(sf); library(data.table); library(MASS); library(sandwich); library(lmtest) })
UTM <- 26913; Y0 <- 2015; Y1 <- 2019; yrs <- Y0:Y1
g <- st_transform(st_read("work/health/bgroup_noyr.gpkg", quiet = TRUE), UTM)
g$bg <- formatC(as.character(g$bg), width = 12, flag = "0")
G <- as.data.table(st_drop_geometry(g))
g$pyears <- rowSums(G[, paste0("pop_", yrs), with = FALSE]); g$pm25 <- rowMeans(G[, paste0("pm_", yrs), with = FALSE])
d <- fread("work/health/deaths_bg_year.csv", colClasses = c(bg = "character"))[year >= Y0 & year <= Y1]
nat <- d[natural_cause == 1, .(deaths_nat = sum(deaths)), by = bg]; allc <- d[, .(deaths_all = sum(deaths)), by = bg]
g <- merge(merge(g, nat, by = "bg", all.x = TRUE), allc, by = "bg", all.x = TRUE)
g$deaths_nat[is.na(g$deaths_nat)] <- 0; g$deaths_all[is.na(g$deaths_all)] <- 0

# EnviroScreen 2.0 (2020 block groups) covariates -> 2010 block groups, area-weighted
es <- st_transform(st_read("work/health/enviroscreen_v2_blockgroups.geojson", quiet = TRUE), UTM)
cov <- c(low_income = "Prcnt_lw_", people_of_color = "Prc___", less_than_hs = "Pr_____", ling_iso = "Prcnt_ln_", over64 = "Pp__64",
         under5 = "Pp__5", prox_hazwaste = "Prxmty_t_h", prox_npl = "Pr__N_P_L_", prox_rmp = "Pr__R_M_P_", diesel_pm = "Ds____PM_", traffic = "Tr____")
for (k in names(cov)) es[[k]] <- suppressWarnings(as.numeric(es[[cov[[k]]]]))
ov <- suppressWarnings(st_intersection(st_make_valid(g[, "bg"]), st_make_valid(es[, names(cov)])))
ov <- ov[st_geometry_type(ov) %in% c("POLYGON", "MULTIPOLYGON"), ]
ov$a <- as.numeric(st_area(ov)); O <- as.data.table(st_drop_geometry(ov))
W <- O[, lapply(.SD, function(x) { x[is.na(x)] <- if (all(is.na(x))) 0 else mean(x, na.rm = TRUE); weighted.mean(x, a) }), by = bg, .SDcols = names(cov)]
g <- merge(g, W, by = "bg", all.x = TRUE)
g$area_km2 <- as.numeric(st_area(g)) / 1e6; g$log_density <- log1p(g[[paste0("pop_", Y1)]] / g$area_km2); g$tract <- substr(g$bg, 1, 11)

CP <- st_coordinates(suppressWarnings(st_point_on_surface(st_geometry(g))))
xy <- function(df) { df <- df[!is.na(df$lat) & !is.na(df$lon), ]; st_coordinates(st_transform(st_as_sf(df, coords = c("lon", "lat"), crs = 4326), UTM)) }
args <- commandArgs(trailingOnly = TRUE)   # optional: R/build_sites.R outputs instead of the Python ones
S0 <- fread(if (length(args) >= 1) args[1] else "app/data/sites.csv"); S <- S0[fe_hazard == TRUE]
L <- fread(if (length(args) >= 2) args[2] else "data/results/CO_directory_listings_1961-2002.csv")
nh <- L[geo_level == "address" & !(fe_hazard | ext_hazard) & !(site_id %in% S0$site_id)]
nh <- nh[!duplicated(paste0(round(lat, 4), round(lon, 4)))]
Hx <- xy(as.data.frame(S)); Pn <- xy(as.data.frame(nh))
nh <- nh[apply(Pn, 1, function(p) sqrt(min((Hx[, 1] - p[1])^2 + (Hx[, 2] - p[2])^2))) > 100]
groups <- list(hidden = S[radar == "Not on any list"], hidden_hiconf = S[radar == "Not on any list" & confidence == "high"],
               known_hist = S[radar != "Not on any list"], tri = fread("app/data/tri_facilities.csv"),
               cleanup = fread("app/data/cleanup_sites.csv"), placebo = nh)
zz <- function(x) { x <- log1p(x); (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE) }
for (k in names(groups)) { P <- xy(as.data.frame(groups[[k]]))
  kd <- vapply(seq_len(nrow(CP)), function(i) { dd <- sqrt((P[, 1] - CP[i, 1])^2 + (P[, 2] - CP[i, 2])^2); dd <- dd[dd <= 2000]; sum(exp(-0.5 * (dd / 500)^2)) }, 0)
  g[[paste0("z_", k)]] <- zz(kd) }
for (c in c("prox_hazwaste", "prox_npl", "prox_rmp")) g[[paste0("z_", c)]] <- zz(g[[c]])

D <- as.data.table(st_drop_geometry(g))[pyears >= 2500]
D <- na.omit(D, cols = c(names(cov), "pm25", "log_density", "fipscoor", grep("^z_", names(D), value = TRUE)))
D <- D[is.finite(log_density)]; D[, log_py := log(pyears)]; D[, fipscoor := factor(fipscoor)]
SES <- "low_income + people_of_color + less_than_hs + ling_iso + over64 + I(over64^2) + under5 + log_density + pm25 + fipscoor"
REG <- " + z_prox_hazwaste + z_prox_npl + z_prox_rmp + z_tri + z_cleanup"
specs <- c("M1 SES+age+PM2.5" = SES, "M2 +regulated" = paste0(SES, REG), "M3 +known historical" = paste0(SES, REG, " + z_known_hist"),
           "M4 +hidden" = paste0(SES, REG, " + z_known_hist + z_hidden"),
           "M4 hidden high-confidence only" = paste0(SES, REG, " + z_known_hist + z_hidden_hiconf"),
           "Placebo: M2 +non-hazardous mfrs" = paste0(SES, REG, " + z_placebo"), "M4 +placebo" = paste0(SES, REG, " + z_known_hist + z_hidden + z_placebo"))
rows <- list()
for (y in c("deaths_nat", "deaths_all")) {
  theta <- glm.nb(as.formula(paste(y, "~", specs[["M4 +placebo"]], "+ offset(log_py)")), data = D, control = glm.control(maxit = 200))$theta
  for (nm in names(specs)) {
    m <- glm(as.formula(paste(y, "~", specs[[nm]], "+ offset(log_py)")), data = D, family = negative.binomial(theta))
    ct <- coeftest(m, vcov. = vcovCL(m, cluster = D$tract, type = "HC1"))   # statsmodels cluster default: G/(G-1) and (N-1)/(N-K)
    r <- list(outcome = y, model = nm, n = nrow(D), deaths = sum(D[[y]]), aic = round(AIC(m), 1), alpha = round(1 / theta, 4))
    for (v in c("z_hidden", "z_hidden_hiconf", "z_known_hist", "z_placebo", "z_tri", "z_cleanup", "z_prox_hazwaste", "z_prox_npl", "z_prox_rmp"))
      if (v %in% rownames(ct)) { b <- ct[v, 1]; se <- ct[v, 2]
        r[[paste0(v, "_rr")]] <- exp(b); r[[paste0(v, "_lo")]] <- exp(b - 1.96 * se); r[[paste0(v, "_hi")]] <- exp(b + 1.96 * se); r[[paste0(v, "_p")]] <- ct[v, 4] }
    rows[[length(rows) + 1]] <- r }
  message(y, " done")
}
T <- rbindlist(rows, fill = TRUE); fwrite(T, "data/results/mortality_bg_models_R.csv")
print(T[, .(outcome, model, z_hidden_rr, z_hidden_lo, z_hidden_hi, z_placebo_rr, aic)])
