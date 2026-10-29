# Industrial corridors in Colorado, 1961-2002 (with the pre-1960 Denver street-level firms where available):
# formation and persistence, clustering by sector, sector succession, and present-day legacy.
#   Rscript R/corridors.R            -> data/results/corridors/*.csv and corridors_summary.md
# Inputs (all in the repository): data/results/CO_directory_listings_1961-2002.csv, app/data/historical_sites.csv,
#   app/data/enviroscreen_tracts.geojson, app/data/sites.csv.
# Units: 500 m grid cells (UTM 13N) for persistence and succession; 1 km cells for the Ellison-Glaeser index.
suppressPackageStartupMessages({ library(sf); library(data.table); library(spatstat.geom); library(spdep); library(spatialreg) })
sf_use_s2(FALSE); UTM <- 26913
dir.create("data/results/corridors", showWarnings = FALSE)
SIC2 <- c("20"="Food","22"="Textiles","23"="Apparel","24"="Lumber & wood","25"="Furniture","26"="Paper","27"="Printing","28"="Chemicals",
          "29"="Petroleum","30"="Rubber & plastics","31"="Leather","32"="Stone, clay & glass","33"="Primary metals","34"="Fabricated metals",
          "35"="Machinery","36"="Electronics","37"="Transportation eq.","38"="Instruments","39"="Misc. manufacturing")

L <- fread("data/results/CO_directory_listings_1961-2002.csv", colClasses = c(sic = "character", zip = "character"))
L <- L[geo_level %in% c("address", "address_approx") & !is.na(lat)]
L[, sic2 := substr(sic, 1, 2)]; L[, sector := SIC2[sic2]]; L[is.na(sector), sector := "Other / not coded"]
L[, hazardous := fe_hazard %in% c(TRUE, "True")]   # Frickel & Elliott hazardous sectors, the definition used everywhere (was SIC 28-30, 33-35, 37)
xy <- st_coordinates(st_transform(st_as_sf(L, coords = c("lon", "lat"), crs = 4326), UTM)); L[, `:=`(x = xy[, 1], y = xy[, 2])]
DEN <- c(x = 500250, y = 4399500)                      # downtown Denver (approx. 17th & Larimer), UTM 13N
L[, metro := sqrt((x - DEN["x"])^2 + (y - DEN["y"])^2) <= 25000]
EDS <- sort(unique(L$year))

# ---------------------------------------------------------------- 1. clustering: Ellison-Glaeser index per sector per edition
# gamma = (G - (1 - sum x_i^2) H) / ((1 - sum x_i^2)(1 - H)); G = sum (s_i - x_i)^2 over 1 km cells; H = 1/N (equal plant sizes).
# x_i = share of ALL located manufacturers in cell i, so gamma asks whether a sector is more concentrated than manufacturing in general.
# p-value: 499 random re-labellings of the same N establishments among that edition's manufacturers.
eg <- function(cell_all, cell_sec, nperm = 499) {
  x <- table(cell_all) / length(cell_all); N <- length(cell_sec); H <- 1 / N
  g1 <- function(cs) { s <- table(factor(cs, levels = names(x))) / N; G <- sum((s - x)^2); (G - (1 - sum(x^2)) * H) / ((1 - sum(x^2)) * (1 - H)) }
  set.seed(20261021)                                                  # the permutation p-values are then the same on every run
  obs <- g1(cell_sec); perm <- replicate(nperm, g1(sample(cell_all, N)))
  c(gamma = obs, p = (1 + sum(perm >= obs)) / (nperm + 1))
}
rows <- list()
for (scope in c("statewide", "Denver metro")) for (yr in EDS) {
  d <- L[year == yr & (scope == "statewide" | metro)]; d <- unique(d, by = "estab_id")
  d[, cell := paste(floor(x / 1000), floor(y / 1000))]
  for (sec in c(names(SIC2)[names(SIC2) %in% d$sic2])) { ds <- d[sic2 == sec]; if (nrow(ds) < 10) next
    r <- eg(d$cell, ds$cell); rows[[length(rows) + 1]] <- data.table(scope, year = yr, sic2 = sec, sector = SIC2[sec], n = nrow(ds), n_all = nrow(d), gamma = r["gamma"], p = r["p"]) }
}
EG <- rbindlist(rows); fwrite(EG, "data/results/corridors/ellison_glaeser_by_sector_edition.csv")

# ---------------------------------------------------------------- 2. persistence in 500 m cells (metro and statewide)
L[, cell := paste(floor(x / 500), floor(y / 500))]
H <- fread("app/data/historical_sites.csv"); H <- H[precision != "town" & !is.na(lat)]
hxy <- st_coordinates(st_transform(st_as_sf(H, coords = c("lon", "lat"), crs = 4326), UTM)); H[, `:=`(x = hxy[, 1], y = hxy[, 2])]
H[, cell := paste(floor(x / 500), floor(y / 500))]; H[, metro := sqrt((x - DEN["x"])^2 + (y - DEN["y"])^2) <= 25000]
cy <- unique(L[, .(cell, year, estab_id, sic2, hazardous, metro)])
P <- cy[, .(n = uniqueN(estab_id), n_haz = uniqueN(estab_id[hazardous]), dominant = names(which.max(table(sic2)))), by = .(cell, year)]
cells <- P[, .(first = min(year), last = max(year), editions = uniqueN(year), max_n = max(n), ever_haz = any(n_haz > 0),
               first_sector = dominant[which.min(year)], last_sector = dominant[which.max(year)],
               n_sectors = uniqueN(dominant)), by = cell]
hp <- H[, .(pre1960_first = min(first_year), pre1960_firms = .N), by = cell]
cells <- merge(cells, hp, by = "cell", all.x = TRUE)
cells[, metro := cell %in% unique(c(L[metro == TRUE]$cell, H[metro == TRUE]$cell))]
nE <- length(EDS); span_ed <- function(f, l) sum(EDS >= f & EDS <= l)
cells[, coverage := editions / mapply(span_ed, first, last)]            # share of the editions between first and last that list a firm
cells[, class := fcase(
  first <= 1968 & last >= 1990 & coverage >= 0.6, "persistent",
  first >= 1980, "emerging",
  last <= 1980, "former (gone by 1980s)",
  default = "intermittent")]
cells[class == "persistent" & first_sector != last_sector & n_sectors >= 3, class := "persistent, sector turnover"]
fwrite(cells, "data/results/corridors/cells_500m.csv")

# ---------------------------------------------------------------- 3. succession: dominant sector in a cell, edition t -> next edition with a firm
P <- P[order(cell, year)]; P[, next_dom := data.table::shift(dominant, -1), by = cell]
T <- P[!is.na(next_dom), .N, by = .(from = SIC2[dominant], to = SIC2[next_dom])][order(-N)]
T[, share_of_from := N / sum(N), by = from]
fwrite(T, "data/results/corridors/sector_transitions.csv")
# and what a cell's first dominant sector became by its last edition
T2 <- cells[editions >= 3, .N, by = .(first = SIC2[first_sector], last = SIC2[last_sector])][order(-N)]
fwrite(T2, "data/results/corridors/sector_first_to_last.csv")

# ---------------------------------------------------------------- 4. do old industrial areas attract new industry?
# entries: establishments whose first listing is edition t+1, counted per 500 m cell; predictor: establishments in the cell at t and in
# the 8 neighbouring cells, distance to downtown Denver (metro only), with cell fixed effects (within-cell change over time).
first_yr <- L[, .(fy = min(year)), by = estab_id]; L2 <- merge(L, first_yr, by = "estab_id")
ent <- L2[year == fy & metro == TRUE, .(entries = uniqueN(estab_id)), by = .(cell, year)]
stock <- L2[metro == TRUE, .(stock = uniqueN(estab_id)), by = .(cell, year)]
grid <- CJ(cell = unique(L2[metro == TRUE]$cell), year = EDS)
grid <- merge(merge(grid, stock, by = c("cell", "year"), all.x = TRUE), ent, by = c("cell", "year"), all.x = TRUE)
grid[is.na(stock), stock := 0]; grid[is.na(entries), entries := 0]
grid[, c("cx", "cy") := lapply(tstrsplit(cell, " "), as.integer)]
nb_stock <- function(cx, cy, yr) { s <- grid[year == yr]; key <- paste(s$cell); st <- setNames(s$stock, key)
  sapply(seq_along(cx), function(k) { nn <- as.vector(outer(cx[k] + -1:1, cy[k] + -1:1, paste)); sum(st[nn], na.rm = TRUE) - st[paste(cx[k], cy[k])] }) }
grid[, nb := nb_stock(cx, cy, year[1]), by = year]
grid <- grid[order(cell, year)]; grid[, `:=`(stock_lag = data.table::shift(stock), nb_lag = data.table::shift(nb)), by = cell]
grid[, dist_km := sqrt((cx * 500 + 250 - DEN["x"])^2 + (cy * 500 + 250 - DEN["y"])^2) / 1000]
G4 <- grid[!is.na(stock_lag)]
m_pool <- glm(entries ~ log1p(stock_lag) + log1p(nb_lag) + dist_km + factor(year), family = poisson, data = G4)
G4[, `:=`(e_dm = entries - mean(entries), s_dm = log1p(stock_lag) - mean(log1p(stock_lag)), n_dm = log1p(nb_lag) - mean(log1p(nb_lag))), by = cell]
m_fe <- lm(e_dm ~ s_dm + n_dm + factor(year), data = G4)                 # within-cell: do more firms last edition predict more entries now?
ENT <- rbind(data.table(model = "Poisson, pooled (cell-years)", term = names(coef(m_pool))[2:4], estimate = coef(m_pool)[2:4], se = sqrt(diag(vcov(m_pool)))[2:4]),
             data.table(model = "within-cell (demeaned OLS)", term = names(coef(m_fe))[2:3], estimate = coef(m_fe)[2:3], se = sqrt(diag(vcov(m_fe)))[2:3]))
fwrite(ENT, "data/results/corridors/entry_models.csv")

# ---------------------------------------------------------------- 5. present-day legacy: cumulative industrial history of a tract vs. EnviroScreen today
tr <- st_make_valid(st_transform(st_read("app/data/enviroscreen_tracts.geojson", quiet = TRUE), UTM))
pts <- st_as_sf(unique(L[, .(estab_id, year, x, y, hazardous)]), coords = c("x", "y"), crs = UTM)
j <- st_join(pts, tr["GEOID"], join = st_within); jd <- as.data.table(st_drop_geometry(j))
hist_t <- jd[!is.na(GEOID), .(firm_years = .N, haz_firm_years = sum(hazardous), firms = uniqueN(estab_id), first = min(year)), by = GEOID]
S <- fread("app/data/sites.csv", colClasses = c(GEOID = "character"))
hid <- S[fe_hazard == TRUE & radar == "Not on any list", .(hidden_sites = .N), by = .(GEOID = substr(GEOID, 1, 11))]
TT <- as.data.table(st_drop_geometry(tr)); TT[, GEOID := as.character(GEOID)]
TT <- merge(merge(TT, hist_t, by = "GEOID", all.x = TRUE), hid, by = "GEOID", all.x = TRUE)
for (v in c("firm_years", "haz_firm_years", "firms", "hidden_sites")) TT[is.na(get(v)), (v) := 0]
TT[, area_km2 := as.numeric(st_area(tr)) / 1e6]; TT[, log_density := log1p(population / area_km2)]
TT <- TT[population >= 500]
queen_listw <- function(g, snap = 2) nb2listw(poly2nb(g, queen = TRUE, snap = snap), style = "W", zero.policy = TRUE)   # snap 2 m (UTM): simplified outlines
w <- queen_listw(tr[match(TT$GEOID, as.character(tr$GEOID)), ])
LEG <- list()
for (yv in c("people_of_color", "low_income", "enviroscreen_pctl", "pollution_climate_pctl")) for (xv in c("log1p(firm_years)", "log1p(haz_firm_years)", "log1p(hidden_sites)")) {
  fo <- as.formula(paste(yv, "~", xv, "+ log_density"))
  m <- errorsarlm(fo, data = TT, listw = w, zero.policy = TRUE)
  cf <- summary(m)$Coef; LEG[[length(LEG) + 1]] <- data.table(outcome = yv, predictor = xv, b = cf[2, 1], se = cf[2, 2], p = cf[2, 4], lambda = m$lambda, n = nrow(TT))
}
LEG <- rbindlist(LEG); fwrite(LEG, "data/results/corridors/legacy_tract_models.csv"); file.copy("data/results/corridors/legacy_tract_models.csv", "app/data", overwrite = TRUE)

# ---------------------------------------------------------------- summary
md <- c("# Industrial corridors: formation, clustering, succession, legacy", "",
        sprintf("Located establishments in the 13 complete editions 1965-1992: %s statewide, %s in the Denver metro (25 km of downtown); 500 m cells with any manufacturer: %s (%s metro).",
                format(uniqueN(L$estab_id), big.mark = ","), format(uniqueN(L[metro == TRUE]$estab_id), big.mark = ","), nrow(cells), sum(cells$metro)), "",
        "## Persistence classes of 500 m cells (metro)", "", "| class | cells | ever hazardous | with a pre-1960 street-level firm |", "|---|---|---|---|")
cc <- cells[metro == TRUE, .(cells = .N, haz = sum(ever_haz), pre = sum(!is.na(pre1960_first))), by = class][order(-cells)]
md <- c(md, sprintf("| %s | %d | %d | %d |", cc$class, cc$cells, cc$haz, cc$pre), "",
        "## Clustering (Ellison-Glaeser gamma vs. all manufacturing, 1 km cells; median over editions, share of editions with p < 0.05)", "",
        "| sector | statewide gamma | sig. share | metro gamma | sig. share |", "|---|---|---|---|---|")
ge <- dcast(EG[, .(g = round(median(gamma), 3), s = round(mean(p < .05), 2)), by = .(sector, scope)], sector ~ scope, value.var = c("g", "s"))
md <- c(md, sprintf("| %s | %s | %s | %s | %s |", ge$sector, ge$g_statewide, ge$s_statewide, ge[["g_Denver metro"]], ge[["s_Denver metro"]]), "",
        "## Most common sector successions (dominant sector of a cell, one edition to the next, excluding no change)", "")
Tn <- T[from != to][1:12]; md <- c(md, sprintf("* %s -> %s: %d cell-transitions (%.0f%% of transitions from %s)", Tn$from, Tn$to, Tn$N, 100 * Tn$share_of_from, Tn$from), "",
        "## Do old industrial areas attract new industry? (metro, 500 m cells)", "")
md <- c(md, sprintf("* %s: %s = %.3f (SE %.3f)", ENT$model, ENT$term, ENT$estimate, ENT$se), "",
        "## Present-day legacy (tracts, spatial error models, + log density)", "", "| outcome | predictor | b | SE | p |", "|---|---|---|---|---|",
        sprintf("| %s | %s | %.3f | %.3f | %.3g |", LEG$outcome, LEG$predictor, LEG$b, LEG$se, LEG$p))
writeLines(md, "data/results/corridors/corridors_summary.md"); cat(md, sep = "\n")
