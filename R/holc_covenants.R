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
hist <- fread("app/data/historical_sites.csv")[precision != "town" & !is.na(lat) & town == "DENVER" & first_year <= 1940 & last_year >= 1921]
hp <- st_transform(st_as_sf(hist, coords = c("lon", "lat"), crs = 4326), UTM); areas$firms_1921_1940 <- lengths(st_intersects(areas, hp))
cv <- st_read("data/covenants/denver_racial_covenants_1931_1935.geojson", quiet = TRUE); cv <- cv[!st_is_empty(cv), ]; cv <- st_transform(cv, UTM)
cv$text <- tolower(paste(cv$racial_tex, cv$abbrev_rac)); cv$excludes_industry <- grepl("manufactur|factory|business|commercial|trade|saloon|store", cv$text)
cv$excludes_black <- grepl("negro|colored|african", cv$text); cv$year <- as.integer(substr(cv$date_recor, 1, 4))
areas$covenants_1931_35 <- lengths(st_intersects(areas, cv))
# 1930 and 1940 ED composition, area-weighted onto the HOLC areas
ed_comp <- function(yr) { f <- sprintf("data/results/denver_eds/denver_eds_%d.geojson", yr); if (!file.exists(f)) return(NULL)
  E <- st_make_valid(st_transform(st_read(f, quiet = TRUE), UTM)); E <- E[!is.na(E$pop), ]; E$a <- as.numeric(st_area(E))
  ov <- suppressWarnings(st_intersection(E[, c("ED", "a", "pop", "black", "fb", "fb_mexico", "hisp", "laborers")], areas[, "area_id"])); ov$w <- as.numeric(st_area(ov)) / ov$a
  as.data.table(st_drop_geometry(ov))[, .(pop = sum(pop * w), black = sum(black * w), fb = sum(fb * w), fb_mexico = sum(fb_mexico * w), hisp = sum(hisp * w), laborers = sum(laborers * w)), by = area_id] }
for (yr in c(1930, 1940)) { e <- ed_comp(yr); if (is.null(e)) next
  e[, `:=`(pb = round(100 * black / pop, 2), pf = round(100 * fb / pop, 1), pm = round(100 * fb_mexico / pop, 2), ph = round(100 * hisp / pop, 2), pl = round(100 * laborers / pop, 1), pop = round(pop))]
  k <- match(areas$area_id, e$area_id); for (v in c("pop", "pb", "pf", "pm", "ph", "pl")) areas[[paste0(c(pop = "pop", pb = "pct_black", pf = "pct_fb", pm = "pct_fb_mexico", ph = "pct_hisp", pl = "pct_laborers")[v], "_", yr)]] <- e[[v]][k] }
st_write(st_transform(areas, 4326), file.path(A, "holc_denver.geojson"), delete_dsn = TRUE, quiet = TRUE)
fwrite(as.data.table(st_drop_geometry(areas)), file.path(O, "holc_areas.csv"))
cvl <- st_coordinates(st_transform(cv, 4326)); fwrite(data.table(lon = round(cvl[, 1], 5), lat = round(cvl[, 2], 5), year = cv$year, subdivision = cv$subdivisio, restriction = cv$abbrev_rac, excludes_black = cv$excludes_black, excludes_industry = cv$excludes_industry), file.path(A, "covenants_denver.csv"))
# ---------------------------------------------------------------- by grade
ar <- as.data.table(st_drop_geometry(areas))[grade %in% c("A", "B", "C", "D")]
G <- ar[, .(areas = .N, area_km2 = round(sum(area_km2), 1), firms_1921_1940 = sum(firms_1921_1940), areas_with_firm = sum(firms_1921_1940 > 0), mentions_industry = sum(mentions_industry), covenants_1931_35 = sum(covenants_1931_35),
            pop_1930 = round(sum(pop_1930, na.rm = TRUE)), pct_black_1930 = round(weighted.mean(pct_black_1930, pop_1930, na.rm = TRUE), 2), pct_fb_1930 = round(weighted.mean(pct_fb_1930, pop_1930, na.rm = TRUE), 1),
            pct_hisp_1930 = round(weighted.mean(pct_hisp_1930, pop_1930, na.rm = TRUE), 2), pct_laborers_1930 = round(weighted.mean(pct_laborers_1930, pop_1930, na.rm = TRUE), 1),
            pct_black_1940 = round(weighted.mean(pct_black_1940, pop_1940, na.rm = TRUE), 2), pct_hisp_1940 = round(weighted.mean(pct_hisp_1940, pop_1940, na.rm = TRUE), 2)), by = grade][order(grade)]
fwrite(G, file.path(O, "holc_by_grade.csv")); print(G)
# ---------------------------------------------------------------- 1940-2020 tract trajectories by dominant HOLC grade (2010 tracts)
xw <- as.data.table(st_drop_geometry(X))[grade %in% c("A", "B", "C", "D"), .(share = sum(pct_tract)), by = .(GEOID = GEOID10, grade)]
dom <- xw[, .(grade = grade[which.max(share)], covered = sum(share)), by = GEOID][covered >= 0.4]     # tracts at least 40% inside graded areas
pan <- fread("app/data/tract_panel.csv", colClasses = c(GEOID = "character")); pan <- merge(pan, dom, by = "GEOID")
TR <- pan[!is.na(pop) & pop > 0, .(tracts = .N, p_black = weighted.mean(p_black, pop, na.rm = TRUE), p_hisp = weighted.mean(p_hisp, pop, na.rm = TRUE), p_fb = weighted.mean(p_fb, pop, na.rm = TRUE), p_pov = weighted.mean(p_pov, pop, na.rm = TRUE),
                                   firms_haz = sum(firms_haz, na.rm = TRUE)), by = .(census, grade)][order(census, grade)]
fwrite(TR, file.path(O, "trajectories_by_grade.csv")); file.copy(file.path(O, c("holc_by_grade.csv", "trajectories_by_grade.csv")), A, overwrite = TRUE)
# Xu-style: change in each outcome over a period on grade dummies (A = reference), with the 1940 baseline of the outcome, 1940 % Black, and firms 1931-40 controlled
W <- dcast(pan, GEOID + grade ~ census, value.var = c("p_black", "p_hisp", "p_fb", "p_pov", "firms_haz"))
M <- list()
for (v in c("p_black", "p_hisp", "p_pov")) for (per in list(c(1940, 1980), c(1980, 2010), c(1940, 2010))) {
  y0 <- paste0(v, "_", per[1]); y1 <- paste0(v, "_", per[2]); if (!all(c(y0, y1) %in% names(W))) next
  if (v == "p_pov" && per[1] == 1940) { d <- W[!is.na(W[[y1]])]; d$base <- 0 } else { d <- W[!is.na(W[[y1]]) & !is.na(W[[y0]])]; d$base <- d[[y0]] }
  d$dy <- d[[y1]] - d$base; d$grade <- factor(d$grade, c("A", "B", "C", "D")); d$black40 <- d$p_black_1940; d$firms40 <- log1p(d$firms_haz_1940)
  if (nrow(d) < 30 || length(unique(d$grade)) < 3) next
  m <- lm(dy ~ grade + base + black40 + firms40, d); ct <- coeftest(m, vcov. = vcovHC(m, type = "HC1"))
  for (g in c("B", "C", "D")) if (paste0("grade", g) %in% rownames(ct)) M[[length(M) + 1]] <- data.table(outcome = v, period = paste(per, collapse = "-"), grade = g, b = ct[paste0("grade", g), 1], se = ct[paste0("grade", g), 2], p = ct[paste0("grade", g), 4], n = nrow(d)) }
M <- rbindlist(M); fwrite(M, file.path(O, "holc_tract_models.csv")); file.copy(file.path(O, "holc_tract_models.csv"), A, overwrite = TRUE)
md <- c("# Redlining (HOLC 1938) and racial covenants (1931-35) vs. the hazardous trades, Denver", "",
        "## HOLC areas by grade: industry, appraisers' remarks, covenants, and the 1930 full-count composition (reconstructed EDs, area-weighted)", "",
        "| grade | areas | km2 | firms 1921-40 | areas with a firm | remarks mention industry | covenants 1931-35 | pop 1930 | % Black 1930 | % foreign born 1930 | % Hispanic 1930 | % laborers 1930 | % Black 1940 | % Hispanic 1940 |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
        sprintf("| %s | %d | %s | %d | %d | %d | %d | %s | %.2f | %.1f | %.2f | %.1f | %.2f | %.2f |", G$grade, G$areas, G$area_km2, G$firms_1921_1940, G$areas_with_firm, G$mentions_industry, G$covenants_1931_35, format(G$pop_1930, big.mark = ","), G$pct_black_1930, G$pct_fb_1930, G$pct_hisp_1930, G$pct_laborers_1930, G$pct_black_1940, G$pct_hisp_1940), "",
        sprintf("Covenant deeds with a point: %d; %d exclude Black residents by name, %d also bar manufacturing/business use.", nrow(cv), sum(cv$excludes_black), sum(cv$excludes_industry)), "",
        "## 2010 tracts by dominant HOLC grade (tracts at least 40% inside graded areas): population-weighted means, 1940-2020", "",
        "| census | grade | tracts | % Black | % Hispanic | % foreign born | % poverty | hazardous firms in decade |", "|---|---|---|---|---|---|---|---|",
        sprintf("| %d | %s | %d | %.1f | %.1f | %.1f | %.1f | %d |", TR$census, TR$grade, TR$tracts, TR$p_black, TR$p_hisp, TR$p_fb, TR$p_pov, TR$firms_haz), "",
        "## Change in tract outcomes by HOLC grade (A = reference; 1940 baseline, 1940 % Black and 1931-40 firms controlled; HC1 SE)", "",
        "| outcome | period | grade | b | SE | p | tracts |", "|---|---|---|---|---|---|---|",
        if (nrow(M)) sprintf("| %s | %s | %s | %.2f | %.2f | %.3g | %d |", M$outcome, M$period, M$grade, M$b, M$se, M$p, M$n) else "| (not enough tracts) |")
writeLines(md, file.path(O, "holc_summary.md")); cat(md, sep = "\n")
