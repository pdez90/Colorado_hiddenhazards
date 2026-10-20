# Zoning today (2023): what became of the 1929 industrial districts, how the historical sites are zoned now, and who lives in the
# tracts zoned for industry.
#   Rscript R/zoning_2023.R        (after R/zoning_1925.R, R/site_fate.R and R/app_census_layers.R)
# Source: Denver-metro zoning layer of 3 October 2023 (51 jurisdictions), compiled by Carrie Makarewicz (University of Colorado Denver)
# for the National Zoning Atlas. Each polygon carries the local district code (Local_zon) and a harmonised category (GenZone2:
# Industrial, Commercial, mixed use with housing at four densities, residential at four densities, open space, civic, ...). The file is
# not redistributed: place ALL_DenverMSA_10.3.23.{shp,shx,dbf,prj,cpg} in work/zoning_2023/. Only area shares and counts are written.
# Categories used here:
#   Industrial (housing not allowed)        GenZone2 == "Industrial" (Denver I-A, I-B; suburban industrial districts)
#   Industrial mixed use (housing allowed)  Denver's I-MX districts, which the harmonised file classes as mixed use with housing
#   Mixed use with housing                  the other MixedUse* categories
#   Residential                             Residential_* and MobileHome
#   Commercial; Open space, civic, other
# Study area as everywhere: the City and County of Denver plus the 147 2010 tracts whose centroid lies within 10 km of downtown.
#   1. the study area's land by category;
#   2. the 1929 Commercial, Industrial A and Industrial B districts (R/zoning_1925.R) by 2023 category;
#   3. hazardous-sector sites (1965-1992 complete editions, street-located) and street-level pre-1960 hazardous trades by 2023 category,
#      for Denver County and for the suburban study tracts, and by the decade the site was last listed;
#   4. the 147 tracts: 2023 share of land in each category, and 2020 composition (population-weighted) by industrial share.
# Outputs: data/results/zoning_2023/*.csv and zoning_2023_summary.md; copies of the summary tables in app/data.
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; O <- "data/results/zoning_2023"; A <- "app/data"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
SHP <- "work/zoning_2023/ALL_DenverMSA_10.3.23.shp"
if (!file.exists(SHP)) stop("Place the 2023 Denver-metro zoning shapefile in work/zoning_2023/ (see the header).")
ED_OK <- c(1965:1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992)
CATS <- c("Industrial (housing not allowed)", "Industrial mixed use (housing allowed)", "Mixed use with housing", "Residential", "Commercial", "Open space, civic, other")
cat_of <- function(g, code) factor(fcase(grepl("^I-MX", code), CATS[2], g == "Industrial", CATS[1], grepl("^MixedUse", g), CATS[3],
                                         grepl("^Residential|^MobileHome", g), CATS[4], g == "Commercial", CATS[5], default = CATS[6]), levels = CATS)
pct_tab <- function(d, by) { r <- d[, .N, by = c(by, "zone2023")]; r[, pct := round(100 * N / sum(N), 1), by = by]
  w <- dcast(r, as.formula(paste(paste(by, collapse = " + "), "~ zone2023")), value.var = "pct", fill = 0)
  merge(r[, .(n = sum(N)), by = by], w, by = by) }
# ---------------------------------------------------------------- study area and zoning
tr <- st_transform(st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE), UTM); tr$core <- as.logical(tr$core) %in% TRUE
AREA <- st_union(st_make_valid(tr[tr$core | substr(tr$GEOID, 1, 5) == "08031", ]))
Z <- st_make_valid(st_transform(st_read(SHP, quiet = TRUE), UTM))
Z$zone2023 <- cat_of(Z$GenZone2, Z$Local_zon)
Z <- suppressWarnings(st_intersection(Z[, c("zone2023", "GenZone2", "Local_zon", "jurisd")], AREA)); Z$km2 <- as.numeric(st_area(Z)) / 1e6
area_km2 <- as.numeric(st_area(AREA)) / 1e6
R1 <- as.data.table(st_drop_geometry(Z))[, .(km2 = round(sum(km2), 1)), by = zone2023][order(zone2023)][, pct := round(100 * km2 / sum(km2), 1)]
R1 <- rbind(R1, data.table(zone2023 = "study area covered by the 2023 file", km2 = round(sum(R1$km2), 1), pct = round(100 * sum(R1$km2) / area_km2, 1)))
fwrite(R1, file.path(O, "zoning_2023_study_area.csv"))
# ---------------------------------------------------------------- 1929 districts in 2023
z29 <- st_make_valid(st_transform(st_read(file.path(A, "zoning_1929.geojson"), quiet = TRUE), UTM))
x <- suppressWarnings(st_intersection(z29[, "zone"], Z[, "zone2023"])); x$km2 <- as.numeric(st_area(x)) / 1e6
R2 <- as.data.table(st_drop_geometry(x))[, .(km2 = sum(km2)), by = .(zone1929 = zone, zone2023)]
R2 <- dcast(R2[, pct := round(100 * km2 / sum(km2), 1), by = zone1929], zone1929 ~ zone2023, value.var = "pct", fill = 0)
R2 <- merge(as.data.table(st_drop_geometry(x))[, .(km2_1929 = round(sum(km2), 2)), by = .(zone1929 = zone)], R2, by = "zone1929")
for (k in CATS) if (!k %in% names(R2)) R2[, (k) := 0]
setcolorder(R2, c("zone1929", "km2_1929", CATS)); fwrite(R2, file.path(O, "zoning_1929_to_2023.csv"))
# ---------------------------------------------------------------- sites and pre-1960 trades
S <- fread(file.path(A, "sites.csv"), colClasses = c(GEOID = "character"))[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx") & !is.na(lat)]
SY <- fread(file.path(A, "site_years.csv"))[year %in% ED_OK][, .(last_listed = max(year)), by = site_id]
S <- merge(S, SY, by = "site_id")
H <- fread(file.path(A, "historical_sites.csv"), colClasses = c(GEOID = "character"))[fe_hazard %in% c(TRUE, "True") & precision != "town" & !is.na(lat)]
locate <- function(d, id) { p <- st_transform(st_as_sf(d, coords = c("lon", "lat"), crs = 4326, remove = FALSE), UTM)
  j <- st_join(p, Z[, c("zone2023", "GenZone2", "Local_zon", "jurisd")], left = FALSE); j <- j[!duplicated(j[[id]]), ]
  r <- as.data.table(st_drop_geometry(j)); r[, where := fifelse(substr(GEOID, 1, 5) == "08031", "Denver County", "Suburban study tracts")]; r }
SS <- locate(S, "site_id"); HH <- locate(H, "hfirm")
fwrite(SS[, .(site_id, address, city, first_year, last_listed, fe_sectors, radar, where, jurisd, Local_zon, GenZone2, zone2023)], file.path(O, "sites_zoning_2023.csv"))
SS[, series := "Hazardous-sector manufacturers 1965-1992"]; HH[, series := "Hazardous trades before 1960 (street level)"]
B <- rbind(SS[, .(series, where, zone2023)], HH[, .(series, where, zone2023)])
R3 <- rbind(pct_tab(B, c("series", "where")), pct_tab(B[, where := "Study area"], c("series", "where")))[n >= 20][order(series, where)]
fwrite(R3, file.path(O, "sites_by_zoning_2023.csv"))
SS[, last_decade := fcase(last_listed <= 1970, "1965-1970", last_listed <= 1980, "1971-1980", default = "1981-1992")]
R3b <- pct_tab(SS, "last_decade")[order(last_decade)]; fwrite(R3b, file.path(O, "sites_by_zoning_2023_last_listed.csv"))
# ---------------------------------------------------------------- tracts
core <- tr[tr$core, "GEOID"]
xt <- suppressWarnings(st_intersection(core, Z[, "zone2023"])); xt$km2 <- as.numeric(st_area(xt)) / 1e6
TZ <- dcast(as.data.table(st_drop_geometry(xt))[, .(km2 = sum(km2)), by = .(GEOID, zone2023)][, pct := round(100 * km2 / sum(km2), 1), by = GEOID],
            GEOID ~ zone2023, value.var = "pct", fill = 0)
for (k in CATS) if (!k %in% names(TZ)) TZ[, (k) := 0]
fwrite(TZ, file.path(O, "tract_zoning_2023.csv"))
P <- fread(file.path(A, "tract_panel.csv"), colClasses = c(GEOID = "character"))[census == 2020 & !is.na(pop) & pop >= 200]
M <- merge(TZ, P, by = "GEOID"); M[, ind := get(CATS[1])]
M[, group := factor(fcase(ind == 0, "No industrial zoning", ind < 5, "Under 5% industrial", ind < 20, "5-20% industrial", default = "20% or more industrial"),
                    levels = c("No industrial zoning", "Under 5% industrial", "5-20% industrial", "20% or more industrial"))]
wm <- function(v, w) round(weighted.mean(v, w, na.rm = TRUE), 1)
R4 <- M[, .(tracts = .N, residents = sum(pop), pct_hispanic = wm(p_hisp, pop), pct_black = wm(p_black, pop), pct_white = wm(p_white, pop),
            pct_foreign_born = wm(p_fb, pop), pct_poverty = wm(p_pov, pop), pct_owner_occupied = wm(p_owner, pop)), by = group][order(group)]
fwrite(R4, file.path(O, "tract_composition_by_zoning_2023.csv"))
file.copy(file.path(O, c("zoning_2023_study_area.csv", "zoning_1929_to_2023.csv", "sites_by_zoning_2023.csv", "sites_by_zoning_2023_last_listed.csv",
                         "tract_composition_by_zoning_2023.csv")), A, overwrite = TRUE)
# ---------------------------------------------------------------- summary
md <- function(d) { d <- as.data.frame(d); paste(c(paste("|", paste(names(d), collapse = " | "), "|"), paste(rep("|---", ncol(d)), collapse = ""), "|",
  apply(d, 1, function(r) paste("|", paste(r, collapse = " | "), "|"))), collapse = "\n") }
writeLines(c("# Zoning today (2023) in the Denver study area", "",
  "Source: Denver-metro zoning, 3 Oct 2023, compiled by C. Makarewicz (CU Denver) for the National Zoning Atlas.", "",
  "## Land by 2023 category", md(R1), "", "## The 1929 districts in 2023 (% of each 1929 district's area)", md(R2), "",
  "## Hazardous sites by 2023 zoning (% of sites)", md(R3), "", "## 1965-92 sites by the decade last listed", md(R3b), "",
  "## 2020 composition by the tract's 2023 industrial share (population-weighted means)", md(R4)), file.path(O, "zoning_2023_summary.md"))
print(R1); print(R2); print(R3); print(R3b); print(R4)
