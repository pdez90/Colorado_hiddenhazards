# Sensitivity of the "known" vs "hidden" (on no inventory) classification to the inventory-matching rule.
#
# A site is "known" in the published classification when any inventory record is linked to it: the same firm by name or address,
# the site lies inside a mapped cleanup boundary, or any record of the tier lies within the tier's radius (75 m cleanup, 100 m TRI,
# 40 m RCRA handlers and other EPA permits, 75 m solid waste; grown by the site's spread, at most 250 m). The October 2026 review
# found that most known sites rest on the last of these alone: a differently named record nearby, often a small-quantity RCRA
# notifier (a pharmacy, a car dealer) that is another occupant of the block. This script re-classifies every site under a ladder of
# rules, from looser than published to strict (same entity or cleanup boundary only), and reports
#   1. how many sites are hidden under each rule (F&E sites, all hazardous sites, high confidence, Denver);
#   2. what the "nearby record only" matches are: the tier of the nearest such record and its distance;
#   3. whether the environmental-justice comparison of tracts changes: EnviroScreen 2.0 percentile, low income, less than high
#      school and people of color in 2020 tracts that hold a hidden site vs tracts with only known sites vs tracts with no site;
#   4. the HOLC grade of Denver's hidden and known sites under each rule.
#
# Inputs: app/data/sites.csv and data/results/known_hidden/site_match_evidence.csv (pipeline/app_inputs.py; per-tier evidence
# from pipeline/build_sites.py), work/reg/context_layers.json (EnviroScreen 2.0 tracts, pipeline/fetch_inputs.py context),
# app/data/holc_denver.geojson. Outputs: data/results/known_hidden/*.csv and summary.md.
#
#   Rscript R/known_hidden_sensitivity.R
suppressPackageStartupMessages({ library(data.table); library(sf); library(jsonlite) })
sf_use_s2(FALSE)

RULES <- c(cleanup = 75, tri = 100, rcra_handler = 40, solid_waste = 75, other_epa = 40)   # tier radii, as in pipeline/build_sites.py
STRONG <- c("same entity (name or address)", "inside a cleanup boundary")
HIDDEN_LABEL <- "Not on any list"
DEF_LABELS <- c(wider = "Looser: every radius doubled (at most 250 m)",
                published = "Published rule (name, address, boundary, or any record within the tier radius)",
                cleanup_tri_prox = "Proximity counts only for cleanup and TRI records",
                prox25 = "Proximity counts only within 25 m",
                prox10 = "Proximity counts only within 10 m",
                strict = "Strict: same firm (name or address) or inside a cleanup boundary")

# known (TRUE) / hidden (FALSE) for every site under rule `def`. E: one row per site with radar, match_basis, spread_m and, per
# tier t, t_basis ('entity', 'boundary', 'prox' or ''), t_prox_m (nearest differently named record inside the radius) and
# t_nearest_m (nearest record of the tier within 250 m).
known_under <- function(E, def) {
  strong <- E$match_basis %in% STRONG
  prox_within <- function(d) Reduce(`|`, lapply(names(RULES), function(t) { v <- E[[paste0(t, "_prox_m")]]; !is.na(v) & v <= d }))
  switch(def,
    published = E$radar != HIDDEN_LABEL,
    strict = strong,
    prox25 = strong | prox_within(25),
    prox10 = strong | prox_within(10),
    cleanup_tri_prox = strong | E$cleanup_basis %in% "prox" | E$tri_basis %in% "prox",
    wider = (E$radar != HIDDEN_LABEL) | Reduce(`|`, lapply(names(RULES), function(t) {
      v <- E[[paste0(t, "_nearest_m")]]; !is.na(v) & v <= pmin(250, 2 * RULES[[t]] + E$spread_m) })),
    stop("unknown rule: ", def))
}

# the published classification must be reproducible from the evidence columns: known = strong evidence or a proximity hit
check_evidence <- function(E) {
  rebuilt <- (E$match_basis %in% STRONG) | Reduce(`|`, lapply(names(RULES), function(t) E[[paste0(t, "_basis")]] %in% "prox"))
  sum(rebuilt != (E$radar != HIDDEN_LABEL))
}

# tier and distance of the nearest "nearby record only" match (sites whose basis is proximity alone)
nearest_prox <- function(E) {
  D <- as.matrix(E[, paste0(names(RULES), "_prox_m"), with = FALSE]); D[is.na(D)] <- Inf
  k <- max.col(-D, ties.method = "first"); d <- D[cbind(seq_len(nrow(D)), k)]
  data.table(tier = ifelse(is.finite(d), names(RULES)[k], NA_character_), dist_m = ifelse(is.finite(d), d, NA_real_))
}

dist_band <- function(d) cut(d, c(-Inf, 10, 25, 40, 75, Inf), labels = c("0-10 m", "10-25 m", "25-40 m", "40-75 m", "over 75 m"))

# tract classes under one rule: tracts holding at least one hidden site, tracts with sites that are all known, tracts with none
tract_classes <- function(site_tract, known, all_tracts) {
  d <- data.table(GEOID = site_tract, hidden = !known)[!is.na(GEOID), .(any_hidden = any(hidden)), by = GEOID]
  cls <- setNames(rep("No hazardous-sector site", length(all_tracts)), all_tracts)
  cls[d[any_hidden == FALSE, GEOID]] <- "Only known sites"
  cls[d[any_hidden == TRUE, GEOID]] <- "At least one hidden site"
  cls
}

# medians by class and Wilcoxon rank-sum p-values (hidden vs no site, hidden vs only known)
compare_classes <- function(T, cls, vars) {
  T <- copy(T)[, class := cls[GEOID]]
  rbindlist(lapply(names(vars), function(v) {
    x <- T[[v]]; g <- T$class; ok <- !is.na(x)
    med <- function(k) median(x[ok & g == k])
    pw <- function(a, b) { xa <- x[ok & g == a]; xb <- x[ok & g == b]
      if (length(xa) < 3 || length(xb) < 3) NA_real_ else suppressWarnings(wilcox.test(xa, xb)$p.value) }
    data.table(measure = vars[[v]],
               n_hidden_tracts = sum(ok & g == "At least one hidden site"), n_known_only_tracts = sum(ok & g == "Only known sites"),
               n_no_site_tracts = sum(ok & g == "No hazardous-sector site"),
               median_hidden = med("At least one hidden site"), median_known_only = med("Only known sites"),
               median_no_site = med("No hazardous-sector site"),
               p_hidden_vs_no_site = pw("At least one hidden site", "No hazardous-sector site"),
               p_hidden_vs_known_only = pw("At least one hidden site", "Only known sites")) }))
}

read_enviroscreen <- function(path) {
  J <- fromJSON(path, simplifyVector = FALSE)
  tmp <- tempfile(fileext = ".geojson")
  write_json(list(type = "FeatureCollection", features = J$enviroscreen_tract), tmp, auto_unbox = TRUE, digits = NA, null = "null")
  es <- st_read(tmp, quiet = TRUE); unlink(tmp)
  es <- st_make_valid(st_transform(es, 4326))
  es$GEOID <- as.character(es$GEOID)
  es
}

fmt <- function(x, d = 1) formatC(x, format = "f", digits = d, big.mark = ",")
md_table <- function(D) {
  D <- as.data.frame(D)
  c(paste0("| ", paste(names(D), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(D)), collapse = "|"), "|"),
    apply(D, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}

main <- function() {
  O <- "data/results/known_hidden"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
  S <- fread("app/data/sites.csv", colClasses = c(GEOID = "character", zip = "character", site_id = "character"))
  EV <- fread(file.path(O, "site_match_evidence.csv"), colClasses = c(site_id = "character"))
  for (t in names(RULES)) set(EV, j = paste0(t, "_basis"), value = fifelse(is.na(EV[[paste0(t, "_basis")]]), "", EV[[paste0(t, "_basis")]]))
  E <- merge(S, EV, by = "site_id", all.x = TRUE)
  stopifnot(nrow(E) == nrow(S), !anyNA(E$spread_m))
  bad <- check_evidence(E)
  cat(sprintf("published classification rebuilt from the evidence columns: %d of %d sites disagree\n", bad, nrow(E)))
  stopifnot(bad == 0)
  E[, fe_hazard := as.logical(fe_hazard)]
  for (d in names(DEF_LABELS)) set(E, j = paste0("known_", d), value = known_under(E, d))

  # 1. counts
  grp <- list(`F&E hazardous-sector sites (headline)` = E$fe_hazard, `All hazardous-sector sites (F&E + extended)` = rep(TRUE, nrow(E)),
              `F&E sites, high confidence` = E$fe_hazard & E$confidence == "high", `F&E sites in the City and County of Denver` = E$fe_hazard & E$county == "Denver")
  C <- rbindlist(lapply(names(DEF_LABELS), function(d) rbindlist(lapply(names(grp), function(g) {
    w <- grp[[g]]; h <- !E[[paste0("known_", d)]][w]
    data.table(rule = d, rule_label = DEF_LABELS[[d]], sites = g, n_sites = sum(w), n_hidden = sum(h), pct_hidden = round(100 * mean(h), 1)) }))))
  fwrite(C, file.path(O, "sensitivity_counts.csv"))

  # 2. what the proximity-only matches are
  P <- cbind(E[fe_hazard == TRUE & match_basis == "nearby record only", .(site_id)], nearest_prox(E[fe_hazard == TRUE & match_basis == "nearby record only"]))
  P[, band := dist_band(dist_m)]
  PT <- P[, .N, by = .(tier, band)][order(tier, band)]
  PT[, pct_of_proximity_only := round(100 * N / sum(N), 1)]
  fwrite(PT, file.path(O, "proximity_only_by_tier_distance.csv"))

  # 3. tract comparison, 2020 tracts with EnviroScreen 2.0
  # pipeline/fetch_inputs.py writes the layer to work/reg/; a copy kept with the other reference downloads is used when that is absent
  es_path <- Filter(file.exists, c("work/reg/context_layers.json", "work/hist/other/reference_data/context_layers.json"))[1]
  TC <- NULL
  if (!is.na(es_path)) {
    es <- read_enviroscreen(es_path)
    vars <- c(ES_S_ = "EnviroScreen percentile", Prcnt_lw_ = "Low income (%)", Pr_____ = "Less than high school (%)", Prc___ = "People of color (%)")
    T <- as.data.table(st_drop_geometry(es))[, c("GEOID", names(vars)), with = FALSE]
    for (v in c("Prcnt_lw_", "Pr_____", "Prc___")) set(T, j = v, value = 100 * T[[v]])      # decimal shares -> percent
    pts <- st_as_sf(E[fe_hazard == TRUE], coords = c("lon", "lat"), crs = 4326, remove = FALSE)
    w <- st_within(pts, es); tr <- es$GEOID[vapply(w, function(i) if (length(i)) i[1] else NA_integer_, 1L)]
    cat(sprintf("F&E sites outside every 2020 tract polygon: %d\n", sum(is.na(tr))))
    TC <- rbindlist(lapply(names(DEF_LABELS), function(d) {
      cls <- tract_classes(tr, pts[[paste0("known_", d)]], T$GEOID)
      cbind(data.table(rule = d, rule_label = DEF_LABELS[[d]]), compare_classes(T, cls, vars)) }))
    fwrite(TC, file.path(O, "tract_comparison_enviroscreen.csv"))
  } else stop("context_layers.json (EnviroScreen 2.0 tracts) not found in work/reg/ or work/hist/other/reference_data/: the tract comparison needs it")

  # 4. HOLC grades of Denver's sites
  HG <- NULL
  if (file.exists("app/data/holc_denver.geojson")) {
    holc <- st_make_valid(st_read("app/data/holc_denver.geojson", quiet = TRUE))
    dp <- st_as_sf(E[fe_hazard == TRUE & county == "Denver"], coords = c("lon", "lat"), crs = 4326, remove = FALSE)
    g <- holc$grade[vapply(st_within(dp, holc), function(i) if (length(i)) i[1] else NA_integer_, 1L)]
    g[is.na(g)] <- "Outside the 1938 map"
    HG <- rbindlist(lapply(names(DEF_LABELS), function(d) {
      k <- dp[[paste0("known_", d)]]
      x <- data.table(status = fifelse(k, "known", "hidden"), grade = g)[, .N, by = .(status, grade)]
      x[, pct := round(100 * N / sum(N), 1), by = status]
      cbind(data.table(rule = d), x[order(status, grade)]) }))
    fwrite(HG, file.path(O, "holc_grade_by_status.csv"))
  }

  # summary
  f <- C[sites == "F&E hazardous-sector sites (headline)"]; hc <- C[sites == "F&E sites, high confidence"]; dn <- C[sites == "F&E sites in the City and County of Denver"]
  T1 <- data.table(Rule = f$rule_label, `Hidden F&E sites` = paste0(fmt(f$n_hidden, 0), " (", fmt(f$pct_hidden), "%)"),
                   `High confidence` = paste0(fmt(hc$n_hidden, 0), " (", fmt(hc$pct_hidden), "%)"),
                   Denver = paste0(fmt(dn$n_hidden, 0), " (", fmt(dn$pct_hidden), "%)"))
  pt <- P[, .N, by = tier][, pct := round(100 * N / sum(N), 1)][order(-N)]
  pb <- P[, .N, by = band][, pct := round(100 * N / sum(N), 1)][order(band)]
  out <- c("# Known vs hidden: sensitivity to the inventory-matching rule", "",
           sprintf("%s F&E hazardous-sector sites (13 complete editions, 1965-1992). A site is hidden when no inventory record is linked to it under the rule.", fmt(f$n_sites[1], 0)), "",
           md_table(T1), "",
           sprintf("Under the published rule %s F&E sites are known through a nearby record only (%s%% of known F&E sites). The nearest such record is:",
                   fmt(nrow(P), 0), fmt(100 * nrow(P) / (f$n_sites[1] - f[rule == "published", n_hidden]))),
           "", md_table(data.table(Inventory = pt$tier, Sites = pt$N, `%` = pt$pct)), "",
           md_table(data.table(Distance = as.character(pb$band), Sites = pb$N, `%` = pb$pct)), "")
  if (!is.null(TC)) {
    out <- c(out, "## Tracts (2020, EnviroScreen 2.0): medians, tracts holding a hidden site vs only known sites vs no site", "")
    for (d in c("published", "cleanup_tri_prox", "prox25", "strict")) {
      x <- TC[rule == d]
      out <- c(out, paste0("**", DEF_LABELS[[d]], "**"), "",
               md_table(data.table(Measure = x$measure, `Hidden-site tracts` = paste0(fmt(x$median_hidden), " (n=", x$n_hidden_tracts, ")"),
                                   `Known-only tracts` = paste0(fmt(x$median_known_only), " (n=", x$n_known_only_tracts, ")"),
                                   `No-site tracts` = paste0(fmt(x$median_no_site), " (n=", x$n_no_site_tracts, ")"),
                                   `p vs no site` = signif(x$p_hidden_vs_no_site, 2), `p vs known only` = signif(x$p_hidden_vs_known_only, 2))), "")
    }
    out <- c(out, "p: Wilcoxon rank-sum test. Sites are placed in 2020 tracts by their coordinates.", "")
  }
  if (!is.null(HG)) {
    x <- HG[grade == "D"]
    out <- c(out, "## Denver: share of sites in HOLC D areas", "",
             md_table(dcast(x, rule ~ status, value.var = "pct")[match(names(DEF_LABELS), rule)][, rule := DEF_LABELS[rule]]), "")
  }
  writeLines(out, file.path(O, "summary.md"))
  cat(out, sep = "\n")
}

if (sys.nframe() == 0L && !nzchar(Sys.getenv("AUDIT_TESTING"))) main()
