# Where Denver's residents lived in 1940 and how long they lived: the 1940 census linked to Social Security death records (CenSoc).
#
#   Rscript R/censoc_denver_1940.R
#
# Inputs (all stay in work/, which git ignores; none of the person-level files is redistributed):
#   work/censoc/*.csv     CenSoc-Numident (men and women, deaths 1988-2005) and/or CenSoc-DMF (men, deaths 1975-2020), free from the
#                         CenSoc Dataverse, https://dataverse.harvard.edu/dataverse/censoc (Breen, Osborne & Goldstein 2023). Put the
#                         unzipped main files here (not the "demo" files); the script recognises them by "numident" / "dmf" in the name.
#   work/ipums/*.xml      the IPUMS USA 1940 full-count extract for Colorado from R/fetch_ipums_fullcount.R (it carries HISTID)
#   work/census/brown/grf/DenverCO/DenverCO_1940.csv   Brown Urban Transition GRF: every 1940 Denver resident's street address + HISTID
#   work/census/grf_geocoded_1940_R.csv                those addresses geocoded at street level (R/grf_eds.R)
#   app/data/historical_sites.csv, holc_denver.geojson, zoning_1929.geojson; work/usgs_landuse/landuse_groups_10m.tif or app/data/landuse_1937_20m.tif (R/landuse_1937_1997.R)
# Design
#   CenSoc links people in the 1940 census to their Social Security death record by HISTID. Each linked Denver resident of 1940 gets the
#   street address of their 1940 household (GRF), and at that address: the 1938 HOLC grade, the 1929 zoning district, the share of land
#   within 250 m in industrial use in 1937 (USGS), and the hazardous trades (Frickel & Elliott sectors) listed in the city directories up
#   to 1940, as a Gaussian kernel (500 m bandwidth, 2 km cutoff; the same exposure as the block mortality models) and as any within 500 m.
#   Commercial land within 250 m is the placebo (busy, central land that is not industrial).
#   Outcome: age at death. Following CenSoc's guidance for these truncated windows, OLS with birth-year fixed effects (and sex for the
#   Numident), CenSoc's post-stratification weights, conservative links only where the file flags them, and errors clustered by 1940 ED.
#   Controls from the 1940 census: race, Hispanic origin, foreign birth (Mexico separately), born in Colorado, moved in 1935-40, and the
#   household's tenure, rent or home value (quintile within tenure), the head's schooling and occupational standing (SEI).
#   M2 = exposure + controls; M3 adds 1940 ED fixed effects, so only the address-level variation within a district is used.
# Outputs (aggregates only): data/results/censoc/{censoc_linkage.csv, censoc_models.csv, censoc_groups.csv, censoc_summary.md}
# and work/censoc/censoc_denver_1940_linked.rds (person-level, stays on this machine).
for (p in c("ipumsr", "RANN", "sandwich", "lmtest", "terra")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(data.table); library(sf); library(terra); library(sandwich); library(lmtest) })
sf_use_s2(FALSE); UTM <- 26913; W <- "work/censoc"; O <- "data/results/censoc"; A <- "app/data"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
cs <- Sys.glob(file.path(W, "*.csv")); cs <- cs[!grepl("demo|geography|codebook|sib", basename(cs), ignore.case = TRUE)]
cs <- cs[grepl("numident|dmf", basename(cs), ignore.case = TRUE)]
if (!length(cs)) stop("put the CenSoc-Numident and/or CenSoc-DMF csv files in work/censoc/ (https://dataverse.harvard.edu/dataverse/censoc)")
# ---------------------------------------------------------------- 1. the 1940 census: Denver residents with HISTID and household traits
ddis <- rev(sort(Sys.glob("work/ipums/*.xml"))); use <- NULL
for (f in ddis) { v <- ipumsr::read_ipums_ddi(f)$var_info$var_name; if (all(c("HISTID", "SEI", "EDUC", "OWNERSHP", "MIGRATE5", "RENT", "VALUEH") %in% v)) { use <- f; break } }
if (is.null(use)) stop("no IPUMS extract with HISTID, SEI, EDUC, OWNERSHP, MIGRATE5, RENT and VALUEH in work/ipums/: run R/fetch_ipums_fullcount.R")
V <- c("YEAR", "SERIAL", "PERNUM", "HISTID", "COUNTYICP", "CITY", "ENUMDIST", "RELATE", "SEX", "AGE", "RACE", "HISPAN", "BPL", "EDUC", "SEI", "OWNERSHP", "RENT", "VALUEH", "MIGRATE5", "GQ", "IND1950", "OCC1950", "LABFORCE")
P <- as.data.table(ipumsr::read_ipums_micro(ipumsr::read_ipums_ddi(use), vars = dplyr::all_of(V), verbose = FALSE))
P <- P[YEAR == 1940 & (CITY == 1710 | COUNTYICP == 310)]; for (v in setdiff(V, "HISTID")) P[[v]] <- as.numeric(P[[v]])
P[, HISTID := toupper(trimws(as.character(HISTID)))]
HAZ_IND <- c(206:239, 336:339, 346:349, 356:359, 376:379, 466:469, 476:478)   # IND1950 hazardous industries, as in R/fetch_ipums_fullcount.R
H <- P[RELATE == 1, .(SERIAL, h_haz_job = as.numeric(IND1950 %in% HAZ_IND), h_manuf = as.numeric(IND1950 >= 306 & IND1950 <= 499), h_hs = fifelse(EDUC > 0 & EDUC < 99, as.numeric(EDUC >= 6), NA_real_), h_sei = fifelse(SEI > 0, SEI, NA_real_),
                      owner = as.numeric(OWNERSHP == 1), rent = fifelse(OWNERSHP == 2 & RENT > 0 & RENT < 9998, RENT, NA_real_),
                      value = fifelse(OWNERSHP == 1 & VALUEH > 0 & VALUEH < 9999998, VALUEH, NA_real_))]
H[, hc_q := NA_integer_]
H[owner == 1 & !is.na(value), hc_q := as.integer(cut(value, unique(quantile(value, 0:5 / 5)), include.lowest = TRUE))]
H[owner == 0 & !is.na(rent), hc_q := as.integer(cut(rent, unique(quantile(rent, 0:5 / 5)), include.lowest = TRUE))]
P <- merge(P, H, by = "SERIAL", all.x = TRUE)
P[, `:=`(black = as.numeric(RACE == 2), hisp = as.numeric(HISPAN > 0 & HISPAN < 9), fb = as.numeric(BPL >= 150 & BPL < 900), fb_mex = as.numeric(BPL == 200),
         born_co = as.numeric(BPL == 8), mover = fifelse(MIGRATE5 %in% 1:4, as.numeric(MIGRATE5 %in% 2:4), NA_real_), gq = as.numeric(GQ >= 3))]
message(format(nrow(P), big.mark = ","), " Denver residents in the 1940 census (", basename(use), ")")
# ---------------------------------------------------------------- 2. 1940 street addresses (GRF) and their geocodes
G <- fread("work/census/brown/grf/DenverCO/DenverCO_1940.csv", colClasses = "character", select = c("histid", "b_ed", "b_hn", "b_stfull"))
G[, num := ifelse(grepl("[0-9]", b_hn), suppressWarnings(as.integer(sub("^[^0-9]*([0-9]+).*$", "\\1", b_hn))), NA_integer_)]   # same address key as R/grf_eds.R
G[, addr := fifelse(!is.na(num) & nzchar(b_stfull), paste(num, trimws(gsub("[^A-Z0-9 ]", "", toupper(b_stfull)))), NA_character_)]
G[, HISTID := toupper(trimws(histid))]
C <- fread("work/census/grf_geocoded_1940_R.csv", colClasses = c(addr = "character"))[grepl("^(fuzzy_)?range_interp", q) & !is.na(lat)]
G <- merge(G[, .(HISTID, ED = b_ed, addr)], C[, .(addr, lat, lon)], by = "addr", all.x = TRUE)
# stray geocodes dropped as in R/grf_eds.R: farther from the ED's person-weighted median centre than max(400 m, 2.5 x the ED's median distance)
xy <- st_coordinates(st_transform(st_as_sf(G[!is.na(lat), .(lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)); G[!is.na(lat), `:=`(x = xy[, 1], y = xy[, 2])]
G[!is.na(x), `:=`(mx = median(x), my = median(y)), by = ED]; G[, dd := sqrt((x - mx)^2 + (y - my)^2)]
G[!is.na(dd), thr := if (.N >= 5) max(400, 2.5 * median(dd)) else 600, by = ED]; G[!is.na(dd) & dd > thr, c("x", "y") := NA_real_]
P <- merge(P, G[, .(HISTID, ED, x, y)], by = "HISTID", all.x = TRUE)
message(sprintf("%.1f%% of 1940 residents found in the GRF; %.1f%% with a street-level address point", 100 * mean(!is.na(P$ED)), 100 * mean(!is.na(P$x))))
# ---------------------------------------------------------------- 3. exposures at the 1940 address
pts <- P[!is.na(x), .(x, y)][, k := .I]; U <- unique(pts[, .(x, y)]); U[, u := .I]
Hs <- fread(file.path(A, "historical_sites.csv"))[town == "DENVER" & precision != "town" & !is.na(lat) & fe_hazard %in% c(TRUE, "True") & first_year <= 1940]
hx <- st_coordinates(st_transform(st_as_sf(Hs[, .(lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM))
nn <- RANN::nn2(hx, as.matrix(U[, .(x, y)]), k = min(nrow(hx), 200), searchtype = "radius", radius = 2000)
d <- nn$nn.dists; d[nn$nn.idx == 0] <- NA
U[, `:=`(haz_k = rowSums(exp(-0.5 * (d / 500)^2), na.rm = TRUE), haz_500 = as.numeric(rowSums(d <= 500, na.rm = TRUE) > 0),
         haz_km = fifelse(is.na(d[, 1]), 2, d[, 1] / 1000))]
S <- fread(file.path(A, "sites.csv"))[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx") & !is.na(lat) & !is.na(lon)]
kern <- function(px) { if (!nrow(px)) return(rep(0, nrow(U))); q <- RANN::nn2(px, UXY, k = min(nrow(px), 300), searchtype = "radius", radius = 2000)
  dd <- q$nn.dists; dd[q$nn.idx == 0] <- NA; rowSums(exp(-0.5 * (dd / 500)^2), na.rm = TRUE) }
sx <- function(d) st_coordinates(st_transform(st_as_sf(d[, .(lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM))
UXY <- as.matrix(U[, .(x, y)]); hk <- kern(sx(S[radar == "Not on any list"])); kk <- kern(sx(S[radar != "Not on any list"]))
U[, `:=`(hidden_k = hk, known_k = kk)]   # sites listed 1965-92: later exposure at the same address
Us <- st_as_sf(U, coords = c("x", "y"), crs = UTM)
Hh <- st_make_valid(st_transform(st_read(file.path(A, "holc_denver.geojson"), quiet = TRUE), UTM)); Hh <- Hh[Hh$grade %in% c("A", "B", "C", "D"), "grade"]
j <- st_join(Us, Hh, join = st_within, left = TRUE); j <- j[!duplicated(j$u), ]; U[, holc := fifelse(is.na(j$grade), "ungraded", j$grade)]
Z <- st_make_valid(st_transform(st_read(file.path(A, "zoning_1929.geojson"), quiet = TRUE), UTM))
g <- fread("data/results/zoning_1929/gcp_fit.csv"); fx <- lm(X ~ px_x + px_y, g); fy <- lm(Y ~ px_x + px_y, g)
PX <- function(px, py) cbind(predict(fx, data.frame(px_x = px, px_y = py)), predict(fy, data.frame(px_x = px, px_y = py)))
SHEET <- st_sfc(st_polygon(list(rbind(PX(0, 0), PX(11849, 0), PX(11849, 12000), PX(0, 12000), PX(0, 0)))), crs = UTM)
zj <- st_join(Us, Z[, "zone"], join = st_within, left = TRUE); zj <- zj[!duplicated(zj$u), ]
U[, zone29 := fifelse(!is.na(zj$zone), fifelse(grepl("Industrial", zj$zone), "industrial", "commercial"), fifelse(lengths(st_within(Us, SHEET)) > 0, "residence", "off the map"))]
LUF <- "work/usgs_landuse/landuse_groups_10m.tif"                               # layer 1 = 1937; values 1-8 = R/landuse_1937_1997.R groups
LU <- if (file.exists(LUF)) rast(LUF)[[1]] else rast(file.path(A, "landuse_1937_20m.tif"))   # else the 20 m 1937 layer the app uses
LU <- crop(LU, ext(project(vect(st_buffer(st_as_sfc(st_bbox(Us)), 500)), crs(LU))))
lu50 <- function(code) aggregate(ifel(is.na(LU), NA, LU == code), fact = max(1, round(50 / res(LU)[1])), fun = "mean", na.rm = TRUE)   # share of each ~50 m cell
wm <- focalMat(lu50(1), 250, "circle"); wm[wm > 0] <- 1
shr <- function(code) { r <- lu50(code); focal(r, wm, fun = "sum", na.rm = TRUE) / focal(!is.na(r), wm, fun = "sum", na.rm = TRUE) }
pv <- project(vect(Us), crs(LU))
U[, `:=`(ind37 = 100 * extract(shr(1), pv)[, 2], com37 = 100 * extract(shr(4), pv)[, 2])]
P <- merge(P, U, by = c("x", "y"), all.x = TRUE)
P[, `:=`(haz_job = as.numeric(LABFORCE == 2 & IND1950 %in% HAZ_IND), manuf_job = as.numeric(LABFORCE == 2 & IND1950 >= 306 & IND1950 <= 499))]
saveRDS(P, file.path(W, "denver_1940_residents.rds"))   # every 1940 resident with the address exposures (for R/censoc_extensions.R; stays on this machine)
# ---------------------------------------------------------------- 4. CenSoc links
rd <- function(f) { h <- names(fread(f, nrows = 0)); keep <- intersect(h, c("HISTID", "histid", "byear", "bmonth", "dyear", "dmonth", "death_age", "sex", "weight", "link_abe_exact_conservative"))
  x <- fread(f, select = keep, colClasses = list(character = intersect(keep, c("HISTID", "histid")))); setnames(x, tolower(names(x))); x[, histid := toupper(trimws(histid))]
  if ("link_abe_exact_conservative" %in% names(x)) x <- x[link_abe_exact_conservative == 1]
  if (!"death_age" %in% names(x)) x[, death_age := dyear - byear - (dmonth < bmonth)]
  if (!"sex" %in% names(x)) x[, sex := 1]
  x[, file := if (grepl("numident", basename(f), ignore.case = TRUE)) "Numident (men and women, deaths 1988-2005)" else "DMF (men, deaths 1975 on)"]; x }
CS <- rbindlist(lapply(cs, rd), fill = TRUE)
L <- merge(CS, P, by.x = "histid", by.y = "HISTID")
L[, female := as.numeric(sex == 2)]
saveRDS(L, file.path(W, "censoc_denver_1940_linked.rds"))
LK <- L[, .(linked = .N, with_address_point = sum(!is.na(x)), min_dyear = min(dyear), max_dyear = max(dyear), median_death_age = as.numeric(median(death_age)),
            median_age_1940 = as.numeric(median(AGE))), by = file]
LK <- rbind(data.table(file = "1940 census, Denver residents", linked = nrow(P), with_address_point = sum(!is.na(P$x))), LK, fill = TRUE)
fwrite(LK, file.path(O, "censoc_linkage.csv")); print(LK)
# ---------------------------------------------------------------- 5. models of age at death
L <- L[!is.na(x) & !is.na(byear) & !is.na(death_age) & gq == 0]
L[, `:=`(hc_q = factor(fifelse(is.na(hc_q), 0L, hc_q)), h_hs_m = as.numeric(is.na(h_hs)), h_hs = fifelse(is.na(h_hs), 0, h_hs),
         h_sei_m = as.numeric(is.na(h_sei)), h_sei = fifelse(is.na(h_sei), 0, h_sei), mover_m = as.numeric(is.na(mover)), mover = fifelse(is.na(mover), 0, mover),
         owner = fifelse(is.na(owner), 0, owner), w = if ("weight" %in% names(L)) weight else 1)]
L <- L[!is.na(w) & w > 0]
sdk <- sd(L$haz_k)
L[, `:=`(hidden_kz = hidden_k / sd(hidden_k), known_kz = known_k / sd(known_k))]
L[, `:=`(haz_kz = haz_k / sdk, ind10 = ind37 / 10, com10 = com37 / 10, holc_D = as.numeric(holc == "D"), holc_C = as.numeric(holc == "C"),
         holc_ungraded = as.numeric(holc == "ungraded"), zone_ind = as.numeric(zone29 == "industrial"))]
CTRL <- "black + hisp + fb + fb_mex + born_co + mover + mover_m + owner + hc_q + h_hs + h_hs_m + h_sei + h_sei_m"
EXP <- list(`Hazardous trades to 1940, kernel (per SD)` = "haz_kz", `Hazardous trade within 500 m` = "haz_500",
            `Industrial land within 250 m, 1937 (per 10 points)` = "ind10", `Placebo: commercial land within 250 m, 1937 (per 10 points)` = "com10",
            `1929 industrial district` = "zone_ind",
            `Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD)` = "hidden_kz", `Later (1965-92) manufacturers on an inventory, kernel (per SD)` = "known_kz", `HOLC grade D (vs A/B)` = c("holc_D", "holc_C", "holc_ungraded"))
fit <- function(d, rhs, term, label, model, fe) {
  if (length(unique(d[[term]])) < 2) return(NULL)
  f <- as.formula(paste("death_age ~", rhs, "+ factor(byear)", if (uniqueN(d$female) > 1) "+ female", if (fe) "+ factor(ED)"))
  m <- lm(f, data = d, weights = w); ct <- coeftest(m, vcov. = vcovCL(m, cluster = ~ED, type = "HC1"))
  if (!term %in% rownames(ct)) return(NULL)
  data.table(file = d$file[1], model = model, exposure = label, term = term, years = round(ct[term, 1], 3), se = round(ct[term, 2], 3),
             lo = round(ct[term, 1] - 1.96 * ct[term, 2], 3), hi = round(ct[term, 1] + 1.96 * ct[term, 2], 3), p = signif(ct[term, 4], 3), n = nobs(m)) }
R <- list()
for (fl in unique(L$file)) { d <- L[file == fl]
  for (e in names(EXP)) { t <- EXP[[e]]; rhs <- paste(t, collapse = " + ")
    R[[length(R) + 1]] <- fit(d, rhs, t[1], e, "M1: birth year (and sex) only", FALSE)
    R[[length(R) + 1]] <- fit(d, paste(rhs, "+", CTRL), t[1], e, "M2: + 1940 person and household controls", FALSE)
    if (e != "HOLC grade D (vs A/B)" && e != "1929 industrial district") R[[length(R) + 1]] <- fit(d, paste(rhs, "+", CTRL), t[1], e, "M3: + 1940 ED fixed effects", TRUE) }
  R[[length(R) + 1]] <- fit(d, paste("haz_kz + ind10 + com10 +", CTRL), "haz_kz", "Hazardous trades kernel, with industrial and commercial land", "M2 joint", FALSE)
  R[[length(R) + 1]] <- fit(d, paste("haz_kz + ind10 + com10 +", CTRL), "ind10", "Industrial land, with hazardous trades and commercial land", "M2 joint", FALSE) }
R <- rbindlist(R); fwrite(R, file.path(O, "censoc_models.csv")); print(R[, .(file = substr(file, 1, 8), model = substr(model, 1, 3), exposure = substr(exposure, 1, 40), years, lo, hi, p, n)])
# ---------------------------------------------------------------- 6. mean age at death by 1940 address, net of birth year (and sex)
L[, resid := residuals(lm(death_age ~ factor(byear) + female, data = .SD, weights = w)) + weighted.mean(death_age, w), by = file]
grp <- function(v, lab) { L[, g_ := as.character(get(v))]; r <- L[, .(n = .N, adj_mean_age_at_death = round(weighted.mean(resid, w), 2)), by = .(file, group = g_)]; r[, measure := lab]; setcolorder(r, c("file", "measure")); r }
L[, `:=`(haz500_g = fifelse(haz_500 == 1, "hazardous trade within 500 m", "none within 500 m"), ind_g = fifelse(ind37 >= 10, "10%+ industrial within 250 m", "under 10%"))]
GR <- rbind(grp("holc", "1938 HOLC grade"), grp("zone29", "1929 zoning district"), grp("haz500_g", "Hazardous trades to 1940"), grp("ind_g", "Industrial land 1937"))
GR <- GR[n >= 20][order(file, measure, group)]; fwrite(GR, file.path(O, "censoc_groups.csv")); print(GR)
# ---------------------------------------------------------------- 7. summary
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
md <- c("# Denver residents of 1940 and their age at death (CenSoc)", "", "## Linkage", "", kab(LK), "", "## Age at death (years) per unit of exposure at the 1940 address", "",
        kab(R[, .(file, model, exposure, years, ci = sprintf("%.2f to %.2f", lo, hi), p, n)]), "", "## Mean age at death, net of birth year and sex (groups of 20+)", "", kab(GR))
writeLines(md, file.path(O, "censoc_summary.md")); message("wrote ", O)
