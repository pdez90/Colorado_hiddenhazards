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
HAS_FIXEST <- requireNamespace("fixest", quietly = TRUE); if (!HAS_FIXEST) message("fixest not installed: spatially robust (Conley) standard errors will be skipped (install.packages('fixest'))")
conley_se <- function(fml, d, cutoff_km = 2) { if (!HAS_FIXEST || !all(c("lat", "lon") %in% names(d))) return(c(NA, NA, NA))   # coefficient on DTRUE with Conley HAC SE, `cutoff_km` radius
  ct <- tryCatch({ m <- fixest::feols(fml, data = d, weights = ~pop); fixest::coeftable(m, vcov = fixest::vcov_conley(m, lat = "lat", lon = "lon", cutoff = cutoff_km)) }, error = function(e) NULL)
  if (is.null(ct) || !"DTRUE" %in% rownames(ct)) return(c(NA, NA, NA)); c(ct["DTRUE", 1], ct["DTRUE", 2], ct["DTRUE", 4]) }
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
hist <- fread("app/data/historical_sites.csv")[precision != "town" & !is.na(lat) & town == "DENVER" & fe_hazard %in% c(TRUE, "True")]   # Frickel & Elliott hazardous trades, as everywhere
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
if (nrow(PRE)) { fd <- function(yr, g) sum(lengths(st_intersects(areas[areas$grade == g, ], hp[hp$first_year <= yr & hp$last_year >= yr - 9, ])))   # street-level hazardous trades active in the decade to the census
  PRE[, firms_haz := mapply(fd, census, grade)] }
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
            data.table(layer = "Hazardous-sector manufacturers 1965-1992 (complete editions)", t(as.vector(cnt(pt(sites[fe_hazard %in% c(TRUE, "True")]))))),
            data.table(layer = "Sites with no match in searched inventories (1965-1992)", t(as.vector(cnt(pt(sites[radar == "Not on any list"]))))),
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
  E$firms_1961_2002 <- lengths(st_intersects(E, pt(sites[fe_hazard %in% c(TRUE, "True")])))   # (column name kept for the app; holds the 1965-1992 complete-edition sites)
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
# the same with HOLC's ungraded Industrial and Commercial zones as classes of their own (for the change models only)
xw6 <- as.data.table(st_drop_geometry(X))[, cls := ifelse(grade %in% c("A", "B", "C", "D"), grade, cat)][cls %in% c("A", "B", "C", "D", "Industrial", "Commercial"), .(share = sum(pct_tract)), by = .(GEOID = GEOID10, cls)]
dom6 <- xw6[, .(cls = cls[which.max(share)], covered6 = sum(share)), by = GEOID][covered6 >= 0.4]
if (file.mtime("app/data/tract_panel.csv") < file.mtime("work/census/denver_tract_panel.csv")) stop("app/data/tract_panel.csv is older than the census panel: run Rscript R/app_census_layers.R first, then this script")
pan <- fread("app/data/tract_panel.csv", colClasses = c(GEOID = "character")); pan <- merge(pan, dom, by = "GEOID")
# 1940 tract Hispanic share from the districts: a tract gets a value only when at least MIN_POP40 residents lie behind it (the same
# 200-resident floor as every other tract measure), and only where the panel has none (no tract table carries Hispanic origin before 1960)
MIN_POP40 <- 200
fill_hisp_1940 <- function(pan, h40) { h40 <- h40[pop40 >= MIN_POP40]
  pan <- merge(pan, h40, by = "GEOID", all.x = TRUE); pan[census == 1940 & is.na(p_hisp) & !is.na(hisp40), p_hisp := 100 * hisp40 / pop40]; pan[, c("pop40", "hisp40") := NULL]; pan }
f40 <- "data/results/denver_eds/denver_eds_1940.geojson"
if (file.exists(f40) && "census" %in% names(pan)) {   # 1940 tract Hispanic share from the full count (no tract table has it before 1960): districts area-weighted into 2010 tracts
  E40 <- st_make_valid(st_transform(st_read(f40, quiet = TRUE), UTM)); E40 <- E40[!is.na(E40$pop), ]; E40$a <- as.numeric(st_area(E40))
  T40 <- st_make_valid(st_transform(st_read("app/data/co_tracts_2010.geojson", quiet = TRUE), UTM)); T40 <- T40[T40$GEOID %in% pan$GEOID, "GEOID"]
  ov <- suppressWarnings(st_intersection(E40[, c("a", "pop", "hisp", "black")], T40)); ov$w <- as.numeric(st_area(ov)) / ov$a
  h40 <- as.data.table(st_drop_geometry(ov))[, .(pop40 = sum(pop * w), hisp40 = sum(hisp * w)), by = GEOID]
  pan <- fill_hisp_1940(pan, h40)
  message("1940 tract Hispanic share filled from the 1940 districts (IPUMS HISPAN, a different definition from the 1960+ tract measures) for ", sum(pan$census == 1940 & !is.na(pan$p_hisp)), " tracts") }
for (k in c("p_owner", "mval_2020", "mrent_2020")) if (!k %in% names(pan)) pan[[k]] <- NA_real_
TR <- pan[!is.na(pop) & pop > 0, .(tracts = .N, p_black = weighted.mean(p_black, pop, na.rm = TRUE), p_hisp = weighted.mean(p_hisp, pop, na.rm = TRUE), p_fb = weighted.mean(p_fb, pop, na.rm = TRUE), p_pov = weighted.mean(p_pov, pop, na.rm = TRUE),
                                   p_owner = weighted.mean(p_owner, pop, na.rm = TRUE), mval_2020 = weighted.mean(mval_2020, pop, na.rm = TRUE), mrent_2020 = weighted.mean(mrent_2020, pop, na.rm = TRUE),
                                   firms_haz = sum(firms_haz, na.rm = TRUE)), by = .(census, grade)][order(census, grade)]
fwrite(TR, file.path(O, "trajectories_by_grade.csv")); file.copy(file.path(O, c("holc_by_grade.csv", "trajectories_by_grade.csv")), A, overwrite = TRUE)
# ---------------------------------------------------------------- did the map create or reinforce? pre-trends and a boundary comparison
# Following Aaronson, Hartley & Mazumder (2021): outcomes are tracked before and after 1938 by grade, and within a narrow band on either
# side of C-D boundaries, where neighbouring places share location advantages. Before 1940 the units are the reconstructed districts
# (HOLC polygons are fixed, so the 1900-1940 series needs no harmonisation); from 1940 they are 2010 tracts. A gap that was already
# widening before 1938 argues for "reinforced"; one that opens only afterwards for "created". Railways and zoning are not controlled.
GR <- areas[areas$grade %in% c("A", "B", "C", "D"), c("area_id", "grade")]
GU <- lapply(setNames(nm = c("A", "B", "C", "D")), function(g) st_union(GR[GR$grade == g, ]))
side_of <- function(g) { ins <- st_intersects(g, GR); vapply(ins, function(i) if (length(i)) GR$grade[i[1]] else NA_character_, "") }
near_g <- function(g, band) matrix(unlist(lapply(GU, function(u) as.logical(st_is_within_distance(g, u, band, sparse = FALSE)))), ncol = 4, dimnames = list(NULL, names(GU)))   # matrix: unit x grade, within `band` of that grade
in_band <- function(g, band) { m <- near_g(g, band); m[, "C"] & m[, "D"] }
PAIRS <- list(c("D", "C"), c("D", "B"), c("D", "A"), c("C", "B"), c("C", "A"), c("B", "A"))
# railways: TIGER/Line rail lines (today's network; in Denver essentially the pre-1900 trunk lines and yards minus abandoned spurs), as a
# control in the boundary regressions - a C-D boundary that follows a rail line can differ for reasons other than the grade
RAIL <- NULL; rz <- file.path(H, "tl_2023_us_rails.zip")
if (!file.exists(rz)) tryCatch(download.file("https://www2.census.gov/geo/tiger/TIGER2023/RAILS/tl_2023_us_rails.zip", rz, mode = "wb", quiet = TRUE), error = function(e) message("rail lines not downloaded (", conditionMessage(e), "); boundary gaps will not be rail-adjusted"))
if (file.exists(rz) && file.size(rz) > 1e6) { rd <- file.path(H, "rails"); if (!dir.exists(rd)) unzip(rz, exdir = rd)
  RAIL <- st_read(Sys.glob(file.path(rd, "*.shp"))[1], quiet = TRUE); bb <- st_as_sfc(st_bbox(st_transform(st_buffer(st_union(GR), 5000), 4326)))
  bb <- st_transform(bb, st_crs(RAIL)); RAIL <- st_transform(RAIL[lengths(st_intersects(RAIL, bb)) > 0, ], UTM); RAIL <- st_union(RAIL); message("rail lines: ", length(st_geometry(RAIL)), " geometries near the HOLC areas") }
rail_m <- function(g) if (is.null(RAIL)) rep(NA_real_, length(g)) else as.numeric(st_distance(g, RAIL))
# 1925 zoning (R/zoning_1925.R): share of each unit zoned industrial on the 1929 building-zone map, used as a control alongside rail
ZS_E <- if (file.exists("data/results/zoning_1929/zoning_shares_eds.csv")) fread("data/results/zoning_1929/zoning_shares_eds.csv", colClasses = c(ED = "character")) else NULL
ZS_T <- if (file.exists("data/results/zoning_1929/zoning_shares_tracts.csv")) fread("data/results/zoning_1929/zoning_shares_tracts.csv", colClasses = c(GEOID = "character")) else NULL
ZS_H <- if (file.exists("data/results/zoning_1929/zoning_shares_holc.csv")) fread("data/results/zoning_1929/zoning_shares_holc.csv") else NULL
if (!is.null(ZS_H)) { ZG <- ZS_H[grade %in% c("A", "B", "C", "D"), { on <- !is.na(share_industrial_1929); .(areas = .N, km2 = round(sum(area_km2), 1), areas_on_map = sum(on), km2_on_map = round(sum(area_km2[on]), 1), pct_industrial_1929 = round(100 * sum(share_industrial_1929[on] * area_km2[on]) / sum(area_km2[on]), 1), pct_commercial_1929 = round(100 * sum(share_commercial_1929[on] * area_km2[on]) / sum(area_km2[on]), 1)) }, by = grade][order(grade)]   # areas off the 1929 map sheet are excluded
  fwrite(ZG, file.path(O, "holc_zoning_by_grade.csv")); file.copy(file.path(O, "holc_zoning_by_grade.csv"), A, overwrite = TRUE); message("1929 zoning by HOLC grade:"); print(ZG) } else message("no 1929 zoning shares (run R/zoning_1925.R); boundary and change models will not be zoning-adjusted")
# A. industry by grade and period (street-level hazardous trades 1891-1956; hazardous-sector manufacturers, complete editions 1965-1992), per km2 of each grade
PER <- list(c(1891, 1905), c(1906, 1920), c(1921, 1937), c(1938, 1956), c(1965, 1980), c(1981, 1992))   # the manufacturers' directory enters through its complete editions 1965-1992
sp <- pt(sites[sites$fe_hazard %in% c(TRUE, "True"), ]); sp$site_id <- sites$site_id[!is.na(sites$lat) & sites$fe_hazard %in% c(TRUE, "True")]; sp$first_year <- sites$first_year[!is.na(sites$lat) & sites$fe_hazard %in% c(TRUE, "True")]; sp$last_year <- sites$last_year[!is.na(sites$lat) & sites$fe_hazard %in% c(TRUE, "True")]
firms_in <- function(a, b) { src <- if (a >= 1960) sp else hp; src[src$first_year <= b & src$last_year >= a, ] }
IND <- rbindlist(lapply(PER, function(pr) { f <- firms_in(pr[1], pr[2]); f$grade <- side_of(f); f$band <- in_band(f, 400)
  g <- as.data.table(st_drop_geometry(GR))[, .(km2 = as.numeric(sum(st_area(GR[GR$grade == .BY$grade, ]))) / 1e6), by = grade]
  d <- merge(g, as.data.table(st_drop_geometry(f))[!is.na(grade), .(firms = .N, firms_band = sum(band)), by = grade], by = "grade", all.x = TRUE)
  d[is.na(firms), `:=`(firms = 0L, firms_band = 0L)]; d[, `:=`(period = sprintf("%d-%d", pr[1], pr[2]), start = pr[1], per_km2 = round(firms / km2, 2), km2 = round(km2, 1))]; d }))
IND[, source := ifelse(start >= 1960, "Directory of Colorado Manufacturers (hazardous sectors)", "Colorado State Business Directory (hazardous trades, street level)")]
# periods differ in length and number of editions, and the two sources are not comparable: per EDITION (mean firms listed in each edition
# of the period, per km2) and the D/C ratio within each period are the comparable quantities; the change across the 1956/1965 source
# switch is not interpretable as a change in siting.
ed_years <- function(a, b) if (a >= 1960) intersect(c(1965:1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992), a:b) else sort(unique(as.integer(unlist(strsplit(as.character(hist$years), "[^0-9]+")))))[sort(unique(as.integer(unlist(strsplit(as.character(hist$years), "[^0-9]+"))))) %in% a:b]
SY <- fread("app/data/site_years.csv")
in_ed <- function(a, b) rbindlist(lapply(ed_years(a, b), function(y) { if (a >= 1960) { f <- sp[sp$site_id %in% SY[year == y]$site_id, ] } else { yy <- strsplit(as.character(hp$years), "[^0-9]+"); f <- hp[vapply(yy, function(z) as.character(y) %in% z, TRUE), ] }
  if (!nrow(f)) return(NULL); data.table(edition = y, grade = side_of(f)) }))
PE <- rbindlist(lapply(PER, function(pr) { x <- in_ed(pr[1], pr[2]); if (!nrow(x)) return(NULL); ne <- uniqueN(x$edition)
  x[!is.na(grade), .(firms_per_edition = .N / ne), by = grade][, `:=`(period = sprintf("%d-%d", pr[1], pr[2]), editions = ne)] }))
IND <- merge(IND, PE, by = c("period", "grade"), all.x = TRUE); IND[is.na(firms_per_edition), firms_per_edition := 0]; IND[, per_km2_per_edition := round(firms_per_edition / km2, 3)]
IND[, dc_ratio_within_period := { r <- per_km2_per_edition[grade == "D"] / per_km2_per_edition[grade == "C"]; if (length(r) && is.finite(r)) round(r, 1) else NA_real_ }, by = period]
setorder(IND, start, grade); fwrite(IND, file.path(O, "holc_industry_periods.csv")); file.copy(file.path(O, "holc_industry_periods.csv"), A, overwrite = TRUE)
print(dcast(IND, period ~ grade, value.var = "per_km2"))
# B. boundary comparison, census by census: units whose centroid lies within 400 m (districts) / 800 m (tracts) of both a C and a D area
bnd_ed <- rbindlist(lapply(c(1900, 1910, 1920, 1930, 1940), function(yr) { f <- sprintf("data/results/denver_eds/denver_eds_%d.geojson", yr); if (!file.exists(f)) return(NULL)
  E <- st_make_valid(st_transform(st_read(f, quiet = TRUE), UTM)); E <- E[!is.na(E$pop) & E$pop > 0, ]; ce <- st_centroid(st_geometry(E))
  for (k in c("owner_hh", "tenure_hh")) if (!k %in% names(E)) E[[k]] <- NA_real_
  data.table(census = yr, basis = "districts", unit = as.character(E$ED), pop = E$pop, p_black = 100 * E$black / E$pop, p_hisp = 100 * E$hisp / E$pop, p_fb = 100 * E$fb / E$pop, p_laborers = 100 * E$laborers / E$pop,
             p_owner = 100 * E$owner_hh / E$tenure_hh, side = side_of(ce), band = in_band(ce, 400), rail_m = rail_m(ce), lon = st_coordinates(st_transform(ce, 4326))[, 1], lat = st_coordinates(st_transform(ce, 4326))[, 2],
             ind29 = if (is.null(ZS_E)) NA_real_ else ZS_E[census == yr][match(as.character(E$ED), ED), share_industrial_1929],
             ind29s = if (is.null(ZS_E) || !"share_industrial_1929_strict" %in% names(ZS_E)) NA_real_ else ZS_E[census == yr][match(as.character(E$ED), ED), share_industrial_1929_strict])[, c("nA", "nB", "nC", "nD") := as.data.table(near_g(ce, 400))[]][, c("nC_narrow", "nD_narrow") := as.data.table(near_g(ce, 200))[, c("C", "D")]][, c("nC_wide", "nD_wide") := as.data.table(near_g(ce, 800))[, c("C", "D")]] }))
TRg <- st_make_valid(st_transform(st_read("app/data/co_tracts_2010.geojson", quiet = TRUE), UTM)); TRg <- TRg[TRg$GEOID %in% pan$GEOID, ]; ct <- st_centroid(st_geometry(TRg))
tb <- data.table(GEOID = TRg$GEOID, side = side_of(ct), band = in_band(ct, 800), rail_m = rail_m(ct), lon = st_coordinates(st_transform(ct, 4326))[, 1], lat = st_coordinates(st_transform(ct, 4326))[, 2],
                 ind29 = if (is.null(ZS_T)) NA_real_ else ZS_T$share_industrial_1929[match(TRg$GEOID, ZS_T$GEOID)],
                 ind29s = if (is.null(ZS_T) || !"share_industrial_1929_strict" %in% names(ZS_T)) NA_real_ else ZS_T$share_industrial_1929_strict[match(TRg$GEOID, ZS_T$GEOID)])[, c("nA", "nB", "nC", "nD") := as.data.table(near_g(ct, 800))[]][, c("nC_narrow", "nD_narrow") := as.data.table(near_g(ct, 400))[, c("C", "D")]][, c("nC_wide", "nD_wide") := as.data.table(near_g(ct, 1600))[, c("C", "D")]]
bnd_tr <- merge(pan[, .(census, unit = GEOID, pop, p_black, p_hisp, p_fb, p_pov, p_owner)], tb, by.x = "unit", by.y = "GEOID")[, basis := "2010 tracts"]
BD0 <- rbindlist(list(bnd_ed, bnd_tr), fill = TRUE)[!is.na(pop) & pop > 0 & !is.na(side)]
BR <- rbindlist(lapply(PAIRS, function(pr) { hi <- pr[1]; lo <- pr[2]                      # units within the band of both grades of the pair, lying in one of them
  keep <- BD0$side %in% pr & as.logical(BD0[[paste0("n", hi)]]) & as.logical(BD0[[paste0("n", lo)]]); keep[is.na(keep)] <- FALSE; BD <- BD0[keep]
  rbindlist(lapply(split(BD, by = c("census", "basis")), function(d) rbindlist(lapply(c("p_black", "p_hisp", "p_fb", "p_owner", "p_pov", "p_laborers"), function(v) {
    if (!v %in% names(d) || sum(!is.na(d[[v]])) < 10 || uniqueN(d$side[!is.na(d[[v]])]) < 2) return(NULL); dd <- d[!is.na(d[[v]]), ]; dd$y <- dd[[v]]; dd$D <- dd$side == hi
    if (sum(dd$D) < 3 || sum(!dd$D) < 3) return(NULL); m <- lm(y ~ D, dd, weights = pop); ct <- coeftest(m, vcov. = vcovHC(m, type = "HC1"))
    rr <- if (all(is.na(dd$rail_m)) || sum(!is.na(dd$rail_m)) < 8) c(NA, NA, NA) else { m2 <- lm(y ~ D + log1p(rail_m), dd, weights = pop); c2 <- coeftest(m2, vcov. = vcovHC(m2, type = "HC1")); c(c2["DTRUE", 1], c2["DTRUE", 2], c2["DTRUE", 4]) }
    zz <- if (all(is.na(dd$ind29)) || sum(!is.na(dd$ind29)) < 8 || sd(dd$ind29, na.rm = TRUE) == 0) c(NA, NA, NA) else { d3 <- dd[!is.na(ind29)]; m3 <- if (all(is.na(d3$rail_m))) lm(y ~ D + ind29, d3, weights = pop) else lm(y ~ D + log1p(rail_m) + ind29, d3, weights = pop); c3 <- coeftest(m3, vcov. = vcovHC(m3, type = "HC1")); c(c3["DTRUE", 1], c3["DTRUE", 2], c3["DTRUE", 4]) }
    zs <- if (!"ind29s" %in% names(dd) || all(is.na(dd$ind29s)) || sum(!is.na(dd$ind29s)) < 8 || sd(dd$ind29s, na.rm = TRUE) == 0) c(NA, NA, NA) else { d4 <- dd[!is.na(ind29s)]; m4 <- if (all(is.na(d4$rail_m))) lm(y ~ D + ind29s, d4, weights = pop) else lm(y ~ D + log1p(rail_m) + ind29s, d4, weights = pop); c4 <- coeftest(m4, vcov. = vcovHC(m4, type = "HC1")); c(c4["DTRUE", 1], c4["DTRUE", 2], c4["DTRUE", 4]) }
    cs <- conley_se(y ~ D, dd, 2)
    data.table(pair = paste0(hi, "-", lo), census = dd$census[1], basis = dd$basis[1], outcome = v, n_C = sum(!dd$D), n_D = sum(dd$D), mean_C = round(weighted.mean(dd$y[!dd$D], dd$pop[!dd$D]), 2), mean_D = round(weighted.mean(dd$y[dd$D], dd$pop[dd$D]), 2),
               gap = round(ct["DTRUE", 1], 2), se = round(ct["DTRUE", 2], 2), p = signif(ct["DTRUE", 4], 2), gap_rail = round(rr[1], 2), se_rail = round(rr[2], 2), p_rail = signif(rr[3], 2), gap_zone = round(zz[1], 2), se_zone = round(zz[2], 2), p_zone = signif(zz[3], 2), ind29_C = round(mean(dd$ind29[!dd$D], na.rm = TRUE), 3), ind29_D = round(mean(dd$ind29[dd$D], na.rm = TRUE), 3),
               gap_zone_strict = round(zs[1], 2), se_zone_strict = round(zs[2], 2), p_zone_strict = signif(zs[3], 2), se_conley2km = round(cs[2], 2), p_conley2km = signif(cs[3], 2),
               rail_m_C = round(median(dd$rail_m[!dd$D], na.rm = TRUE)), rail_m_D = round(median(dd$rail_m[dd$D], na.rm = TRUE))) })))) }))
setorder(BR, pair, outcome, census); fwrite(BR, file.path(O, "holc_boundary.csv")); file.copy(file.path(O, "holc_boundary.csv"), A, overwrite = TRUE)
# B2. bandwidth sensitivity for the D-C pair: narrow / standard / wide bands (districts 200/400/800 m; tracts 400/800/1600 m)
BW <- rbindlist(lapply(c("narrow", "standard", "wide"), function(bw) { nC <- if (bw == "standard") "nC" else paste0("nC_", bw); nD <- if (bw == "standard") "nD" else paste0("nD_", bw)
  if (!all(c(nC, nD) %in% names(BD0))) return(NULL); keep <- BD0$side %in% c("C", "D") & as.logical(BD0[[nC]]) & as.logical(BD0[[nD]]); keep[is.na(keep)] <- FALSE; BD <- BD0[keep]
  rbindlist(lapply(split(BD, by = c("census", "basis")), function(d) rbindlist(lapply(c("p_black", "p_hisp"), function(v) { dd <- d[!is.na(d[[v]]), ]; if (nrow(dd) < 10) return(NULL); dd$y <- dd[[v]]; dd$D <- dd$side == "D"
    if (sum(dd$D) < 3 || sum(!dd$D) < 3) return(NULL); m <- lm(y ~ D, dd, weights = pop); ct <- coeftest(m, vcov. = vcovHC(m, type = "HC1"))
    data.table(bandwidth = bw, metres = if (dd$basis[1] == "districts") c(narrow = 200, standard = 400, wide = 800)[[bw]] else c(narrow = 400, standard = 800, wide = 1600)[[bw]], census = dd$census[1], basis = dd$basis[1], outcome = v, n_C = sum(!dd$D), n_D = sum(dd$D), gap = round(ct["DTRUE", 1], 2), se = round(ct["DTRUE", 2], 2), p = signif(ct["DTRUE", 4], 2)) })))) }))
if (nrow(BW)) { setorder(BW, outcome, census, metres); fwrite(BW, file.path(O, "holc_boundary_bandwidth.csv")); file.copy(file.path(O, "holc_boundary_bandwidth.csv"), A, overwrite = TRUE); print(dcast(BW[outcome == "p_black"], census + basis ~ bandwidth, value.var = "gap")) }
# B3. trends of the D-C gap WITHIN one unit. Districts end in 1940 and tracts begin in 1940, so a single series cannot test a change of
# course at 1938 without confounding it with the change of unit, band width and population base: the district series (1900-1940)
# gives the pre-map trend and the tract series (1940-2020) the post-map path, each estimated separately (weighted by 1/SE^2).
TT <- rbindlist(lapply(c("p_black", "p_hisp"), function(v) rbindlist(lapply(list(c("districts", 1900, 1940), c("2010 tracts", 1940, 1970), c("2010 tracts", 1970, 2020)), function(u) {
  g <- BR[pair == "D-C" & outcome == v & basis == u[1] & census >= as.integer(u[2]) & census <= as.integer(u[3]) & !is.na(se) & se > 0]
  if (nrow(g) < 3) return(NULL); g[, `:=`(t = (census - 1938) / 10, w = 1 / se^2)]; m <- lm(gap ~ t, g, weights = w); ct <- coeftest(m)
  data.table(outcome = v, unit = u[1], years = sprintf("%s-%s", u[2], u[3]), points = nrow(g), slope_per_decade = round(coef(m)["t"], 2), se = round(ct["t", 2], 2), p = signif(ct["t", 4], 2)) }))))
if (nrow(TT)) { fwrite(TT, file.path(O, "holc_trend_test.csv")); file.copy(file.path(O, "holc_trend_test.csv"), A, overwrite = TRUE); message("trend of the D-C gap within each unit (few points; indicative):"); print(TT) }
print(BR[outcome %in% c("p_black", "p_hisp")])
# C. grade gaps by census from the full-grade series (D - C, C - B), before (HOLC polygons) and after (tracts)
GAP <- rbindlist(list(if (exists("PRE") && nrow(PRE)) melt(PRE, id.vars = c("grade", "census"), measure.vars = intersect(c("p_black", "p_hisp", "p_fb", "p_owner", "p_laborers"), names(PRE)))[, basis := "HOLC areas"],
                      melt(TR, id.vars = c("grade", "census"), measure.vars = intersect(c("p_black", "p_hisp", "p_fb", "p_owner", "p_pov"), names(TR)))[, basis := "2010 tracts"]), fill = TRUE)
GAP <- dcast(GAP[!is.na(value) & !is.nan(value)], census + basis + variable ~ grade, value.var = "value")
for (g in c("A", "B", "C", "D")) if (!g %in% names(GAP)) GAP[[g]] <- NA_real_
for (g in c("A", "B", "C", "D")) GAP[[g]] <- round(GAP[[g]], 2)
GAP[, `:=`(D_minus_C = round(D - C, 2), D_minus_B = round(D - B, 2), D_minus_A = round(D - A, 2), C_minus_B = round(C - B, 2), C_minus_A = round(C - A, 2), B_minus_A = round(B - A, 2))]; setorder(GAP, variable, census, basis)
fwrite(GAP, file.path(O, "holc_gaps.csv")); file.copy(file.path(O, "holc_gaps.csv"), A, overwrite = TRUE)
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
pan[, lmval := fifelse(is.finite(mval_2020) & mval_2020 > 0, log(mval_2020), NA_real_)]   # a few tracts have 0/NA value (grouped medians with < 10 units)
W <- dcast(pan, GEOID + grade ~ census, value.var = c("p_black", "p_hisp", "p_fb", "p_pov", "firms_haz", "p_owner", "lmval"))
W <- merge(W, dom6[, .(GEOID, cls)], by = "GEOID", all.x = TRUE); W[is.na(cls), cls := grade]
W <- merge(W, if (is.null(ZS_T)) data.table(GEOID = W$GEOID, ind29 = NA_real_) else ZS_T[, .(GEOID, ind29 = share_industrial_1929)], by = "GEOID", all.x = TRUE)
W <- merge(W, tb[, .(GEOID, lat, lon, ind29s)], by = "GEOID", all.x = TRUE)
M <- list()
# poverty is first measured in 1970, so its change is 1970-2010; the Hispanic share changes definition between 1940 (full-count HISPAN from the
# districts), 1960 (Spanish surname) and 1970 (Spanish language or surname), so its changes also start at 1970
change_periods <- function(v) if (v %in% c("p_pov", "p_hisp")) list(c(1970, 1980), c(1980, 2010), c(1970, 2010)) else list(c(1940, 1980), c(1980, 2010), c(1940, 2010))
# a class with fewer than MIN_CLS tracts is dropped: with one or two tracts its dummy fits them exactly and the HC1 error collapses to nothing.
# The reference class (A, four tracts in Denver) is never dropped: it carries no dummy of its own, and without it no model could run
MIN_CLS <- 5
drop_small_classes <- function(d, min_n = MIN_CLS, ref = "A") { keep_cls <- union(ref, names(which(table(d$grade) >= min_n))); d <- d[grade %in% keep_cls]; d$grade <- droplevels(d$grade); d }
# the change model: HC1 errors (ct) and, for comparison, classical errors (ct0)
change_model <- function(d) { m <- lm(dy ~ grade + base + black40 + firms40, d); list(m = m, ct = coeftest(m, vcov. = vcovHC(m, type = "HC1")), ct0 = coeftest(m)) }
for (v in c("p_black", "p_hisp", "p_pov", "p_owner", "lmval")) for (per in change_periods(v)) {
  y0 <- paste0(v, "_", per[1]); y1 <- paste0(v, "_", per[2]); if (!all(c(y0, y1) %in% names(W))) next
  d <- W[!is.na(W[[y1]]) & !is.na(W[[y0]])]; d$base <- d[[y0]]
  d$dy <- d[[y1]] - d$base; d$grade <- factor(d$cls, c("A", "B", "C", "D", "Industrial", "Commercial")); d$black40 <- d$p_black_1940; d$firms40 <- log1p(d$firms_haz_1940)
  d <- d[is.finite(dy) & is.finite(base) & !is.na(grade)]
  d <- drop_small_classes(d)
  if (nrow(d) < 30 || length(unique(d$grade)) < 3 || !"A" %in% levels(d$grade)) next
  cm <- change_model(d); m <- cm$m; ct <- cm$ct; ct0 <- cm$ct0
  cz <- if (sum(!is.na(d$ind29)) >= 30 && sd(d$ind29, na.rm = TRUE) > 0) { mz <- lm(dy ~ grade + base + black40 + firms40 + ind29, d[!is.na(ind29)]); coeftest(mz, vcov. = vcovHC(mz, type = "HC1")) } else NULL
  czs <- if ("ind29s" %in% names(d) && sum(!is.na(d$ind29s)) >= 30 && sd(d$ind29s, na.rm = TRUE) > 0) { mzs <- lm(dy ~ grade + base + black40 + firms40 + ind29s, d[!is.na(ind29s)]); coeftest(mzs, vcov. = vcovHC(mzs, type = "HC1")) } else NULL
  cc <- if (HAS_FIXEST && all(c("lat", "lon") %in% names(d))) tryCatch({ mf <- fixest::feols(dy ~ grade + base + black40 + firms40, data = d); fixest::coeftable(mf, vcov = fixest::vcov_conley(mf, lat = "lat", lon = "lon", cutoff = 2)) }, error = function(e) NULL) else NULL
  for (g in c("B", "C", "D", "Industrial", "Commercial")) if (paste0("grade", g) %in% rownames(ct)) M[[length(M) + 1]] <- data.table(outcome = v, period = paste(per, collapse = "-"), grade = g, b = ct[paste0("grade", g), 1], se = ct[paste0("grade", g), 2], p = ct[paste0("grade", g), 4], n = nrow(d), n_class = sum(d$grade == g), n_ref = sum(d$grade == "A"),
    se_classical = ct0[paste0("grade", g), 2], p_classical = ct0[paste0("grade", g), 4],
    b_zone = if (!is.null(cz) && paste0("grade", g) %in% rownames(cz)) cz[paste0("grade", g), 1] else NA_real_, se_zone = if (!is.null(cz) && paste0("grade", g) %in% rownames(cz)) cz[paste0("grade", g), 2] else NA_real_, p_zone = if (!is.null(cz) && paste0("grade", g) %in% rownames(cz)) cz[paste0("grade", g), 4] else NA_real_,
    b_ind29 = if (!is.null(cz)) cz["ind29", 1] else NA_real_, p_ind29 = if (!is.null(cz)) cz["ind29", 4] else NA_real_,
    b_zone_strict = if (!is.null(czs) && paste0("grade", g) %in% rownames(czs)) czs[paste0("grade", g), 1] else NA_real_, p_zone_strict = if (!is.null(czs) && paste0("grade", g) %in% rownames(czs)) czs[paste0("grade", g), 4] else NA_real_,
    se_conley2km = if (!is.null(cc) && paste0("grade", g) %in% rownames(cc)) cc[paste0("grade", g), 2] else NA_real_, p_conley2km = if (!is.null(cc) && paste0("grade", g) %in% rownames(cc)) cc[paste0("grade", g), 4] else NA_real_) }
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
