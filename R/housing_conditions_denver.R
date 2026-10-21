# Housing conditions and evictions by landlord: Denver 311 requests linked to parcels, and Eviction Lab tract filings.
#
#   Rscript R/fetch_denver_311.R  and  Rscript R/fetch_landlord_data.R   (inputs)
#   Rscript R/ownership_denver.R                                       (owner groups: work/property/parcel_owner_groups_private.csv)
#   Rscript R/housing_conditions_denver.R
#
# 1. Requests. 311 requests routed to Public Health & Environment about conditions inside homes (mold, no heat or water, rats, mice,
#    roaches, bed bugs, water damage, sewage) and to Community Planning & Development about the outside of a property (trash, weeds,
#    outdoor storage, inoperable vehicles, dilapidated fences, neglected or vacant buildings, illegal occupancy). Snow-on-sidewalk
#    requests are left out (weather, not the building). The classification is printed with the most common request types in each class.
# 2. Linking. A request is joined to a building by house number, street name and ZIP (the Assessor's situs address); failing that, by
#    the street address alone when it is unique in Denver (no ZIP given), by the nearest house number on the same street and side
#    (within 10, or 100 for buildings of 20+ units, which often carry several numbers), or by coordinates (nearest building within 60 m,
#    or nearest building of 20+ units within 150 m). A building is all parcels sharing a situs street address (a condominium building
#    is one building). Its owner is the owner family holding most of its rental units.
# 3. Models (rental buildings; Poisson with tract fixed effects and standard errors clustered by tract): requests on the owner's
#    portfolio size in Denver (log rental units, and size bands), with the building's units (and their square), type, decade built, owner
#    type and out-of-state mailing address (An et al. 2024, JAPA). Portfolio size is measured three ways: by owner name (S3), by owner
#    family (S4: names sharing a mailing address) and, if the business registry was linked, by registry group (S5). Also: the share
#    of buildings with a complaint held by the largest 1% of owners (Hangen & O'Brien 2025), and rates by HOLC grade and near
#    historical sites. A request is a report, not a verified violation: tenants' willingness to call differs between places and owners.
# 4. Evictions. Eviction Lab tract filings 2000-2018 (court records bought from vendors), averaged over the latest five years in which
#    nearly every tract has a count and which the Lab judged complete for Denver County (2012-2016), against the share of rental units held by large owners today (a cross-section 6+ years apart).
# Outputs (aggregates only): data/results/housing_conditions/*.csv, summary.md; app/data/conditions_*.csv.
for (p in c("data.table", "sf", "RANN", "sandwich", "lmtest")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(data.table); library(sf) })
sf_use_s2(FALSE); UTM <- 26913; D <- "work/property"; A <- "app/data"; O <- "data/results/housing_conditions"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
num <- function(x) suppressWarnings(as.numeric(x))
G <- file.path(D, "parcel_owner_groups_private.csv"); if (!file.exists(G)) stop("run Rscript R/ownership_denver.R first")
F311 <- Sys.glob("work/denver311/311_*.csv"); if (!length(F311)) stop("run Rscript R/fetch_denver_311.R first")
# ---------------------------------------------------------------- buildings and their owners
P <- fread(file.path(D, "owners.csv"), colClasses = "character")[!duplicated(SCHEDNUM)]
P <- merge(P[, .(SCHEDNUM, SITUS_ADDRESS_LINE1, SITUS_ZIP, SITUS_X_COORD, SITUS_Y_COORD, RES_ORIG_YEAR_BUILT)], fread(G, colClasses = c(SCHEDNUM = "character")), by = "SCHEDNUM")
addr_key <- function(x) { x <- toupper(trimws(ifelse(is.na(x), "", x))); x <- gsub("[.,#]", " ", x); x <- gsub("\\bSAINT\\b", "ST", x); x <- sub("\\b(UNIT|APT|STE|SUITE)\\b.*$", "", x)
  x <- gsub("\\b(N|S|E|W|NORTH|SOUTH|EAST|WEST)\\b", " ", x)
  x <- gsub("\\b(ST|STREET|AVE|AVENUE|AV|BLVD|BOULEVARD|PL|PLACE|DR|DRIVE|CT|COURT|WAY|LN|LANE|RD|ROAD|PKWY|PARKWAY|CIR|CIRCLE|TER|TERRACE)\\b", " ", x)
  w <- strsplit(trimws(gsub("\\s+", " ", x)), " "); vapply(w, function(t) if (length(t) >= 2 && grepl("^[0-9]+", t[1])) paste(head(t, 2), collapse = " ") else "", "") }
z5 <- function(z) substr(gsub("\\D", "", ifelse(is.na(z), "", z)), 1, 5)
P[, bkey := fifelse(addr_key(SITUS_ADDRESS_LINE1) == "", paste0("parcel_", SCHEDNUM), paste(addr_key(SITUS_ADDRESS_LINE1), z5(SITUS_ZIP)))]
P[, `:=`(x = num(SITUS_X_COORD), y = num(SITUS_Y_COORD))]
fam_tot <- function(g) P[, .(scale = sum(rental_units)), by = g]
if (!"g_registry" %in% names(P)) P[, g_registry := g_family]
for (g in c("g_name", "g_family", "g_registry")) { s <- fam_tot(g); setnames(s, c(g, paste0("scale_", g))); P <- merge(P, s, by = g, all.x = TRUE) }
B <- P[, { w <- if (sum(rental_units) > 0) rental_units else units; k <- which.max(w)
  .(units = sum(units), rental_units = sum(rental_units), parcels = .N, type = type[which.max(units)], owner_type = owner_type[k], out_of_state = out_of_state[k],
    owner_occ_any = any(owner_occ), scale_g_name = scale_g_name[k], scale_g_family = scale_g_family[k], g_family = g_family[k],
    scale_g_registry = scale_g_registry[k],
    built = suppressWarnings(median(num(RES_ORIG_YEAR_BUILT), na.rm = TRUE)), x = mean(x, na.rm = TRUE), y = mean(y, na.rm = TRUE)) }, by = bkey]
B <- B[!is.na(x) & x > 0]
bxy <- st_coordinates(st_transform(st_as_sf(B[, .(x, y)], coords = c("x", "y"), crs = 2877), UTM)); B[, `:=`(ux = bxy[, 1], uy = bxy[, 2])]
message(nrow(B), " residential buildings; ", B[rental_units > 0, .N], " with rental units")
# ---------------------------------------------------------------- requests
R <- rbindlist(lapply(F311, fread, colClasses = "character"), fill = TRUE)
for (cc in c("Case_Summary", "Type", "Topic", "Agency", "Incident_Address_1", "Incident_Zip_Code", "Longitude", "Latitude")) if (!cc %in% names(R)) R[, (cc) := NA_character_]
R[, txt := toupper(paste(Case_Summary, Type, Topic))]; R[, ag := toupper(Agency)]
HOUSING_RX <- "MOLD|NO HEAT|NO WATER|NO HOT WATER|\\bRATS?\\b|MICE|RODENT|ROACH|BED ?BUGS?|PEST|INSECT|WATER DAMAGE|STANDING WATER|SEWAGE|SEWER BACK|PLUMBING|HOUSING|HABITAB|UNSANITARY|RESIDENTIAL HEALTH|MULTIPLE ISSUES|PLACARD|LEAD PAINT|SECONDHAND|VAPE SMOKE"
EXTERIOR_RX <- "TRASH IN YARD|WEEDS|VEGETATION|OUTDOOR STORAGE|INOPERABLE|PARKING ON LAWN|DILAPIDATED|NEGLECT|VACANT|ILLEGAL OCCUPANCY|UNRELATED OCCUPANTS|OVERFLOWING PRIVATE DUMPSTER|ACCESSORY STRUCTURE|\\bYARD\\b|^TRASH|GRAFFITI"
R[, class := fcase(grepl("HEALTH|ENVIRONMENT", ag) & grepl(HOUSING_RX, txt) & !grepl("FOOD|RESTAURANT|NOISE|ANIMAL|PET\\b|DOG|CAT\\b", txt), "Conditions inside the home",
                   grepl("PLANNING|NEIGHBORHOOD", ag) & grepl(EXTERIOR_RX, txt) & !grepl("SNOW|SIDEWALK", txt), "Outside of the property", default = NA_character_)]
CLS <- R[, .N, by = .(class, agency = Agency, request = Case_Summary)][order(class, -N)]
CLS_TOP <- CLS[, head(.SD, 15), by = class]; print(CLS_TOP, nrows = 60)
R <- R[!is.na(class)]
R[, `:=`(akey = addr_key(Incident_Address_1), zip = z5(Incident_Zip_Code), lon = num(Longitude), lat = num(Latitude))]
R[, bkey := fifelse(akey != "", paste(akey, zip), NA_character_)]
R[, how := fifelse(bkey %in% B$bkey, "address", NA_character_)]
# address without a ZIP: the street address if it is unique in Denver
BK <- B[!grepl("^parcel_", bkey), .(bkey, akey = sub(" [0-9]{5}$|\\s+$", "", bkey))]; uk <- BK[, .N, by = akey][N == 1, akey]
R[is.na(how) & akey != "" & zip == "" & akey %in% uk, `:=`(bkey = BK$bkey[match(akey, BK$akey)], how = "address (no ZIP; unique street address)")]
# a building with several street numbers on one parcel: the nearest house number on the same street and side (same parity), within 10
# numbers, or 100 for a building of 20+ units (apartment complexes)
BK[, `:=`(num = as.integer(sub(" .*", "", akey)), street = sub("^[0-9]+ ", "", akey), zip = sub(".* ", "", bkey))]; BK[, par := num %% 2L]
ri <- R[is.na(how) & akey != "", which = TRUE]
if (length(ri)) { Q <- R[ri, .(i = ri, num = as.integer(sub(" .*", "", akey)), street = sub("^[0-9]+ ", "", akey), zip)][!is.na(num)][, par := num %% 2L]
  setkey(BK, street, zip, par, num); m <- BK[Q, on = .(street, zip, par, num), roll = "nearest", .(i, bkey, bnum = x.num, qnum = i.num)]
  m <- merge(m[!is.na(bkey)], B[, .(bkey, bunits = units)], by = "bkey"); m <- m[abs(bnum - qnum) <= fifelse(bunits >= 20, 100, 10)]
  R[m$i, `:=`(bkey = m$bkey, how = "nearest house number on the same street and side (within 10; 100 for 20+ units)")] }
# coordinates: nearest building within 60 m, or the nearest building of 20+ units within 150 m (apartment complexes)
nn_i <- R[is.na(how) & !is.na(lon) & !is.na(lat) & lon < -100 & lon > -106, which = TRUE]
if (length(nn_i)) { rxy <- st_coordinates(st_transform(st_as_sf(R[nn_i, .(lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM))
  nn <- RANN::nn2(as.matrix(B[, .(ux, uy)]), rxy, k = 1); hit <- nn$nn.dists[, 1] <= 60
  R[nn_i[hit], `:=`(bkey = B$bkey[nn$nn.idx[hit, 1]], how = "coordinates (nearest building within 60 m)")]
  BB <- B[units >= 20]; nn_j <- nn_i[!hit]
  if (length(nn_j) && nrow(BB)) { nb <- RANN::nn2(as.matrix(BB[, .(ux, uy)]), rxy[!hit, , drop = FALSE], k = 1); h2 <- nb$nn.dists[, 1] <= 150
    R[nn_j[h2], `:=`(bkey = BB$bkey[nb$nn.idx[h2, 1]], how = "coordinates (building of 20+ units within 150 m)")] } }
R[is.na(how), how := fifelse(akey == "" & (is.na(lon) | lon > -100), "no usable address or coordinates", "not a residential building in the parcel file")]
R[!grepl("^address|^nearest|^coordinates", how), bkey := NA_character_]
LINK <- R[, .N, by = .(class, how)][, pct := round(100 * N / sum(N), 1), by = class][order(class, -N)]; print(LINK)
yrs <- sort(unique(num(R$year))); NY <- length(yrs)
CNT <- dcast(R[!is.na(bkey), .N, by = .(bkey, class)], bkey ~ class, value.var = "N", fill = 0)
setnames(CNT, c("Conditions inside the home", "Outside of the property"), c("n_inside", "n_outside"), skip_absent = TRUE)
B <- merge(B, CNT, by = "bkey", all.x = TRUE); for (cc in c("n_inside", "n_outside")) { if (!cc %in% names(B)) B[, (cc) := 0]; set(B, which(is.na(B[[cc]])), cc, 0) }
# ---------------------------------------------------------------- where buildings are
pts <- st_as_sf(B[, .(ux, uy)], coords = c("ux", "uy"), crs = UTM)
TR <- st_transform(st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE), UTM); TR <- TR[substr(TR$GEOID, 1, 5) == "08031", ]
B[, GEOID := TR$GEOID[vapply(st_within(pts, TR), function(i) if (length(i)) i[1] else NA_integer_, 1L)]]
HOLC <- st_make_valid(st_transform(st_read(file.path(A, "holc_denver.geojson"), quiet = TRUE), UTM)); HOLC <- HOLC[HOLC$grade %in% c("A", "B", "C", "D"), "grade"]
B[, holc := { w <- st_within(pts, HOLC); vapply(w, function(i) if (length(i)) HOLC$grade[i[1]] else "Not graded", "") }]
S <- fread(file.path(A, "sites.csv"))[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx") & !is.na(lat) & !is.na(lon)][, .(kind = fifelse(radar == "Not on any list", "hidden", "known"), lat, lon)]
H <- fread(file.path(A, "historical_sites.csv"))[fe_hazard %in% c(TRUE, "True") & precision != "town" & !is.na(lat) & town == "DENVER"][, .(kind = "pre1960", lat, lon)]
SITES <- st_transform(st_as_sf(rbind(S, H), coords = c("lon", "lat"), crs = 4326), UTM)
for (k in c("hidden", "known", "pre1960")) B[, (paste0("near_", k)) := lengths(st_is_within_distance(pts, SITES[SITES$kind == k, ], 400)) > 0]
# ---------------------------------------------------------------- rates
band <- function(u) factor(fcase(u <= 1, "1 unit", u <= 4, "2-4 units", u <= 19, "5-19 units", u <= 99, "20-99 units", u <= 999, "100-999 units", default = "1,000+ units"),
                           levels = c("1 unit", "2-4 units", "5-19 units", "20-99 units", "100-999 units", "1,000+ units"))
RB <- B[rental_units > 0 & !owner_type %in% c("Unknown (no name recorded)")]
RB[, `:=`(size = band(scale_g_family), any_inside = n_inside > 0, any_outside = n_outside > 0)]
rate <- function(d) d[, .(buildings = .N, rental_units = sum(rental_units),
                          inside_per_100_units_yr = round(100 * sum(n_inside) / sum(rental_units) / NY, 2), outside_per_100_buildings_yr = round(100 * sum(n_outside) / .N / NY, 2),
                          pct_buildings_inside_request = round(100 * mean(any_inside), 1), pct_buildings_outside_request = round(100 * mean(any_outside), 1))]
RATES <- rbindlist(list(
  RB[, rate(.SD), by = .(value = as.character(size))][, group := "Owner family size (rental units in Denver)"],
  RB[, rate(.SD), by = .(value = owner_type)][, group := "Owner type"],
  RB[, rate(.SD), by = .(value = fifelse(out_of_state, "Mailing address out of state", "Mailing address in Colorado"))][, group := "Owner location"],
  RB[, rate(.SD), by = .(value = type)][, group := "Building type"],
  RB[, rate(.SD), by = .(value = holc)][, group := "1938 HOLC grade"],
  RB[near_hidden == TRUE, rate(.SD)][, `:=`(group = "Historical sites", value = "Within 400 m of a hidden site")],
  RB[near_known == TRUE, rate(.SD)][, `:=`(group = "Historical sites", value = "Within 400 m of a known site")],
  RB[near_pre1960 == TRUE, rate(.SD)][, `:=`(group = "Historical sites", value = "Within 400 m of a pre-1960 hazardous trade")],
  RB[!near_hidden & !near_known & !near_pre1960, rate(.SD)][, `:=`(group = "Historical sites", value = "More than 400 m from any")],
  RB[, rate(.SD)][, `:=`(group = "All rental buildings", value = "all")]), fill = TRUE)
setcolorder(RATES, c("group", "value")); print(RATES)
# outcome concentration: the largest 1% of owner families (by rental units)
fam <- RB[, .(units = sum(rental_units), buildings = .N, inside = sum(any_inside), outside = sum(any_outside), n_in = sum(n_inside)), by = g_family][order(-units)]
top <- head(fam, ceiling(nrow(fam) / 100))
OUTC <- data.table(owners = "Largest 1% of owner families", pct_rental_units = round(100 * sum(top$units) / sum(fam$units), 1), pct_rental_buildings = round(100 * sum(top$buildings) / sum(fam$buildings), 1),
                   pct_buildings_with_inside_request = round(100 * sum(top$inside) / max(1, sum(fam$inside)), 1), pct_inside_requests = round(100 * sum(top$n_in) / max(1, sum(fam$n_in)), 1),
                   pct_buildings_with_outside_request = round(100 * sum(top$outside) / max(1, sum(fam$outside)), 1))
print(OUTC)
# ---------------------------------------------------------------- models
RB[, `:=`(lunits = log(units), lunits2 = log(units)^2, decade = factor(fifelse(is.na(built) | built < 1880, "unknown", as.character(pmin(2020, 10 * (built %/% 10))))),
          ftype = factor(type), fown = relevel(factor(owner_type), ref = "Individual"), oos = as.numeric(out_of_state), tract = factor(GEOID))]
MD <- RB[!is.na(GEOID)]
fitp <- function(y, scale_col, label, bands = FALSE) { d <- copy(MD); d <- d[!is.na(get(scale_col))]
  if (bands) d[, sc := band(get(scale_col))] else d[, sc := log(pmax(get(scale_col), 1))]
  f <- as.formula(paste(y, "~ sc + lunits + lunits2 + ftype + decade + fown + oos + tract"))
  m <- glm(f, data = d, family = poisson()); V <- sandwich::vcovCL(m, cluster = ~tract, type = "HC0"); ct <- lmtest::coeftest(m, vcov. = V)
  rn <- grep("^sc", rownames(ct), value = TRUE)
  data.table(outcome = y, portfolio = label, term = if (bands) sub("^sc", "", rn) else "per doubling of the owner's Denver rental units",
             irr = round(exp(ct[rn, 1] * if (bands) 1 else log(2)), 3), lo = round(exp((ct[rn, 1] - 1.96 * ct[rn, 2]) * if (bands) 1 else log(2)), 3),
             hi = round(exp((ct[rn, 1] + 1.96 * ct[rn, 2]) * if (bands) 1 else log(2)), 3), p = signif(ct[rn, 4], 3), buildings = nobs(m)) }
SC <- c(g_name = "S3 by owner name", g_family = "S4 by owner family", g_registry = "S5 by registry group")
SC <- SC[paste0("scale_", names(SC)) %in% names(MD) & vapply(paste0("scale_", names(SC)), function(cc) cc %in% names(MD) && any(!is.na(MD[[cc]])), TRUE)]
MODELS <- rbindlist(c(lapply(c("n_inside", "n_outside"), function(y) rbindlist(lapply(names(SC), function(g) fitp(y, paste0("scale_", g), SC[[g]])))),
                      lapply(c("n_inside", "n_outside"), function(y) fitp(y, "scale_g_family", "S4 by owner family (size bands vs 1 unit)", bands = TRUE))))
MODELS[, outcome := c(n_inside = "Requests about conditions inside the home", n_outside = "Requests about the outside of the property")[outcome]]
print(MODELS)
# ---------------------------------------------------------------- evictions (Eviction Lab tracts)
EVF <- "work/evictionlab/tract_proprietary_valid_2000_2018_CO.csv"; EVT <- NULL; EVM <- NULL
if (file.exists(EVF)) {
  E <- fread(EVF, colClasses = "character"); nm <- names(E); message("Eviction Lab columns: ", paste(nm, collapse = ", "))
  idc <- nm[grepl("^(id|geoid|fips|GEOID)$", nm, ignore.case = TRUE)][1]; yc <- nm[tolower(nm) == "year"][1]
  fc <- nm[grepl("^filings?$", nm, ignore.case = TRUE)][1]; jc <- nm[grepl("^judge?ments?$", nm, ignore.case = TRUE)][1]
  rc <- nm[grepl("renter|renting", nm, ignore.case = TRUE)][1]
  E[, GEOID := sprintf("%011.0f", num(get(idc)))]; E <- E[substr(GEOID, 1, 5) == "08031"]
  E[, `:=`(year = num(get(yc)), filings = num(get(fc)), judgments = if (!is.na(jc)) num(get(jc)) else NA_real_, renters = if (!is.na(rc)) num(get(rc)) else NA_real_)]
  frc <- nm[tolower(nm) == "filing_rate"][1]
  if (all(is.na(E$renters)) && !is.na(frc)) E[, renters := fifelse(num(get(frc)) > 0, 100 * filings / num(get(frc)), NA_real_)]   # renter households implied by the Lab's rate
  # latest five years in which nearly every Denver tract has a count, and not past the last year the Lab judged complete for the county
  cov <- E[, .(ok = mean(!is.na(filings))), by = year][ok >= 0.9, year]
  cfile <- "work/evictionlab/county_proprietary_valid_2000_2018_CO.csv"
  cmax <- if (file.exists(cfile)) max(num(fread(cfile, colClasses = "character")[num(cofips) == 8031 & filings != "", year])) else Inf
  y1 <- max(cov[cov <= cmax]); E5 <- E[year > y1 - 5 & year <= y1 & !is.na(filings)]
  EVT <- E5[, .(years = .N, filings_per_year = mean(filings), judgments_per_year = mean(judgments), renter_households = mean(renters)), by = GEOID]
  EVT[, filing_rate := 100 * filings_per_year / renter_households]
  OT <- if (file.exists("data/results/ownership/by_tract.csv")) fread("data/results/ownership/by_tract.csv", colClasses = c(GEOID = "character")) else NULL
  if (!is.null(OT)) {
    EVT <- merge(EVT, OT, by = "GEOID")
    EVT[, `:=`(any_hidden = as.numeric(hidden_1965_92 > 0), any_known = as.numeric(known_1965_92 > 0))]
    d <- EVT[!is.na(filing_rate) & is.finite(filing_rate) & renter_households >= 50 & !is.na(p_black)]
    em <- function(xv, lab) { f <- as.formula(paste("filing_rate ~", xv, "+ p_black + p_hisp + p_pov + any_hidden + any_known")); m <- lm(f, data = d, weights = renter_households)
      ct <- lmtest::coeftest(m, vcov. = sandwich::vcovHC(m, type = "HC1"))
      data.table(model = lab, term = rownames(ct)[-1], estimate = round(ct[-1, 1], 3), se = round(ct[-1, 2], 3), p = signif(ct[-1, 4], 3), tracts = nobs(m)) }
    EVM <- rbind(em("pct_rental_owner_100plus", "Filing rate (% of renter households per year) on share of rental units held by owners of 100+ units"),
                 em("pct_rental_company", "Filing rate on share of rental units held by companies"),
                 em("pct_rental_out_of_state", "Filing rate on share of rental units with an out-of-state owner"))
    EVT[, large_owner_tercile := cut(pct_rental_owner_100plus, quantile(pct_rental_owner_100plus, c(0, 1/3, 2/3, 1), na.rm = TRUE), include.lowest = TRUE, labels = c("lowest third", "middle third", "highest third"))]
    EVS <- EVT[!is.na(filing_rate) & is.finite(filing_rate), .(tracts = .N, renter_households = round(sum(renter_households)), filings_per_year = round(sum(filings_per_year)),
                                                                filing_rate = round(100 * sum(filings_per_year) / sum(renter_households), 2)), by = .(large_owner_tercile)][order(large_owner_tercile)]
    EVS[, years := sprintf("%d-%d", y1 - 4, y1)]; print(EVS); print(EVM)
  }
} else message("Eviction Lab tract file missing: run Rscript R/fetch_landlord_data.R (tract results skipped)")
EVCF <- "work/evictionlab/county_proprietary_valid_2000_2018_CO.csv"; EVC <- NULL
if (file.exists(EVCF)) { E2 <- fread(EVCF, colClasses = "character")
  EVC <- E2[num(cofips) == 8031, .(year = num(year), filings = num(filings), filing_rate = num(filing_rate), judgments = num(judgements), judgment_rate = num(judgement_rate))][order(year)]
  message("Denver County eviction filings (Eviction Lab):"); print(EVC) }
# ---------------------------------------------------------------- write (aggregates only)
out <- list(classes = CLS_TOP, linking = LINK, rates = RATES, outcome_concentration = OUTC, models = MODELS)
if (!is.null(EVM)) { out$evictions_by_large_owner_share <- EVS; out$evictions_models <- EVM }
if (!is.null(EVC)) out$evictions_denver_county <- EVC
for (k in names(out)) { fwrite(out[[k]], file.path(O, paste0(k, ".csv"))); fwrite(out[[k]], file.path(A, paste0("conditions_", k, ".csv"))) }
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
writeLines(c("# Housing conditions and evictions by landlord, Denver", "", sprintf("311 requests %d-%d (%d years); aggregates only.", min(yrs), max(yrs), NY), "",
             "## Request classes (most common request types)", "", kab(CLS_TOP), "", "## Linking requests to buildings", "", kab(LINK), "",
             "## Rates", "", kab(RATES), "", "## Largest 1% of owners", "", kab(OUTC), "", "## Poisson models (incidence-rate ratios, tract fixed effects)", "", kab(MODELS),
             if (!is.null(EVM)) c("", "## Evictions (Eviction Lab)", "", kab(EVS), "", kab(EVM)), if (!is.null(EVC)) c("", "## Denver County eviction filings (Eviction Lab)", "", kab(EVC))), file.path(O, "summary.md"))
message("wrote ", O)
