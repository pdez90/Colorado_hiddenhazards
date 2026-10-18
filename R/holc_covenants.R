# Redlining and racial covenants in Denver vs. the hazardous trades.
#   Rscript R/holc_covenants.R      (after R/denver_eds_analysis.R and R/app_census_layers.R)
# Sources
#   HOLC 1938 Residential Security Map of Denver and its area descriptions: Mapping Inequality (Nelson, Winling et al., University of
#     Richmond DSL), via their GitHub repositories (CC-BY-NC): work/holc/mapping-inequality-census-crosswalk (areas crosswalked to
#     2010 tracts) and work/holc/HOLC_Area_Description_Data (form fields). Cloned by this script if git is available.
#   Racial covenants 1931-1935: Mapping Prejudice: Denver (Denver Public Library, pilot of 764 deeds; public domain) from
#     data.colorado.gov/Housing/Mapping-Prejudice-Denver-1931-1935-/3qth-7k3v, saved as data/covenants/denver_racial_covenants_1931_1935.geojson.
# Questions (after Xu 2022, Housing Policy Debate, who compared HOLC's post-hoc map with Chicago's implemented FHA map; no FHA map
#   survives for Denver, so here the HOLC grades are read against what came BEFORE them - the 1900-1940 districts - and after):
#   1. Were the D ("hazardous") areas the industrial districts? Firms 1921-1940 per area, the appraisers' own "detrimental influences"
#      text, and the 1930 ED composition (area-weighted) by grade.
#   2. Did the covenants exclude industry along with non-whites? Deeds mentioning manufacturing/business; covenants by HOLC grade.
#   3. Trajectories 1940-2020 of 2010 tracts by dominant HOLC grade (NHGIS panel), and a Xu-style regression of the change in each
#      outcome on grade with the 1940 baseline and 1931-40 firms controlled.
# Outputs: app/data/holc_denver.geojson, app/data/covenants_denver.csv, data/results/holc/{holc_by_grade.csv, holc_areas.csv,
#   trajectories_by_grade.csv, holc_tract_models.csv, holc_summary.md}
suppressPackageStartupMessages({ library(sf); library(data.table); library(sandwich); library(lmtest) })
sf_use_s2(FALSE); UTM <- 26913; H <- "work/holc"; O <- "data/results/holc"; A <- "app/data"; dir.create(O, showWarnings = FALSE, recursive = TRUE); dir.create(H, showWarnings = FALSE, recursive = TRUE)
for (r in c("mapping-inequality-census-crosswalk", "HOLC_Area_Description_Data")) if (!dir.exists(file.path(H, r))) system2("git", c("clone", "--depth", "1", paste0("https://github.com/americanpanorama/", r, ".git"), file.path(H, r)))
X <- st_read(file.path(H, "mapping-inequality-census-crosswalk/MIv3Areas_2010TractCrosswalk.geojson"), quiet = TRUE)
X <- X[grepl("Denver", X$city) & X$state == "CO", ]; X <- st_make_valid(st_transform(X, UTM))
areas <- aggregate(X[, c("area_id", "label", "grade", "cat", "res", "com", "ind")], by = list(id = X$area_id), FUN = function(z) z[1])[, -1]
areas <- st_sf(st_drop_geometry(areas), geometry = st_make_valid(st_geometry(areas))); areas$area_km2 <- as.numeric(st_area(areas)) / 1e6
message(nrow(areas), " HOLC areas in Denver: ", paste(names(table(areas$grade)), table(areas$grade), collapse = ", "))
# area descriptions (form 19371001): 1c detrimental influences, 2a occupation, 2b income, 2c foreign-born, 2d Negro, 2e infiltration, 2f relief, 2g population trend, 5 remarks
ad <- fread(file.path(H, "HOLC_Area_Description_Data/holc_ad_data.csv"))[area_id %in% areas$area_id]
fld <- function(cat, sub) ad[cat_id == cat & (is.na(sub) | sub_cat_id == sub)][order(area_id, `_order`)][!is.na(data) & data != "", .(txt = paste(data, collapse = " | ")), by = area_id]
get <- function(cat, sub = NA) { f <- fld(cat, sub); f$txt[match(areas$area_id, f$area_id)] }
areas$detrimental <- get(1, "c"); areas$favorable <- get(1, "b"); areas$occupation <- get(2, "a"); areas$income <- get(2, "b"); areas$holc_foreign_born <- get(2, "c")
areas$holc_negro <- get(2, "d"); areas$infiltration <- get(2, "e"); areas$relief <- get(2, "f"); areas$pop_trend <- get(2, "g"); areas$remarks <- get(5)
IND <- "industr|factor|smelter|railroad|railway|rail ?yard|smoke|odor|odour|refiner|packing|stock ?yard|warehouse|freight|foundry|gas plant|power plant|brick ?yard"
areas$mentions_industry <- grepl(IND, paste(areas$detrimental, areas$remarks), ignore.case = TRUE)
# firms 1921-1940 (street level) and racial covenants in each area
hist <- fread("app/data/historical_sites.csv")[precision != "town" & !is.na(lat) & town == "DENVER"]
hp <- st_transform(st_as_sf(hist, coords = c("lon", "lat"), crs = 4326), UTM)
fw <- function(a, b) lengths(st_intersects(areas, hp[hp$first_year <= b & hp$last_year >= a, ]))
areas$firms_pre1938 <- fw(1871, 1937); areas$firms_1921_1937 <- fw(1921, 1937); areas$firms_1938_1956 <- fw(1938, 1956); areas$firms_1921_1940 <- fw(1921, 1940)   # before the map (all street-level listings), the 17 years before it, after it
cv <- st_read("data/covenants/denver_racial_covenants_1931_1935.geojson", quiet = TRUE); cv <- cv[!st_is_empty(cv), ]; cv <- st_transform(cv, UTM)
cv$text <- tolower(paste(cv$racial_tex, cv$abbrev_rac)); cv$excludes_industry <- grepl("manufactur|factory|business|commercial|trade|saloon|store", cv$text)
cv$excludes_black <- grepl("negro|colored|african", cv$text); cv$year <- as.integer(substr(cv$date_recor, 1, 4))
areas$covenants_1931_35 <- lengths(st_intersects(areas, cv))
# 1930 and 1940 ED composition, area-weighted onto the HOLC areas
ed_comp <- function(yr) { f <- sprintf("data/results/denver_eds/denver_eds_%d.geojson", yr); if (!file.exists(f)) return(NULL)
  E <- st_make_valid(st_transform(st_read(f, quiet = TRUE), UTM)); E <- E[!is.na(E$pop), ]; E$a <- as.numeric(st_area(E))
  for (k in c("owner_hh", "tenure_hh")) if (!k %in% names(E)) E[[k]] <- NA_real_
  ov <- suppressWarnings(st_intersection(E[, c("ED", "a", "pop", "black", "fb", "fb_mexico", "hisp", "laborers", "owner_hh", "tenure_hh")], areas[, "area_id"])); ov$w <- as.numeric(st_area(ov)) / ov$a
  as.data.table(st_drop_geometry(ov))[, .(pop = sum(pop * w), black = sum(black * w), fb = sum(fb * w), fb_mexico = sum(fb_mexico * w), hisp = sum(hisp * w), laborers = sum(laborers * w),
                                         owner_hh = sum(owner_hh * w), tenure_hh = sum(tenure_hh * w)), by = area_id] }
# before the map: every reconstructed census 1900-1940 aggregated to the HOLC polygons (which are fixed, so no tract harmonisation is involved; the
# only approximation is area-weighting each census's districts into the polygons) and then population-weighted by grade -> trajectories_pre_by_grade.csv
PRE <- rbindlist(lapply(c(1900, 1910, 1920, 1930, 1940), function(yr) { e <- ed_comp(yr); if (is.null(e)) return(NULL)
  e <- merge(e, as.data.table(st_drop_geometry(areas))[, .(area_id, grade)], by = "area_id")[grade %in% c("A", "B", "C", "D")]
  e[, .(census = yr, areas = .N, pop = round(sum(pop)), p_black = round(100 * sum(black) / sum(pop), 2), p_hisp = round(100 * sum(hisp) / sum(pop), 2), p_fb = round(100 * sum(fb) / sum(pop), 2),
        p_laborers = round(100 * sum(laborers) / sum(pop), 2), p_owner = round(100 * sum(owner_hh) / sum(tenure_hh), 2)), by = grade] }))
if (nrow(PRE)) { setorder(PRE, census, grade); fwrite(PRE, file.path(O, "trajectories_pre_by_grade.csv")); file.copy(file.path(O, "trajectories_pre_by_grade.csv"), A, overwrite = TRUE) }
for (yr in c(1930, 1940)) { e <- ed_comp(yr); if (is.null(e)) next
  e[, `:=`(pb = round(100 * black / pop, 2), pf = round(100 * fb / pop, 1), pm = round(100 * fb_mexico / pop, 2), ph = round(100 * hisp / pop, 2), pl = round(100 * laborers / pop, 1), pop = round(pop))]
  k <- match(areas$area_id, e$area_id); for (v in c("pop", "pb", "pf", "pm", "ph", "pl")) areas[[paste0(c(pop = "pop", pb = "pct_black", pf = "pct_fb", pm = "pct_fb_mexico", ph = "pct_hisp", pl = "pct_laborers")[v], "_", yr)]] <- e[[v]][k] }
st_write(st_transform(areas, 4326), file.path(A, "holc_denver.geojson"), delete_dsn = TRUE, quiet = TRUE)
fwrite(as.data.table(st_drop_geometry(areas)), file.path(O, "holc_areas.csv"))
cvl <- st_coordinates(st_transform(cv, 4326)); fwrite(data.table(lon = round(cvl[, 1], 5), lat = round(cvl[, 2], 5), year = cv$year, subdivision = cv$subdivisio, restriction = cv$abbrev_rac, excludes_black = cv$excludes_black, excludes_industry = cv$excludes_industry), file.path(A, "covenants_denver.csv"))
# ---------------------------------------------------------------- by grade
ar <- as.data.table(st_drop_geometry(areas))[grade %in% c("A", "B", "C", "D")]
G <- ar[, .(areas = .N, area_km2 = round(sum(area_km2), 1), firms_pre1938 = sum(firms_pre1938), areas_with_firm_pre1938 = sum(firms_pre1938 > 0), firms_1921_1937 = sum(firms_1921_1937), firms_1938_1956 = sum(firms_1938_1956), mentions_industry = sum(mentions_industry), covenants_1931_35 = sum(covenants_1931_35),
            pop_1930 = round(sum(pop_1930, na.rm = TRUE)), pct_black_1930 = round(weighted.mean(pct_black_1930, pop_1930, na.rm = TRUE), 2), pct_fb_1930 = round(weighted.mean(pct_fb_1930, pop_1930, na.rm = TRUE), 1),
            pct_hisp_1930 = round(weighted.mean(pct_hisp_1930, pop_1930, na.rm = TRUE), 2), pct_laborers_1930 = round(weighted.mean(pct_laborers_1930, pop_1930, na.rm = TRUE), 1),
            pct_black_1940 = round(weighted.mean(pct_black_1940, pop_1940, na.rm = TRUE), 2), pct_hisp_1940 = round(weighted.mean(pct_hisp_1940, pop_1940, na.rm = TRUE), 2)), by = grade][order(grade)]
fwrite(G, file.path(O, "holc_by_grade.csv")); print(G)
# ---------------------------------------------------------------- share of facilities by grade, then and now (within the graded areas)
pt <- function(df) st_transform(st_as_sf(df[!is.na(df$lat), ], coords = c("lon", "lat"), crs = 4326), UTM)
sites <- fread("app/data/sites.csv"); tri <- fread("app/data/tri_facilities.csv"); cln <- fread("app/data/cleanup_sites.csv")
# HOLC also outlined "Industrial" and "Commercial" zones without a residential grade; they are kept as classes of their own
areas$class <- ifelse(areas$grade %in% c("A", "B", "C", "D"), areas$grade, ifelse(grepl("Industrial", areas$cat), "Industrial", ifelse(grepl("Commercial", areas$cat), "Commercial", "other")))
CLS <- c("A", "B", "C", "D", "Industrial", "Commercial"); gr <- areas[areas$class %in% CLS, ]
cnt <- function(p) { k <- st_intersects(p, gr); g <- gr$class[vapply(k, function(z) if (length(z)) z[1] else NA_integer_, 0L)]; table(factor(g, CLS)) }
SH <- rbind(data.table(layer = "Land area of HOLC areas", t(as.vector(tapply(gr$area_km2, factor(gr$class, CLS), sum)))),
            data.table(layer = "Population 1940", t(as.vector(tapply(gr$pop_1940, factor(gr$class, CLS), sum, na.rm = TRUE)))),
            data.table(layer = "Hazardous trades before the map (1871-1937)", t(as.vector(cnt(hp[hp$first_year <= 1937, ])))),
            data.table(layer = "Hazardous trades after the map (1938-1956)", t(as.vector(cnt(hp[hp$first_year <= 1956 & hp$last_year >= 1938, ])))),
            data.table(layer = "Hazardous-sector manufacturers 1961-2002", t(as.vector(cnt(pt(sites))))),
            data.table(layer = "Sites on no current inventory (1961-2002)", t(as.vector(cnt(pt(sites[radar == "Not on any list"]))))),
            data.table(layer = "EPA TRI facilities (today)", t(as.vector(cnt(pt(tri))))),
            data.table(layer = "Cleanup / contamination sites (today)", t(as.vector(cnt(pt(cln))))))
setnames(SH, c("layer", CLS)); SH[is.na(SH)] <- 0; SH[, total := A + B + C + D + Industrial + Commercial]
for (g in CLS) SH[[paste0("share_", g)]] <- round(100 * SH[[g]] / SH$total, 1)
fwrite(SH, file.path(O, "holc_facility_shares.csv")); file.copy(file.path(O, "holc_facility_shares.csv"), A, overwrite = TRUE); print(SH[, .(layer, total, share_A, share_B, share_C, share_D, share_Industrial, share_Commercial)])
# ---------------------------------------------------------------- 1930 and 1940 districts classified by HOLC grade and covenants
ED_cls <- list()
for (yr in c(1930, 1940)) { f <- sprintf("data/results/denver_eds/denver_eds_%d.geojson", yr); if (!file.exists(f)) next
  E <- st_make_valid(st_transform(st_read(f, quiet = TRUE), UTM)); E <- E[!is.na(E$pop) & E$pop > 0, ]; E$a <- as.numeric(st_area(E))
  ov <- suppressWarnings(st_intersection(E[, c("ED", "a")], gr[, c("class")])); ov$w <- as.numeric(st_area(ov)) / ov$a
  gs <- as.data.table(st_drop_geometry(ov))[, .(w = sum(w)), by = .(ED, grade = class)]; dom <- gs[, .(grade = grade[which.max(w)], graded_share = sum(w)), by = ED]
  E <- merge(E, dom, by = "ED", all.x = TRUE); E$grade[is.na(E$grade) | E$graded_share < 0.3] <- "ungraded"
  E$covenants <- lengths(st_intersects(E, cv)); E$firms_pre1938 <- lengths(st_intersects(E, hp[hp$first_year <= 1937, ])); E$firms_1938_1956 <- lengths(st_intersects(E, hp[hp$first_year <= 1956 & hp$last_year >= 1938, ]))
  E$firms_1961_2002 <- lengths(st_intersects(E, pt(sites)))
  d <- as.data.table(st_drop_geometry(E)); d[, `:=`(pct_black = 100 * black / pop, pct_fb = 100 * fb / pop, pct_hisp = 100 * hisp / pop, pct_laborers = 100 * laborers / pop, has_covenant = covenants > 0)]
  cls <- d[, .(EDs = .N, population = sum(pop), covenants = sum(covenants), pct_black = round(weighted.mean(pct_black, pop), 2), pct_fb = round(weighted.mean(pct_fb, pop), 1), pct_hisp = round(weighted.mean(pct_hisp, pop), 2), pct_laborers = round(weighted.mean(pct_laborers, pop), 1),
                firms_pre1938 = sum(firms_pre1938), firms_1938_1956 = sum(firms_1938_1956), firms_1961_2002 = sum(firms_1961_2002)), by = .(grade, has_covenant)][, census := yr][order(grade, has_covenant)]
  cls[, firms_per_10k_pre1938 := round(1e4 * firms_pre1938 / population, 2)]; cls[, firms_per_10k_1938_56 := round(1e4 * firms_1938_1956 / population, 2)]; cls[, firms_per_10k_1961_2002 := round(1e4 * firms_1961_2002 / population, 2)]
  ED_cls[[length(ED_cls) + 1]] <- cls
  G2 <- st_transform(st_simplify(E[, c("ED", "pop", "grade", "graded_share", "covenants", "firms_pre1938", "firms_1938_1956", "firms_1961_2002")], dTolerance = 8), 4326)
  G2$pct_black <- round(d$pct_black, 2); G2$pct_hisp <- round(d$pct_hisp, 2); G2$pct_fb <- round(d$pct_fb, 1); G2$pct_laborers <- round(d$pct_laborers, 1); G2$census <- yr
  f2 <- file.path(A, sprintf("eds_holc_%d.geojson", yr)); if (file.exists(f2)) file.remove(f2); st_write(G2, f2, quiet = TRUE)
}
if (length(ED_cls)) { EC <- rbindlist(ED_cls); fwrite(EC, file.path(O, "ed_holc_classes.csv")); file.copy(file.path(O, "ed_holc_classes.csv"), A, overwrite = TRUE); print(EC[census == 1930, .(grade, has_covenant, EDs, population, pct_black, pct_hisp, firms_pre1938, firms_1938_1956, firms_1961_2002)]) }

# ---------------------------------------------------------------- 1940-2020 tract trajectories by dominant HOLC grade (2010 tracts)
xw <- as.data.table(st_drop_geometry(X))[grade %in% c("A", "B", "C", "D"), .(share = sum(pct_tract)), by = .(GEOID = GEOID10, grade)]
dom <- xw[, .(grade = grade[which.max(share)], covered = sum(share)), by = GEOID][covered >= 0.4]     # tracts at least 40% inside graded areas
if (file.mtime("app/data/tract_panel.csv") < file.mtime("work/census/denver_tract_panel.csv")) stop("app/data/tract_panel.csv is older than the census panel: run Rscript R/app_census_layers.R first, then this script")
pan <- fread("app/data/tract_panel.csv", colClasses = c(GEOID = "character")); pan <- merge(pan, dom, by = "GEOID")
for (k in c("p_owner", "mval_2020", "mrent_2020")) if (!k %in% names(pan)) pan[[k]] <- NA_real_
TR <- pan[!is.na(pop) & pop > 0, .(tracts = .N, p_black = weighted.mean(p_black, pop, na.rm = TRUE), p_hisp = weighted.mean(p_hisp, pop, na.rm = TRUE), p_fb = weighted.mean(p_fb, pop, na.rm = TRUE), p_pov = weighted.mean(p_pov, pop, na.rm = TRUE),
                                   p_owner = weighted.mean(p_owner, pop, na.rm = TRUE), mval_2020 = weighted.mean(mval_2020, pop, na.rm = TRUE), mrent_2020 = weighted.mean(mrent_2020, pop, na.rm = TRUE),
                                   firms_haz = sum(firms_haz, na.rm = TRUE)), by = .(census, grade)][order(census, grade)]
fwrite(TR, file.path(O, "trajectories_by_grade.csv")); file.copy(file.path(O, c("holc_by_grade.csv", "trajectories_by_grade.csv")), A, overwrite = TRUE)
# mortgage lending today (HMDA 2018-21, R/fetch_hmda.R) by dominant HOLC grade: the implemented-policy counterpart
hm <- "data/results/hmda_tracts_2018_2021.csv"
if (file.exists(hm)) { Hm <- merge(fread(hm, colClasses = c(GEOID = "character")), dom, by = "GEOID")
  HG <- Hm[, .(tracts = .N, apps = sum(apps), denial_rate = round(100 * sum(denied) / sum(apps), 1), pct_apps_black = round(100 * sum(black_apps) / sum(apps), 1), pct_apps_hisp = round(100 * sum(hisp_apps) / sum(apps), 1),
               black_denial_rate = round(weighted.mean(black_denial_rate, black_apps, na.rm = TRUE), 1), hisp_denial_rate = round(weighted.mean(hisp_denial_rate, hisp_apps, na.rm = TRUE), 1),
               median_loan_k = round(weighted.mean(median_loan_k, apps)), median_income_k = round(weighted.mean(median_income_k, apps))), by = grade][order(grade)]
  fwrite(HG, file.path(O, "hmda_by_grade.csv")); file.copy(file.path(O, "hmda_by_grade.csv"), A, overwrite = TRUE); print(HG)
  m <- lm(denial_rate ~ factor(grade, c("A", "B", "C", "D")) + log(median_income_k), Hm[apps >= 30], weights = apps); ct <- coeftest(m, vcov. = vcovHC(m, type = "HC1"))
  HM <- data.table(term = rownames(ct), b = ct[, 1], se = ct[, 2], p = ct[, 4])[grepl("grade", term)][, term := sub(".*\\)", "grade ", term)]
  fwrite(HM, file.path(O, "hmda_grade_model.csv")); file.copy(file.path(O, "hmda_grade_model.csv"), A, overwrite = TRUE); print(HM) }
# Xu-style: change in each outcome over a period on grade dummies (A = reference), with the 1940 baseline of the outcome, 1940 % Black, and firms 1931-40 controlled
pan[, lmval := log(mval_2020)]
W <- dcast(pan, GEOID + grade ~ census, value.var = c("p_black", "p_hisp", "p_fb", "p_pov", "firms_haz", "p_owner", "lmval"))
M <- list()
for (v in c("p_black", "p_hisp", "p_pov", "p_owner", "lmval")) for (per in list(c(1940, 1980), c(1980, 2010), c(1940, 2010))) {
  y0 <- paste0(v, "_", per[1]); y1 <- paste0(v, "_", per[2]); if (!all(c(y0, y1) %in% names(W))) next
  if (v == "p_pov" && per[1] == 1940) { d <- W[!is.na(W[[y1]])]; d$base <- 0 } else { d <- W[!is.na(W[[y1]]) & !is.na(W[[y0]])]; d$base <- d[[y0]] }
  d$dy <- d[[y1]] - d$base; d$grade <- factor(d$grade, c("A", "B", "C", "D")); d$black40 <- d$p_black_1940; d$firms40 <- log1p(d$firms_haz_1940)
  if (nrow(d) < 30 || length(unique(d$grade)) < 3) next
  m <- lm(dy ~ grade + base + black40 + firms40, d); ct <- coeftest(m, vcov. = vcovHC(m, type = "HC1"))
  for (g in c("B", "C", "D")) if (paste0("grade", g) %in% rownames(ct)) M[[length(M) + 1]] <- data.table(outcome = v, period = paste(per, collapse = "-"), grade = g, b = ct[paste0("grade", g), 1], se = ct[paste0("grade", g), 2], p = ct[paste0("grade", g), 4], n = nrow(d)) }
M <- rbindlist(M); fwrite(M, file.path(O, "holc_tract_models.csv")); file.copy(file.path(O, "holc_tract_models.csv"), A, overwrite = TRUE)
md <- c("# Redlining (HOLC 1938) and racial covenants (1931-35) vs. the hazardous trades, Denver", "",
        "## HOLC areas by grade: industry before and after the map, appraisers' remarks, covenants, and the 1930 full-count composition (reconstructed EDs, area-weighted)", "",
        "| grade | areas | km2 | firms before the map (1871-1937, street level) | areas with one | firms 1921-37 | firms 1938-56 | remarks mention industry | covenants 1931-35 | pop 1930 | % Black 1930 | % foreign born 1930 | % Hispanic 1930 | % laborers 1930 | % Black 1940 | % Hispanic 1940 |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
        sprintf("| %s | %d | %s | %d | %d | %d | %d | %d | %d | %s | %.2f | %.1f | %.2f | %.1f | %.2f | %.2f |", G$grade, G$areas, G$area_km2, G$firms_pre1938, G$areas_with_firm_pre1938, G$firms_1921_1937, G$firms_1938_1956, G$mentions_industry, G$covenants_1931_35, format(G$pop_1930, big.mark = ","), G$pct_black_1930, G$pct_fb_1930, G$pct_hisp_1930, G$pct_laborers_1930, G$pct_black_1940, G$pct_hisp_1940), "",
        sprintf("Covenant deeds with a point: %d; %d exclude Black residents by name, %d also bar manufacturing/business use.", nrow(cv), sum(cv$excludes_black), sum(cv$excludes_industry)), "",
        "## 2010 tracts by dominant HOLC grade (tracts at least 40% inside graded areas): population-weighted means, 1940-2020", "",
        "| census | grade | tracts | % Black | % Hispanic | % foreign born | % poverty | hazardous firms in decade |", "|---|---|---|---|---|---|---|---|",
        sprintf("| %d | %s | %d | %.1f | %.1f | %.1f | %.1f | %d |", TR$census, TR$grade, TR$tracts, TR$p_black, TR$p_hisp, TR$p_fb, TR$p_pov, TR$firms_haz), "",
        "## Change in tract outcomes by HOLC grade (A = reference; 1940 baseline, 1940 % Black and 1931-40 firms controlled; HC1 SE)", "",
        "| outcome | period | grade | b | SE | p | tracts |", "|---|---|---|---|---|---|---|",
        if (nrow(M)) sprintf("| %s | %s | %s | %.2f | %.2f | %.3g | %d |", M$outcome, M$period, M$grade, M$b, M$se, M$p, M$n) else "| (not enough tracts) |")
writeLines(md, file.path(O, "holc_summary.md")); cat(md, sep = "\n")
