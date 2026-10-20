# Do historical hazardous sites show up in Denver home prices? A hedonic model of residential sales, 2015-.
#
#   Rscript R/fetch_denver_property.R     (once; public Assessor records into work/property/)
#   Rscript R/hedonic_denver.R
#
# Question: do homes that sell near a historical hazardous site sell for less than otherwise similar homes in the same market
# neighbourhood and year, and does it matter whether the site is on a current environmental inventory ("known") or not ("hidden")?
# A buyer can see a cleanup listing in a disclosure or database search; a hidden site leaves no record, so if prices respond to
# information, the discount should appear near known sites but not near hidden ones, even where the hazard history is similar.
#
# Sample: arm's-length residential sales (warranty or special-warranty deeds, price >= $25,000, one parcel per reception number),
# single-family, rowhouse, duplex/triplex and condominium units, 2015 onwards; prices trimmed at the 1st/99th percentile by year and type.
# Location: the parcel's situs point. Exposure: distance from the sale to the nearest site of each kind, in bands
# 0-200 m, 200-400 m and 400-800 m (reference: farther than 800 m), for
#   hidden  = 1965-92 hazardous-sector manufacturers on no current inventory
#   known   = 1965-92 hazardous-sector manufacturers on a current inventory
#   pre1960 = hazardous trades before 1960 (street level)
# Model: log(price) on the bands, house characteristics (above-grade area, basement and finished basement, bedrooms, baths, stories,
# land area, age and age squared, property type) and fixed effects for market neighbourhood x sale year and sale month;
# errors clustered by census tract.
#   M1 base; M2 adds present-day hazards and amenities that sit near old industry (a petroleum release within 100 m, a TRI facility
#   within 500 m, inside a Superfund operable unit, a freeway within 250 m, parcel zoned industrial);
#   M3 tract x year fixed effects instead of neighbourhood x year; M4 single-family homes only; M5 counts of sites within 400 m.
# Outputs (aggregates only): data/results/hedonic/hedonic_models.csv, hedonic_sample.csv, hedonic_summary.md; app/data/hedonic_models.csv
for (p in c("data.table", "sf", "fixest")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(data.table); library(sf); library(fixest) })
sf_use_s2(FALSE); UTM <- 26913; D <- "work/property"; A <- "app/data"; O <- "data/results/hedonic"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
if (!file.exists(file.path(D, "sales.csv"))) stop("run Rscript R/fetch_denver_property.R first")
num <- function(x) suppressWarnings(as.numeric(x))
# ---------------------------------------------------------------- sales
SA <- fread(file.path(D, "sales.csv"), colClasses = "character")
SA[, `:=`(price = num(SALE_PRICE), year = as.integer(SALE_YEAR), rdate = as.Date(RECEPTION_DATE, "%Y%m%d"))]
SA[, month := as.integer(format(rdate, "%m"))]
SA[, sched := sprintf("%013.0f", num(PARID))]
SA[, nparc := uniqueN(sched), by = RECEPTION_NUM]
SA[, type := fcase(grepl("CONDO", D_CLASS_N, ignore.case = TRUE), "Condominium", grepl("ROW", D_CLASS_N, ignore.case = TRUE), "Rowhouse",
                   grepl("DUPLEX|TRIPLEX|TWO.?FAM|MULTI.?UNIT \\(2|DOUBLE", D_CLASS_N, ignore.case = TRUE), "Duplex / triplex",
                   grepl("SINGLE|RESIDENTIAL$|RESIDENTIAL-SFR|^SFR", D_CLASS_N, ignore.case = TRUE), "Single family", default = NA_character_)]
n0 <- nrow(SA)
SA <- SA[!is.na(price) & price >= 25000 & grepl("^(WD|SW)", INSTRUMENT) & nparc == 1 & !is.na(type) & year >= 2015 & !is.na(month)]
SA[, `:=`(lo = quantile(price, .01), hi = quantile(price, .99)), by = .(year, type)]; SA <- SA[price >= lo & price <= hi]
message(nrow(SA), " arm's-length residential sales kept of ", n0, " transfers")
# ---------------------------------------------------------------- parcels (location, zoning) and characteristics
PA <- fread(file.path(D, "parcels.csv"), colClasses = "character")[, .(sched = SCHEDNUM, x = num(SITUS_X_COORD), y = num(SITUS_Y_COORD), zone = ZONE_10,
                                                                      p_yb = num(RES_ORIG_YEAR_BUILT), p_area = num(RES_ABOVE_GRADE_AREA), p_land = num(LAND_AREA))]
PA <- PA[!is.na(x) & x > 0 & !duplicated(sched)]
RC <- fread(file.path(D, "res_chars.csv"), colClasses = "character")
RC[, sched := sprintf("%013.0f", num(PARID))]; RC <- RC[order(sched, num(OFCARD))][!duplicated(sched)]
RC <- RC[, .(sched, area = num(AREA_ABG), bsmt = num(BSMT_AREA), fbsmt = num(FBSMT_SQFT), beds = num(BED_RMS), fbath = num(FULL_B), hbath = num(HLF_B),
             story = num(STORY), yb = num(CCYRBLT), land = num(LAND_SQFT), nbhd = NBHD_1)]
M <- merge(SA[, .(sched, price, year, month, type, nbhd_s = NBHD_1)], PA, by = "sched")
M <- merge(M, RC, by = "sched", all.x = TRUE)
M[, `:=`(area = fifelse(is.na(area) | area <= 0, p_area, area), yb = fifelse(is.na(yb) | yb < 1850, p_yb, yb), land = fifelse(is.na(land) | land <= 0, p_land, land),
         nbhd = fifelse(is.na(nbhd) | nbhd == "", nbhd_s, nbhd))]
M <- M[!is.na(area) & area >= 300 & area <= 10000 & !is.na(yb) & yb >= 1860 & yb <= year & !is.na(nbhd)]
for (v in c("bsmt", "fbsmt", "beds", "fbath", "hbath", "story", "land")) { M[, (paste0(v, "_m")) := as.numeric(is.na(get(v)))]; M[is.na(get(v)), (v) := 0] }
M[, `:=`(lp = log(price), larea = log(area), lland = log1p(land), age = year - yb, bsmt_k = bsmt / 1000, fbsmt_k = fbsmt / 1000)]
M[, age2 := age^2 / 100]
pts <- st_transform(st_as_sf(M[, .(x, y)], coords = c("x", "y"), crs = 2877), UTM)
# ---------------------------------------------------------------- the historical sites (as in R/context_layers.R)
S <- fread(file.path(A, "sites.csv"))[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx") & !is.na(lat) & !is.na(lon)]
S <- S[, .(kind = fifelse(radar == "Not on any list", "hidden", "known"), lat, lon)]
H <- fread(file.path(A, "historical_sites.csv"))[fe_hazard %in% c(TRUE, "True") & precision != "town" & !is.na(lat) & town == "DENVER"]
SITES <- rbind(S, H[, .(kind = "pre1960", lat, lon)])
SITES_sf <- st_transform(st_as_sf(SITES, coords = c("lon", "lat"), crs = 4326), UTM)
nearest_m <- function(tgt) { if (!nrow(tgt)) return(rep(Inf, nrow(M))); i <- st_nearest_feature(pts, tgt); as.numeric(st_distance(pts, tgt[i, ], by_element = TRUE)) }
band <- function(d) factor(fcase(d <= 200, "0-200 m", d <= 400, "200-400 m", d <= 800, "400-800 m", default = "over 800 m"), levels = c("over 800 m", "0-200 m", "200-400 m", "400-800 m"))
for (k in c("hidden", "known", "pre1960")) {
  d <- nearest_m(SITES_sf[SITES_sf$kind == k, ]); M[, (paste0("d_", k)) := d]; M[, (paste0("b_", k)) := band(d)]
  M[, (paste0("n400_", k)) := lengths(st_is_within_distance(pts, SITES_sf[SITES_sf$kind == k, ], 400))] }
# ---------------------------------------------------------------- present-day hazards and amenities near old industry
PR <- fread(file.path(A, "petroleum_releases_study.csv"))[!is.na(lat) & !is.na(lon)]
M[, petro_100 := as.numeric(lengths(st_is_within_distance(pts, st_transform(st_as_sf(PR, coords = c("lon", "lat"), crs = 4326), UTM), 100)) > 0)]
TRI <- unique(fread(file.path(A, "tri_facility_years_study.csv"))[!is.na(lat), .(trifd, lat, lon)], by = "trifd")
M[, tri_500 := as.numeric(lengths(st_is_within_distance(pts, st_transform(st_as_sf(TRI, coords = c("lon", "lat"), crs = 4326), UTM), 500)) > 0)]
SFU <- st_make_valid(st_transform(st_read(file.path(A, "superfund_ou_study.geojson"), quiet = TRUE), UTM))
M[, superfund := as.numeric(lengths(st_intersects(pts, SFU)) > 0)]
HW <- st_transform(st_read(file.path(A, "highways_denver.geojson"), quiet = TRUE), UTM); HW <- HW[HW$kind == "Freeway", ]
M[, freeway_250 := as.numeric(lengths(st_is_within_distance(pts, HW, 250)) > 0)]
M[, zoned_ind := as.numeric(grepl("^I-|^I-[ABMX]|^IMX|^IA|^IB", toupper(zone)))]
TR <- st_transform(st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE), UTM)
M[, tract := TR$GEOID[vapply(st_within(pts, TR), function(i) if (length(i)) i[1] else NA_integer_, 1L)]]
M <- M[!is.na(tract)]
message(nrow(M), " sales in the model sample; ", sum(M$d_hidden <= 400), " within 400 m of a hidden site, ", sum(M$d_known <= 400), " of a known site")
# ---------------------------------------------------------------- models
X <- "larea + bsmt_k + fbsmt_k + beds + fbath + hbath + story + lland + age + age2 + bsmt_m + fbsmt_m + beds_m + fbath_m + hbath_m + story_m + land_m"
B3 <- "b_hidden + b_known + b_pre1960"; CUR <- "petro_100 + tri_500 + superfund + freeway_250 + zoned_ind"
FE_N <- "nbhd^year + month + type"; FE_T <- "tract^year + month + type"
tidy <- function(m, model, sample) { ct <- as.data.table(coeftable(m), keep.rownames = "term"); setnames(ct, c("term", "estimate", "se", "t", "p"))
  ct <- ct[grepl("^b_|^n400_|petro_100|tri_500|superfund|freeway_250|zoned_ind", term)]
  ct[, `:=`(kind = fcase(grepl("hidden", term), "Hidden (no current inventory)", grepl("known", term), "Known (on a current inventory)", grepl("pre1960", term), "Pre-1960 hazardous trade",
                         default = "Present-day control"),
            distance = fifelse(grepl("^b_", term), sub("^b_(hidden|known|pre1960)(::)?", "", term), fifelse(grepl("^n400", term), "per site within 400 m", term)),
            pct = round(100 * (exp(estimate) - 1), 2), lo = round(100 * (exp(estimate - 1.96 * se) - 1), 2), hi = round(100 * (exp(estimate + 1.96 * se) - 1), 2),
            p = signif(p, 3), n = nobs(m), model = model, sample = sample)]
  ct[, .(model, sample, kind, distance, pct, lo, hi, p, estimate = round(estimate, 4), se = round(se, 4), n)] }
fit <- function(rhs, fe, d = M) feols(as.formula(paste("lp ~", rhs, "+", X, "|", fe)), data = d, cluster = ~tract)
RES <- rbindlist(list(
  tidy(fit(B3, FE_N), "M1 base: neighbourhood x year FE", "All residential sales"),
  tidy(fit(paste(B3, "+", CUR), FE_N), "M2 + present-day hazards", "All residential sales"),
  tidy(fit(paste(B3, "+", CUR), FE_T), "M3 tract x year FE", "All residential sales"),
  tidy(fit(paste(B3, "+", CUR), FE_N, M[type == "Single family"]), "M2 + present-day hazards", "Single-family homes"),
  tidy(fit(paste("n400_hidden + n400_known + n400_pre1960 +", CUR), FE_N), "M5 site counts within 400 m", "All residential sales")))
# hidden vs known within 400 m: one pooled indicator each, and the test of equality
M[, `:=`(hid400 = as.numeric(d_hidden <= 400), kn400 = as.numeric(d_known <= 400), pre400 = as.numeric(d_pre1960 <= 400))]
m6 <- fit(paste("hid400 + kn400 + pre400 +", CUR), FE_N)
b <- coef(m6); V <- vcov(m6); dd <- b["hid400"] - b["kn400"]; sdd <- sqrt(V["hid400", "hid400"] + V["kn400", "kn400"] - 2 * V["hid400", "kn400"])
T6 <- as.data.table(coeftable(m6), keep.rownames = "term")[term %in% c("hid400", "kn400", "pre400")]; setnames(T6, c("term", "estimate", "se", "t", "p"))
T6 <- T6[, .(model = "M6 within 400 m (pooled)", sample = "All residential sales",
             kind = c(hid400 = "Hidden (no current inventory)", kn400 = "Known (on a current inventory)", pre400 = "Pre-1960 hazardous trade")[term], distance = "0-400 m",
             pct = round(100 * (exp(estimate) - 1), 2), lo = round(100 * (exp(estimate - 1.96 * se) - 1), 2), hi = round(100 * (exp(estimate + 1.96 * se) - 1), 2),
             p = signif(p, 3), estimate = round(estimate, 4), se = round(se, 4), n = nobs(m6))]
RES <- rbind(RES, T6, data.table(model = "M6 within 400 m (pooled)", sample = "All residential sales", kind = "Hidden minus known", distance = "0-400 m",
                                 pct = round(100 * dd, 2), lo = round(100 * (dd - 1.96 * sdd), 2), hi = round(100 * (dd + 1.96 * sdd), 2),
                                 p = signif(2 * pnorm(-abs(dd / sdd)), 3), estimate = round(dd, 4), se = round(sdd, 4), n = nobs(m6)))
# ---------------------------------------------------------------- sample description (aggregates only)
SMP <- rbindlist(lapply(c("hidden", "known", "pre1960"), function(k) M[, .(sales = .N, median_price = as.numeric(median(price)), median_area = as.numeric(median(area)),
                                                                          median_year_built = as.numeric(median(yb)), pct_condo = round(100 * mean(type == "Condominium"), 1)),
                                                                       by = .(distance = get(paste0("b_", k)))][, kind := k]))
setcolorder(SMP, "kind"); SMP <- SMP[order(kind, distance)]
fwrite(RES, file.path(O, "hedonic_models.csv")); fwrite(SMP, file.path(O, "hedonic_sample.csv")); fwrite(RES, file.path(A, "hedonic_models.csv")); fwrite(SMP, file.path(A, "hedonic_sample.csv"))
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
writeLines(c("# Hedonic model: Denver residential sales and historical hazardous sites", "",
             sprintf("%s arm's-length residential sales, %d-%d. Effects are percentage differences in sale price (95%% CI) relative to sales more than 800 m from any site of that kind.",
                     format(nrow(M), big.mark = ","), min(M$year), max(M$year)), "", "## Models", "", kab(RES[kind != "Present-day control"]), "",
             "## Present-day controls (M2)", "", kab(RES[model == "M2 + present-day hazards" & sample == "All residential sales" & kind == "Present-day control"]), "",
             "## Sales by distance band", "", kab(SMP)), file.path(O, "hedonic_summary.md"))
print(RES[kind != "Present-day control", .(model = substr(model, 1, 22), sample = substr(sample, 1, 12), kind = substr(kind, 1, 18), distance, pct, lo, hi, p, n)])
message("wrote ", O)
