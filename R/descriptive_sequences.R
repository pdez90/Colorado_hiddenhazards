# Descriptive sequences: what came first, and did anything speed up?
#   Rscript R/descriptive_sequences.R      (after R/denver_eds_analysis.R, R/app_census_layers.R, R/zoning_1925.R, R/holc_covenants.R)
# No models with causal readings: tabulations on FIXED geographies so that a change over time is a change in the same place.
#   A. 500 m grid over the area mapped in every census 1900-1940 (the 1900 city): each census's enumeration-district counts
#      area-weighted onto the cells. Each cell carries its future 1938 HOLC class (largest share of the cell) and its 1929 zoning
#      (industrial share of the cell, NA off the map sheet), and the street-level hazardous trades (Frickel & Elliott sectors).
#        A1 location quotients by future class / 1929 zoning, 1900-1940 (share of a group living there / share of all people living there)
#        A2 first arrival of a hazardous trade: composition of cells BEFORE a first firm arrives vs cells that never had one
#           (does industry go to where disadvantaged people already live?), and the change in the decade after arrival
#        A3 the 1925 ordinance: change 1920 -> 1930 -> 1940 in cells zoned industrial vs not, within the same future HOLC class
#   B. 2010 tracts, 1940-2020, the fixed set of the 147 study tracts with data from 1960 (142):
#        B1 location quotients by dominant 1938 class (A, B, C, D, Industrial, Commercial)
#        B2 first arrival of a hazardous manufacturer WITHIN the manufacturers' directory (none in 1965-70, first listed 1973-80)
#           vs tracts with none through 1992: composition in 1970 and change 1970 -> 1990
#   C. timeline: for each future D area, the census at which its Black / Hispanic share first exceeded twice the city share,
#      and the year its first hazardous trade was listed.
# Outputs: data/results/descriptive/*.csv and descriptive_summary.md; copies in app/data.
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; O <- "data/results/descriptive"; A <- "app/data"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
YRS <- c(1900, 1910, 1920, 1930, 1940)
CNT <- c("pop", "black", "hisp", "fb", "laborers", "owner_hh", "tenure_hh")
# ---------------------------------------------------------------- inputs
E <- lapply(c(1880, YRS), function(y) { f <- sprintf("data/results/denver_eds/denver_eds_%d.geojson", y); if (!file.exists(f)) return(NULL)
  e <- st_make_valid(st_transform(st_read(f, quiet = TRUE), UTM)); e <- e[!is.na(e$pop) & e$pop > 0, ]
  for (k in CNT) e[[k]] <- if (k %in% names(e)) as.numeric(e[[k]]) else NA_real_; e$year <- y; e[, c("year", CNT)] })
names(E) <- c(1880, YRS); E <- E[!vapply(E, is.null, TRUE)]
hist <- fread("app/data/historical_sites.csv")[precision != "town" & !is.na(lat) & town == "DENVER" & fe_hazard %in% c(TRUE, "True")]
hp <- st_transform(st_as_sf(hist[, .(hfirm, first_year, last_year, lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)
H <- st_make_valid(st_transform(st_read("app/data/holc_denver.geojson", quiet = TRUE), UTM)); H$cls <- ifelse(is.na(H$grade), as.character(H$cat), H$grade)
Z <- st_make_valid(st_transform(st_read("app/data/zoning_1929.geojson", quiet = TRUE), UTM)); ZI <- st_union(Z[Z$class == "Industrial", ])
g <- fread("data/results/zoning_1929/gcp_fit.csv"); fx <- lm(X ~ px_x + px_y, g); fy <- lm(Y ~ px_x + px_y, g)
corner <- function(x, y) { d <- data.frame(px_x = x, px_y = y); c(predict(fx, d), predict(fy, d)) }
EXT <- st_sfc(st_polygon(list(rbind(corner(0, 0), corner(11849, 0), corner(11849, 12000), corner(0, 12000), corner(0, 0)))), crs = UTM)
CBD <- st_sfc(st_point(c(500250, 4399500)), crs = UTM)
share_in <- function(cells, layer) { a <- as.numeric(st_area(cells)); s <- numeric(nrow(cells)); x <- suppressWarnings(st_intersection(st_geometry(cells), layer))
  if (length(x)) { idx <- attr(x, "idx"); if (is.null(idx)) idx <- cbind(seq_along(x), 1); s0 <- tapply(as.numeric(st_area(x)), idx[, 1], sum); s[as.integer(names(s0))] <- s0 }; s / a }
# ---------------------------------------------------------------- A. fixed 500 m grid, 1900-1940
com <- Reduce(st_intersection, lapply(E[as.character(YRS)], function(e) st_union(st_geometry(e))))
gr <- st_make_grid(com, cellsize = 500); gr <- st_sf(cid = seq_along(gr), geometry = gr); gr <- suppressWarnings(st_intersection(gr, st_sf(geometry = com)))
gr <- gr[as.numeric(st_area(gr)) >= 0.5 * 500^2, ]; gr$cid <- seq_len(nrow(gr))
ov <- suppressWarnings(st_intersection(gr[, "cid"], H[, "cls"])); ov$a <- as.numeric(st_area(ov))
cl <- as.data.table(st_drop_geometry(ov))[, .(a = sum(a)), by = .(cid, cls)][order(-a)][, .SD[1], by = cid]
gr$cls <- cl$cls[match(gr$cid, cl$cid)]; gr$cls[is.na(gr$cls)] <- "not graded"
gr$on_sheet <- share_in(gr, EXT) >= 0.5; gr$ind29 <- ifelse(gr$on_sheet, share_in(gr, ZI), NA_real_)
gr$zoned_ind <- ifelse(is.na(gr$ind29), NA, gr$ind29 >= 0.25)
gr$dist_cbd_km <- as.numeric(st_distance(st_centroid(st_geometry(gr)), CBD)) / 1000
aw <- function(e) { e$src_a <- as.numeric(st_area(e)); x <- suppressWarnings(st_intersection(e, gr[, "cid"])); w <- as.numeric(st_area(x)) / x$src_a   # area weighting: even density inside a district
  d <- as.data.table(st_drop_geometry(x)); for (k in CNT) set(d, j = k, value = d[[k]] * w); d[, lapply(.SD, function(v) if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE)), by = cid, .SDcols = CNT] }
G <- rbindlist(lapply(names(E), function(y) aw(E[[y]])[, census := as.integer(y)]), fill = TRUE)
# hazardous trades by cell: listed in the ten years ending at the census (the rule used everywhere), and ever listed up to the census
wi <- st_within(hp, gr); hc <- data.table(hfirm = hp$hfirm, first_year = hp$first_year, last_year = hp$last_year, cid = vapply(wi, function(i) if (length(i)) gr$cid[i[1]] else NA_integer_, 0L))[!is.na(cid)]
fy <- function(y) hc[first_year <= y & last_year >= y - 9, .N, by = cid]; ev <- function(y) hc[first_year <= y, .N, by = cid]
G[, firms := 0L]; G[, firms_ever := 0L]
for (y in unique(G$census)) { a <- fy(y); b <- ev(y); G[census == y, firms := a$N[match(cid, a$cid)]]; G[census == y, firms_ever := b$N[match(cid, b$cid)]] }
G[is.na(firms), firms := 0L]; G[is.na(firms_ever), firms_ever := 0L]
G <- merge(G, data.table(cid = gr$cid, cls = gr$cls, ind29 = gr$ind29, zoned_ind = gr$zoned_ind, dist_cbd_km = gr$dist_cbd_km), by = "cid")
G <- G[!is.na(pop)]
first_firm <- hc[, .(first_listed = min(first_year)), by = cid]; G <- merge(G, first_firm, by = "cid", all.x = TRUE)
pct <- function(n, d) 100 * sum(n, na.rm = TRUE) / sum(d, na.rm = TRUE)
# A1 location quotients
lq <- function(D, by) { city <- D[, .(cB = sum(black, na.rm = TRUE) / sum(pop), cH = sum(hisp, na.rm = TRUE) / sum(pop), cF = sum(fb, na.rm = TRUE) / sum(pop), cL = sum(laborers, na.rm = TRUE) / sum(pop),
                                        cO = sum(owner_hh, na.rm = TRUE) / sum(tenure_hh, na.rm = TRUE)), by = census]
  x <- D[, .(cells = .N, pop = round(sum(pop)), pct_black = pct(black, pop), pct_hisp = pct(hisp, pop), pct_fb = pct(fb, pop), pct_laborers = pct(laborers, pop),
             pct_owner = if (all(is.na(owner_hh))) NA_real_ else pct(owner_hh, tenure_hh), cells_with_firm = sum(firms > 0), cells_ever_firm = sum(firms_ever > 0), firms = sum(firms)), by = c("census", by)]
  x <- merge(x, city, by = "census"); x[, `:=`(lq_black = round(pct_black / 100 / cB, 2), lq_hisp = round(pct_hisp / 100 / cH, 2), lq_fb = round(pct_fb / 100 / cF, 2), lq_laborers = round(pct_laborers / 100 / cL, 2),
                                          owner_ratio = round(pct_owner / 100 / cO, 2))][, c("cB", "cH", "cF", "cL", "cO") := NULL]
  for (v in c("pct_black", "pct_hisp", "pct_fb", "pct_laborers", "pct_owner")) set(x, j = v, value = round(x[[v]], 2)); x[] }
G[, cls4 := fifelse(cls %in% c("A", "B", "C", "D"), cls, fifelse(cls %in% c("Industrial", "Commercial"), paste("ungraded", tolower(cls)), "not graded"))]
A1 <- rbind(lq(G[census >= 1900], "cls4")[, group := paste("1938 class:", cls4)][, cls4 := NULL],
            lq(G[census >= 1900 & !is.na(zoned_ind)], "zoned_ind")[, group := fifelse(zoned_ind, "1929: zoned industrial (>=25% of cell)", "1929: not zoned industrial")][, zoned_ind := NULL])
setcolorder(A1, c("group", "census")); setorder(A1, group, census)
fwrite(A1, file.path(O, "grid_location_quotients_1900_1940.csv"))
# A2 first arrival: cells with no hazardous trade ever listed by census t; "arrival" = first listing in (t, t+10]
A2 <- rbindlist(lapply(c(1900, 1910, 1920, 1930), function(t) { a <- G[census == t & firms_ever == 0]; nx <- G[census == t + 10, .(cid, pop2 = pop, black2 = black, hisp2 = hisp, fb2 = fb, lab2 = laborers, own2 = owner_hh, ten2 = tenure_hh)]
  a <- merge(a, nx, by = "cid"); a[, arrival := !is.na(first_listed) & first_listed > t & first_listed <= t + 10]
  a[, .(cells = .N, pop = round(sum(pop)), pct_black_before = pct(black, pop), pct_hisp_before = pct(hisp, pop), pct_fb_before = pct(fb, pop), pct_laborers_before = pct(laborers, pop),
        pct_owner_before = if (t == 1880) NA_real_ else pct(owner_hh, tenure_hh), km_to_downtown = round(weighted.mean(dist_cbd_km, pop), 2),
        chg_black = pct(black2, pop2) - pct(black, pop), chg_hisp = pct(hisp2, pop2) - pct(hisp, pop), chg_fb = pct(fb2, pop2) - pct(fb, pop), chg_owner = pct(own2, ten2) - pct(owner_hh, tenure_hh)),
    by = .(group = fifelse(arrival, "first hazardous trade arrives in the next decade", "no hazardous trade by the next census"))][, `:=`(from = t, to = t + 10)] }))
for (v in grep("^pct_|^chg_", names(A2), value = TRUE)) set(A2, j = v, value = round(A2[[v]], 2)); setcolorder(A2, c("from", "to", "group"))
fwrite(A2, file.path(O, "grid_first_arrival_1900_1940.csv"))
# A3 the 1925 ordinance: change 1920 -> 1930 and 1930 -> 1940 by 1929 zoning, within future HOLC class (cells on the map sheet)
W <- dcast(G[census %in% c(1920, 1930, 1940) & !is.na(zoned_ind)], cid + cls4 + zoned_ind ~ census, value.var = c("pop", "black", "hisp", "fb", "laborers"))
A3 <- W[, .(cells = .N, pop_1920 = round(sum(pop_1920)), black_1920 = pct(black_1920, pop_1920), black_1930 = pct(black_1930, pop_1930), black_1940 = pct(black_1940, pop_1940),
            hisp_1920 = pct(hisp_1920, pop_1920), hisp_1930 = pct(hisp_1930, pop_1930), hisp_1940 = pct(hisp_1940, pop_1940),
            fb_1920 = pct(fb_1920, pop_1920), fb_1940 = pct(fb_1940, pop_1940), laborers_1920 = pct(laborers_1920, pop_1920), laborers_1940 = pct(laborers_1940, pop_1940),
            pop_change_1920_40_pct = round(100 * (sum(pop_1940) / sum(pop_1920) - 1), 1)), by = .(future_class = cls4, zoned_industrial_1929 = zoned_ind)][order(future_class, zoned_industrial_1929)]
for (v in grep("_19[234]0$", names(A3), value = TRUE)) if (!grepl("^pop", v)) set(A3, j = v, value = round(A3[[v]], 2))
fwrite(A3, file.path(O, "grid_zoning_1920_1940.csv"))
# ---------------------------------------------------------------- B. tracts 1940-2020 (fixed set: study tracts with data in every census from 1960)
pan <- fread("app/data/tract_panel.csv", colClasses = c(GEOID = "character"))[core == TRUE]
fix <- pan[census >= 1960 & !is.na(pop) & pop >= 200, .N, by = GEOID][N == uniqueN(pan[census >= 1960, census]), GEOID]
P <- pan[GEOID %in% fix]
TRg <- st_make_valid(st_transform(st_read("app/data/co_tracts_2010.geojson", quiet = TRUE), UTM)); TRg <- TRg[TRg$GEOID %in% fix, "GEOID"]
ovt <- suppressWarnings(st_intersection(TRg, H[, "cls"])); ovt$a <- as.numeric(st_area(ovt)); TRg$a <- as.numeric(st_area(TRg))
ct <- as.data.table(st_drop_geometry(ovt))[, .(a = sum(a)), by = .(GEOID, cls)]; ct <- merge(ct, data.table(GEOID = TRg$GEOID, at = TRg$a), by = "GEOID")
dom <- ct[, .(cls = cls[which.max(a)], covered = sum(a) / at[1]), by = GEOID][covered >= 0.4]
P <- merge(P, dom[, .(GEOID, cls)], by = "GEOID", all.x = TRUE); P[is.na(cls), cls := "not graded (<40% in HOLC areas)"]
P[cls %in% c("Industrial", "Commercial"), cls := paste("ungraded", tolower(cls))]
cnt <- P[!is.na(pop) & pop > 0, .(black = p_black * pop / 100, hisp = p_hisp * pop / 100, fb = p_fb * pop / 100, pov = p_pov * pop / 100, GEOID, census, cls, pop, firms_haz)]
cityT <- cnt[, .(cB = sum(black, na.rm = TRUE) / sum(pop[!is.na(black)]), cH = sum(hisp, na.rm = TRUE) / sum(pop[!is.na(hisp)]), cF = sum(fb, na.rm = TRUE) / sum(pop[!is.na(fb)]),
                 cP = sum(pov, na.rm = TRUE) / sum(pop[!is.na(pov)])), by = census]
B1 <- cnt[, .(tracts = .N, pop = round(sum(pop)), pct_black = 100 * sum(black, na.rm = TRUE) / sum(pop[!is.na(black)]), pct_hisp = 100 * sum(hisp, na.rm = TRUE) / sum(pop[!is.na(hisp)]),
              pct_fb = 100 * sum(fb, na.rm = TRUE) / sum(pop[!is.na(fb)]), pct_poverty = 100 * sum(pov, na.rm = TRUE) / sum(pop[!is.na(pov)]), firms = sum(firms_haz, na.rm = TRUE)), by = .(census, cls)]
B1 <- merge(B1, cityT, by = "census")[, `:=`(lq_black = round(pct_black / 100 / cB, 2), lq_hisp = round(pct_hisp / 100 / cH, 2), lq_fb = round(pct_fb / 100 / cF, 2), lq_poverty = round(pct_poverty / 100 / cP, 2))][, c("cB", "cH", "cF", "cP") := NULL]
for (v in grep("^pct_", names(B1), value = TRUE)) set(B1, j = v, value = round(B1[[v]], 2)); B1[is.nan(lq_hisp), lq_hisp := NA]
setorder(B1, cls, census); fwrite(B1, file.path(O, "tract_location_quotients_1940_2020.csv"))
# B2 first arrival within the manufacturers' directory: complete editions 1965-68, 1970 = "before"; first listing 1973-1980 = "arrival"
# sites.csv's GEOID is the EnviroScreen (2020) tract, not a 2010 tract: sites are placed in the 2010 tracts by their coordinates
st <- fread("app/data/sites.csv", colClasses = c(GEOID = "character"))[fe_hazard %in% c(TRUE, "True") & !is.na(lat)]
TR10 <- st_make_valid(st_transform(st_read("app/data/co_tracts_2010.geojson", quiet = TRUE), UTM))
sp <- st_transform(st_as_sf(st[, .(lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)
k <- vapply(st_within(sp, TR10), function(i) if (length(i)) i[1] else NA_integer_, 1L)
miss <- which(is.na(k)); if (length(miss)) { nn <- st_nearest_feature(sp[miss, ], TR10); d <- as.numeric(st_distance(sp[miss, ], TR10[nn, ], by_element = TRUE)); k[miss[d <= 100]] <- nn[d <= 100] }   # on a simplified edge
st[, GEOID := TR10$GEOID[k]]; st <- st[!is.na(GEOID)]
sy <- fread("app/data/site_years.csv"); ED_OK <- c(1965:1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992); sy <- sy[year %in% ED_OK & site_id %in% st$site_id]
sy <- merge(sy, st[, .(site_id, GEOID)], by = "site_id")
tf <- sy[, .(first = min(year)), by = GEOID]; tb <- sy[year <= 1970, .N, by = GEOID]
W2 <- dcast(P[census %in% c(1960, 1970, 1980, 1990)], GEOID + cls ~ census, value.var = c("pop", "p_black", "p_hisp", "p_fb", "p_pov", "p_owner"))
W2[, before := GEOID %in% tb$GEOID]; W2 <- merge(W2, tf, by = "GEOID", all.x = TRUE)
W2[, group := fifelse(before, "hazardous manufacturer listed 1965-70", fifelse(!is.na(first) & first <= 1980, "first listed 1973-80 (arrival)", fifelse(!is.na(first), "first listed 1983-92", "none listed 1965-92")))]
wmn <- function(v, w) { ok <- !is.na(v) & !is.na(w); if (!any(ok)) NA_real_ else round(weighted.mean(v[ok], w[ok]), 2) }
B2 <- W2[, .(tracts = .N, pop_1970 = round(sum(pop_1970, na.rm = TRUE)), km_note = NA,
             pct_hisp_1960 = wmn(p_hisp_1960, pop_1960), pct_hisp_1970 = wmn(p_hisp_1970, pop_1970), pct_hisp_1990 = wmn(p_hisp_1990, pop_1990),
             pct_black_1970 = wmn(p_black_1970, pop_1970), pct_black_1990 = wmn(p_black_1990, pop_1990),
             pct_poverty_1970 = wmn(p_pov_1970, pop_1970), pct_poverty_1990 = wmn(p_pov_1990, pop_1990),
             pct_owner_1970 = wmn(p_owner_1970, pop_1970), pct_owner_1990 = wmn(p_owner_1990, pop_1990)), by = group][, km_note := NULL]
B2[, `:=`(chg_hisp_1970_90 = pct_hisp_1990 - pct_hisp_1970, chg_black_1970_90 = pct_black_1990 - pct_black_1970, chg_poverty_1970_90 = pct_poverty_1990 - pct_poverty_1970, chg_owner_1970_90 = pct_owner_1990 - pct_owner_1970)]
fwrite(B2, file.path(O, "tract_first_arrival_1965_1992.csv"))
# ---------------------------------------------------------------- C. timeline of each future D area
# area weighting as in aw() above: carry each district's own area through the intersection, so a piece counts area(piece) / area(district)
#   of the district's people (st_intersection of two sf objects keeps no "idx" attribute, so it cannot be used to look the area up)
ca <- function(y) { e <- E[[as.character(y)]]; e$src_a <- as.numeric(st_area(e)); x <- suppressWarnings(st_intersection(e[, c("pop", "black", "hisp", "src_a")], H[H$cls == "D", "area_id"]))
  w <- as.numeric(st_area(x)) / x$src_a
  d <- as.data.table(st_drop_geometry(x))[, w := w][, .(pop = sum(pop * w), black = sum(black * w, na.rm = TRUE), hisp = sum(hisp * w, na.rm = TRUE)), by = area_id][, census := y]
  city <- as.data.table(st_drop_geometry(e))[, .(cb = sum(black, na.rm = TRUE) / sum(pop), ch = sum(hisp, na.rm = TRUE) / sum(pop))]; d[, `:=`(lq_black = (black / pop) / city$cb, lq_hisp = (hisp / pop) / city$ch)] }
TL <- rbindlist(lapply(YRS, function(y) tryCatch(ca(y), error = function(e) NULL)))
hd <- st_join(hp, H[H$cls == "D", "area_id"], left = FALSE); f1 <- as.data.table(st_drop_geometry(hd))[, .(first_trade = min(first_year), trades_by_1937 = sum(first_year <= 1937)), by = area_id]
C <- TL[, .(pop_1930 = round(pop[census == 1930]), first_black_lq2 = if (any(lq_black >= 2 & pop >= 100)) min(census[lq_black >= 2 & pop >= 100]) else NA_real_,
            first_hisp_lq2 = if (any(lq_hisp >= 2 & pop >= 100)) min(census[lq_hisp >= 2 & pop >= 100]) else NA_real_,
            lq_black_1900 = round(lq_black[census == 1900], 2), lq_black_1940 = round(lq_black[census == 1940], 2)), by = area_id]
C <- merge(C, f1, by = "area_id", all.x = TRUE); C[is.na(trades_by_1937), trades_by_1937 := 0L]
lab <- as.data.table(st_drop_geometry(H))[, .(area_id, label)]; C <- merge(lab, C, by = "area_id")[order(label)]
fwrite(C, file.path(O, "d_area_timeline.csv"))
file.copy(list.files(O, "\\.csv$", full.names = TRUE), A, overwrite = TRUE)
message("grid cells: ", nrow(gr), "; on the 1929 sheet: ", sum(gr$on_sheet), "; tracts in the fixed set: ", length(fix))
print(A1[census %in% c(1900, 1920, 1940), .(group, census, cells, pct_black, lq_black, lq_hisp, lq_fb, lq_laborers, owner_ratio, cells_ever_firm)])
print(A2); print(A3); print(B1[census %in% c(1940, 1960, 1980, 2000, 2020) & !grepl("not graded", cls), .(cls, census, tracts, lq_black, lq_hisp, lq_poverty)]); print(B2); print(C)
