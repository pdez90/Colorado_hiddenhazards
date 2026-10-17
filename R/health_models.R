# R port of pipeline/health/health_models.py: nested tract-level models, OLS (HC3) and spatial error models (ML, queen).
#   Rscript R/health_models.R     (after R/build_exposures.R)  -> data/results/health_models_R.csv
# M1 SES -> M2 +regulated hazards -> M3 +known historical sites -> M4 +hidden sites; placebo = non-hazardous manufacturers.
suppressPackageStartupMessages({ library(sf); library(data.table); library(spdep); library(spatialreg); library(sandwich); library(lmtest) })
sf_use_s2(FALSE)   # planar contiguity, as libpysal (some tract rings are invalid on the sphere)
f_in <- if (file.exists("work/health/tract_analysis_R.csv")) "work/health/tract_analysis_R.csv" else "work/health/tract_analysis.csv"
A <- fread(f_in, colClasses = c(tract = "character")); A[, tract := formatC(tract, width = 11, flag = "0")]
A <- A[population >= 500]
for (c in c("asthma_hosp", "low_birth_wt", "life_exp")) A[get(c) <= 0, (c) := NA]   # 0 = suppressed small numbers
A[, log_asthma := log(asthma_hosp)]; A[, log_density := log1p(pop_density)]
z <- function(x) { x <- log1p(x); (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE) }
for (e in c("hidden", "hidden_hiconf", "hidden_persist10", "known_hist", "hist_all", "tri", "cleanup", "placebo", "pre1960"))
  A[[paste0("z_", e)]] <- z(A[[paste0(e, "_kd")]])
for (c in c("prox_hazwaste", "prox_npl", "prox_rmp")) A[[paste0("z_", c)]] <- z(A[[c]])
SES <- c("low_income", "people_of_color", "less_than_hs", "ling_iso", "over64", "under5", "log_density")
REG <- c("z_prox_hazwaste", "z_prox_npl", "z_prox_rmp", "z_tri", "z_cleanup")
OUT <- c(log_asthma = "Asthma hospitalization rate (log)", low_birth_wt = "Low birth weight (%)", life_exp = "Life expectancy (years)",
         heart_dis = "Heart disease (index)", cancer = "Cancer (index)", diabetes = "Diabetes (index)", mental_health = "Poor mental health (%)")
tr <- st_read("app/data/enviroscreen_tracts.geojson", quiet = TRUE)[, "GEOID"]
tr$GEOID <- formatC(as.character(tr$GEOID), width = 11, flag = "0")

fit <- function(y, X) {
  d <- na.omit(A[, c(y, X, "tract"), with = FALSE]); fo <- reformulate(X, y)
  ols <- lm(fo, d); ct <- coeftest(ols, vcov. = vcovHC(ols, type = "HC3"))
  g <- tr[match(d$tract, tr$GEOID), ]
  w <- nb2listw(poly2nb(g, queen = TRUE), style = "W", zero.policy = TRUE)
  sem <- errorsarlm(fo, data = d, listw = w, zero.policy = TRUE, method = "eigen")
  list(n = nrow(d), ols = ols, ct = ct, sem = sem, ss = summary(sem)$Coef)
}
rows <- list()
specs <- list("M1 SES" = SES, "M2 +regulated" = c(SES, REG), "M3 +known historical" = c(SES, REG, "z_known_hist"),
              "M4 +hidden" = c(SES, REG, "z_known_hist", "z_hidden"), "Placebo: M2 +non-hazardous mfrs" = c(SES, REG, "z_placebo"),
              "M4 +placebo" = c(SES, REG, "z_known_hist", "z_hidden", "z_placebo"))
for (y in names(OUT)) {
  fits <- lapply(specs, function(X) fit(y, X)); ll <- sapply(fits, function(f) as.numeric(logLik(f$sem)))
  for (k in names(fits)) { f <- fits[[k]]
    r <- list(outcome = OUT[[y]], model = k, n = f$n, r2_ols = round(summary(f$ols)$r.squared, 4), aic_sem = round(AIC(f$sem), 1),
              logll_sem = round(ll[[k]], 2), lambda_sem = round(f$sem$lambda, 3))
    for (v in c("z_known_hist", "z_hidden", "z_placebo", "z_tri", "z_cleanup", "z_prox_hazwaste", "z_prox_npl")) if (v %in% rownames(f$ss)) {
      r[[paste0(v, "_b")]] <- f$ss[v, 1]; r[[paste0(v, "_se")]] <- f$ss[v, 2]; r[[paste0(v, "_p")]] <- f$ss[v, 4]
      r[[paste0(v, "_b_ols")]] <- f$ct[v, 1]; r[[paste0(v, "_p_ols")]] <- f$ct[v, 4] }
    rows[[length(rows) + 1]] <- r }
  for (pr in list(c("M2 +regulated", "M1 SES"), c("M3 +known historical", "M2 +regulated"), c("M4 +hidden", "M3 +known historical"),
                  c("Placebo: M2 +non-hazardous mfrs", "M2 +regulated"), c("M4 +placebo", "M4 +hidden"))) {
    lr <- 2 * (ll[[pr[1]]] - ll[[pr[2]]]); dfree <- if (grepl("regulated", pr[1])) length(REG) else 1
    rows[[length(rows) + 1]] <- list(outcome = OUT[[y]], model = paste("LR", pr[1], "vs", pr[2]), lr = round(lr, 2), lr_p = pchisq(lr, dfree, lower.tail = FALSE)) }
  message(OUT[[y]], " done")
}
R <- rbindlist(rows, fill = TRUE); fwrite(R, "data/results/health_models_R.csv")
print(R[model == "M4 +hidden", .(outcome, n, z_hidden_b, z_hidden_se, z_hidden_p, z_known_hist_b, aic_sem)])
