# What became of the sites? Current parcel use of every historical hazardous site in the City and County of Denver.
#   Rscript R/site_fate.R
# Source: City and County of Denver assessor parcels, open-data feature service ODC_PROP_PARCELS_A (layer 245; no key). For every site
# point one REST query returns the parcel it falls in with the assessor's property class (D_CLASS_CN, e.g. "SINGLE FAMILY-RANCH",
# "INDUSTRIAL-WAREHOUSE", "EXEMPT-SCHOOL"), the current zone district (ZONE_ID; ZONE_10 is the same code with hyphens, not the former code), dwelling units and the year the present building was
# built. Responses are cached in work/site_fate/parcels_by_point.csv so a rerun only fetches new points.
# Every site (1965-1992 manufacturers' directory, hazardous sectors) and every street-level pre-1960 hazardous trade in Denver County is
# scored: broad use today; whether the current building post-dates the last directory listing (redeveloped); whether the zone is still
# industrial. Outputs (data/results/site_fate/, copies in app/data/):
#   site_fate_denver.csv          one row per 1965-92 site: last directory year, regulatory status, parcel class, zone, year built, use today
#   site_fate_denver_pre1960.csv  the same for pre-1960 business-directory trades
#   site_fate_summary.csv         use today by decade the site was last listed (counts and %), both series
#   site_fate_parcel_match.csv    how the parcel was chosen (same address / same street and side / same street / nearest) and the
#                                 agreement rate between the chosen parcel's situs address and the site's address
#   site_fate_sensitive.csv       1965-92 sites now under residential, school, park or health use, with no cleanup record ("hidden conversions")
# This is the Frickel & Elliott (2008) land-use-conversion question for the whole inventory rather than a sample; Sanborn sheets and the
# Denver Public Library's reverse street directories are the archival check for a sample of these.
suppressPackageStartupMessages({ library(sf); library(data.table); library(jsonlite) })
sf_use_s2(FALSE); W <- "work/site_fate"; O <- "data/results/site_fate"; A <- "app/data"; for (d in c(W, O)) dir.create(d, showWarnings = FALSE, recursive = TRUE)
SVC <- "https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/arcgis/rest/services/ODC_PROP_PARCELS_A/FeatureServer/245/query"
FLD <- c("SCHEDNUM", "PROP_CLASS", "D_CLASS", "D_CLASS_CN", "ZONE_ID", "TOT_UNITS", "RES_ORIG_YEAR_BUILT", "COM_ORIG_YEAR_BUILT", "SITUS_ADDRESS_LINE1", "OWNER_NAME", "LAND_AREA")
# ---- 1. sites and pre-1960 trades in Denver County
sites <- fread(file.path(A, "sites.csv"), colClasses = c(GEOID = "character"))[!is.na(lat) & fe_hazard %in% c(TRUE, "True")]
local({ m <- which(is.na(sites$GEOID) | !nzchar(sites$GEOID)); if (!length(m)) return()          # points on a tract edge: nearest tract within 100 m
  TRc <- st_transform(st_read(file.path(A, "enviroscreen_tracts.geojson"), quiet = TRUE), 26913); p <- st_transform(st_as_sf(sites[m, .(lon, lat)], coords = c("lon", "lat"), crs = 4326), 26913)
  k <- st_nearest_feature(p, TRc); d <- as.numeric(st_distance(p, TRc[k, ], by_element = TRUE))
  sites[m[d <= 100], GEOID := as.character(TRc$GEOID[k[d <= 100]])] })
sites <- sites[substr(GEOID, 1, 5) == "08031"]
hist <- fread(file.path(A, "historical_sites.csv"), colClasses = c(GEOID = "character"))[!is.na(lat) & precision != "town" & fe_hazard %in% c(TRUE, "True") & toupper(town) == "DENVER"]
PTS <- unique(rbind(sites[, .(lon, lat)], hist[, .(lon, lat)]))[, pkey := sprintf("%.6f,%.6f", lon, lat)]
message(nrow(sites), " manufacturers' sites, ", nrow(hist), " pre-1960 trades, ", nrow(PTS), " distinct points")
# ---- 2. candidate parcels for each point (cached). Sites were geocoded to street addresses, so most points sit on the street centreline
#          or the kerb rather than inside the lot: the query asks for every parcel within SEARCH_M metres and caches all of them
#          (cand_rank = 1 nearest). The nearest parcel is on the wrong side of the street about half the time (a centreline point is as
#          close to the lots opposite as to the right one), so the parcel is chosen in step 2b by the site's own address, not by distance.
SEARCH_M <- 40; FLD2 <- c("ZONE_10", "SITUS_ADDR_NBR", "SITUS_STR_NAME")
f_cache <- file.path(W, "parcels_by_point.csv"); if (file.exists(f_cache) && !"dist_m" %in% names(fread(f_cache, nrows = 1))) file.rename(f_cache, file.path(W, "parcels_by_point_v1.csv"))
if (file.exists(f_cache) && !"cand_rank" %in% names(fread(f_cache, nrows = 1))) {   # v2 cache kept only the nearest parcel per point: every point is fetched again
  file.rename(f_cache, file.path(W, "parcels_by_point_v2.csv")); message("cache ", f_cache, " predates the address-based parcel choice (one parcel per point); set aside as parcels_by_point_v2.csv and all points will be fetched again") }
PC <- if (file.exists(f_cache)) fread(f_cache, colClasses = "character") else data.table(pkey = character())
todo <- PTS[!pkey %in% PC$pkey]
if (nrow(todo)) {
  message("querying the Denver parcel service for ", nrow(todo), " points (about ", round(nrow(todo) * 0.5 / 60), " min)")
  one <- function(lon, lat, pkey) {
    u <- paste0(SVC, "?geometry=", lon, "%2C", lat, "&geometryType=esriGeometryPoint&inSR=4326&spatialRel=esriSpatialRelIntersects&distance=", SEARCH_M, "&units=esriSRUnit_Meter",
                "&outFields=", paste(c(FLD, FLD2), collapse = "%2C"), "&returnGeometry=true&outSR=4326&f=geojson")
    g <- tryCatch(suppressWarnings(st_read(u, quiet = TRUE)), error = function(e) NULL)
    if (is.null(g) || !nrow(g)) return(data.table(pkey = pkey, SCHEDNUM = NA_character_, dist_m = NA_real_))
    g <- st_make_valid(g); d <- as.numeric(st_distance(st_transform(st_sfc(st_point(c(lon, lat)), crs = 4326), 26913), st_transform(g, 26913)))
    a <- as.data.table(st_drop_geometry(g)); a$dist_m <- round(d, 1); a <- a[order(dist_m)]; a$cand_rank <- seq_len(nrow(a)); a$pkey <- pkey; a[] }
  new <- rbindlist(lapply(seq_len(nrow(todo)), function(i) { if (i %% 100 == 0) message("  ", i, "/", nrow(todo)); one(todo$lon[i], todo$lat[i], todo$pkey[i]) }), fill = TRUE)
  for (k in setdiff(c(FLD, FLD2, "dist_m", "cand_rank"), names(new))) new[[k]] <- NA
  PC <- rbind(PC, new[, c("pkey", FLD, FLD2, "dist_m", "cand_rank"), with = FALSE][, lapply(.SD, as.character)], fill = TRUE); fwrite(PC, f_cache) }
PC <- copy(unique(PC, by = c("pkey", "SCHEDNUM")))
for (k in c("TOT_UNITS", "RES_ORIG_YEAR_BUILT", "COM_ORIG_YEAR_BUILT", "LAND_AREA", "dist_m", "cand_rank")) PC[[k]] <- suppressWarnings(as.numeric(PC[[k]]))
PC[, year_built := pmax(RES_ORIG_YEAR_BUILT, COM_ORIG_YEAR_BUILT, na.rm = TRUE)]; PC[!is.finite(year_built) | year_built < 1800, year_built := NA]
message(uniqueN(PC[!is.na(SCHEDNUM), pkey]), " of ", uniqueN(PC$pkey), " points have an assessor parcel within ", SEARCH_M, " m (",
        round(mean(PC[!is.na(SCHEDNUM), .N, by = pkey]$N), 1), " candidate parcels per point on average)")
# ---- 2b. which of the candidate parcels is the site? House number, direction, street name and street type of the site's address and
#          of each parcel's situs address are each spelled one way (as in R/housing_conditions_denver.R; the assessor writes the N/S/E/W
#          the directories usually omit, so a direction missing on one side is no conflict). Rules, in order:
#          1 same address: situs house number and street equal the site's;  2 same street and side (odd/even), nearest house number;
#          3 same street, nearest parcel;  4 nearest parcel of any street (the former rule, and the only one for an address without a
#          number). The rule used is written to parcel_match; rule 1's share among numbered addresses is the agreement rate reported below.
DIRW <- c(NORTH = "N", SOUTH = "S", EAST = "E", WEST = "W", N = "N", S = "S", E = "E", W = "W")
TYPW <- c(STREET = "ST", ST = "ST", AVENUE = "AVE", AVE = "AVE", AV = "AVE", BOULEVARD = "BLVD", BLVD = "BLVD", PLACE = "PL", PL = "PL", DRIVE = "DR", DR = "DR",
          COURT = "CT", CT = "CT", WAY = "WAY", LANE = "LN", LN = "LN", ROAD = "RD", RD = "RD", PARKWAY = "PKWY", PKWY = "PKWY", CIRCLE = "CIR", CIR = "CIR",
          TERRACE = "TER", TER = "TER", HIGHWAY = "HWY", HWY = "HWY", TRAIL = "TRL", TRL = "TRL")
addr_parts <- function(x) { x <- toupper(trimws(ifelse(is.na(x), "", x))); x <- sub("\\s*(#|\\b(UNIT|APT|STE|SUITE|BLDG|RM)\\b).*$", "", x)
  x <- gsub("[.,]", " ", x); x <- gsub("\\bSAINT\\b", "ST", x); w <- strsplit(trimws(gsub("\\s+", " ", x)), " ")
  p <- vapply(w, function(t) { if (!length(t) || !nzchar(t[1])) return(c("", "", "", ""))
    n <- ""; if (grepl("^[0-9]", t[1])) { n <- sub("[^0-9].*$", "", t[1]); t <- t[-1] }       # "4300A" -> 4300; an address without a number keeps n = ""
    d <- ""; if (length(t) >= 2 && t[1] %in% names(DIRW)) { d <- DIRW[[t[1]]]; t <- t[-1] }
    j <- which(t %in% names(TYPW)); j <- j[j >= 2]; ty <- ""; if (length(j)) { j <- max(j); ty <- TYPW[[t[j]]]; t <- t[seq_len(j - 1)] }   # "ST PAUL ST": name ST PAUL
    c(n, d, paste(t, collapse = " "), ty) }, character(4))
  data.table(num = p[1, ], dir = p[2, ], sname = p[3, ], stype = p[4, ]) }
PM <- c("same address", "same street and side, nearest number", "same street, nearest parcel", "nearest parcel", "no parcel within 40 m")
PC[, c("p_num", "p_dir", "p_sname", "p_stype") := addr_parts(SITUS_ADDRESS_LINE1)]
PC[p_num == "" & !is.na(SITUS_ADDR_NBR), p_num := sub("[^0-9].*$", "", trimws(SITUS_ADDR_NBR))]
pick <- function(d, acol) {   # d: one row per site with pkey and the address column acol; returns d with the chosen parcel's fields
  d <- copy(d)[, rid := .I]; d[, c("a_num", "a_dir", "a_sname", "a_stype") := addr_parts(get(acol))]
  X <- merge(d[, .(rid, a_num, a_dir, a_sname, a_stype, pkey)], PC[!is.na(SCHEDNUM)], by = "pkey", allow.cartesian = TRUE)
  X[, `:=`(n_a = suppressWarnings(as.integer(a_num)), n_p = suppressWarnings(as.integer(p_num)))]
  X[, same_street := a_sname != "" & a_sname == p_sname & (a_dir == "" | p_dir == "" | a_dir == p_dir) & (a_stype == "" | p_stype == "" | a_stype == p_stype)]
  X[, rule := fcase(same_street & !is.na(n_a) & !is.na(n_p) & n_a == n_p, 1L,
                    same_street & !is.na(n_a) & !is.na(n_p) & n_a %% 2L == n_p %% 2L, 2L,
                    same_street, 3L, default = 4L)]
  X[, numdiff := fifelse(rule == 2L, abs(n_a - n_p), NA_integer_)]
  setorderv(X, c("rid", "rule", "numdiff", "dist_m"), na.last = TRUE); X <- X[!duplicated(rid)]
  out <- merge(d, X[, .(rid, SCHEDNUM, PROP_CLASS, D_CLASS_CN, ZONE_ID, ZONE_10, TOT_UNITS, year_built, SITUS_ADDRESS_LINE1, LAND_AREA, parcel_dist_m = dist_m, rule)], by = "rid", all.x = TRUE)   # owner names stay in the work/ cache only
  out[, parcel_match := PM[fifelse(is.na(rule), 5L, rule)]]; out[, c("rid", "rule", "a_num", "a_dir", "a_sname", "a_stype") := NULL]; out[] }
# ---- 3. broad classes
broad <- function(cls, zone) { cls <- toupper(ifelse(is.na(cls), "", cls)); zone <- toupper(ifelse(is.na(zone), "", zone))
  fcase(cls == "", "No parcel match",
        grepl("SINGLE FAM|^SFR|DUPLEX|TRIPLEX|ROWHOUSE|TOWNHOUSE|CONDO|APARTMENT|MULTI|RESIDENTIAL|MOBILE|MIXED USE.*RES", cls), "Residential",
        grepl("PARK$|^DENVER PARK|OPEN SPACE|GOLF|CEMETERY|RECREATION", cls), "Park / open space",
        grepl("STADIUM|STOCK SHOW|JAIL|COURTHOUSE|FIRE STATION|POLICE|LIBRARY|MUSEUM|GOVERNMENT|SCHOOL|CHURCH|HOSPITAL|RELIGIOUS|CHARIT|EDUCATION|UNIVERSITY|COLLEGE", cls), "Civic / school / health",
        grepl("INDUSTRIAL|WAREHOUSE|UTILIT|RAILROAD|MANUFACTUR", cls), "Industrial / utility",
        grepl("VACANT", cls), "Vacant",
        grepl("EXEMPT", cls) & grepl("PARK|OPEN SPACE|CEMETERY|RECREATION", cls), "Park / open space",
        grepl("EXEMPT|SCHOOL|CHURCH|HOSPITAL|RELIGIOUS|GOVERNMENT|CHARIT|EDUCATION", cls), "Civic / school / health",
        grepl("COMMERCIAL|OFFICE|RETAIL|STORE|HOTEL|MOTEL|RESTAURANT|PARKING|GARAGE|SERVICE|BANK|THEATER|SHOPPING", cls), "Commercial / office",
        default = "Other") }
score <- function(d, acol) { d <- pick(d[, pkey := sprintf("%.6f,%.6f", lon, lat)], acol)
  d[, use_now := broad(D_CLASS_CN, ZONE_ID)]; d[, zone_industrial := grepl("^I-?(A|B|MX)", toupper(ZONE_ID))]   # I-A, I-B, I-MX-* and the former-code IA/IB districts
  d[, redeveloped := !is.na(year_built) & year_built > last_year]; d[, last_decade := paste0(floor(last_year / 10) * 10, "s")]; d[, pkey := NULL]; d[] }
S <- score(sites[, .(site_id, address, first_year, last_year, radar, fe_sectors, lat, lon)], "address")
H <- score(hist[, .(hfirm, name, street, first_year, last_year, sectors, persists_to_1961plus, lat, lon)], "street")
fwrite(S, file.path(O, "site_fate_denver.csv")); fwrite(H, file.path(O, "site_fate_denver_pre1960.csv"))
# ---- 4. summaries
lab <- c(S = "Manufacturers' directory sites 1965-1992", H = "Business-directory hazardous trades 1891-1956")
SM <- rbind(S[, .(series = lab["S"], n = .N), by = .(last_decade, use_now)], H[, .(series = lab["H"], n = .N), by = .(last_decade, use_now)])
SM[, pct := round(100 * n / sum(n), 1), by = .(series, last_decade)]; setorder(SM, series, last_decade, -n); fwrite(SM, file.path(O, "site_fate_summary.csv"))
# how the parcel was chosen, and the agreement rate: the share of numbered addresses with a parcel whose situs address is the site's
PMT <- rbind(S[, .(series = lab["S"], n = .N), by = parcel_match], H[, .(series = lab["H"], n = .N), by = parcel_match]); PMT[, pct := round(100 * n / sum(n), 1), by = series]
PMT[, parcel_match := factor(parcel_match, PM)]; setorder(PMT, series, parcel_match); PMT[, parcel_match := as.character(parcel_match)]
agree <- function(d) { a <- d[parcel_match != PM[5] & grepl("^[0-9]", trimws(d[[if ("address" %in% names(d)) "address" else "street"]]))]; c(n = nrow(a), agree_pct = round(100 * mean(a$parcel_match == PM[1]), 1)) }
AG <- rbind(data.table(series = lab["S"], t(agree(S))), data.table(series = lab["H"], t(agree(H))))
PMT <- rbind(PMT, AG[, .(series, parcel_match = "agreement rate: situs address = site address (numbered addresses with a parcel)", n = n, pct = agree_pct)])
fwrite(PMT, file.path(O, "site_fate_parcel_match.csv")); print(dcast(PMT, parcel_match ~ series, value.var = "pct", fill = 0))
message("parcel agreement rate (situs address equals the site's address): ", AG$agree_pct[1], "% of ", AG$n[1], " numbered 1965-92 sites with a parcel; ", AG$agree_pct[2], "% of ", AG$n[2], " pre-1960 trades")
ST <- rbind(S[, .(series = lab["S"], n = .N), by = use_now], H[, .(series = lab["H"], n = .N), by = use_now]); ST[, pct := round(100 * n / sum(n), 1), by = series]
print(dcast(ST, use_now ~ series, value.var = "pct", fill = 0))
Z <- rbind(S[use_now != "No parcel match", .(series = lab["S"], n = .N, pct_zone_industrial = round(100 * mean(zone_industrial), 1), pct_redeveloped = round(100 * mean(redeveloped), 1), median_year_built = median(year_built, na.rm = TRUE))],
           H[use_now != "No parcel match", .(series = lab["H"], n = .N, pct_zone_industrial = round(100 * mean(zone_industrial), 1), pct_redeveloped = round(100 * mean(redeveloped), 1), median_year_built = median(year_built, na.rm = TRUE))])
print(Z); fwrite(Z, file.path(O, "site_fate_zoning.csv"))
SEN <- S[use_now %in% c("Residential", "Park / open space", "Civic / school / health") & radar == "Not on any list"]
fwrite(SEN[, .(site_id, address, first_year, last_year, fe_sectors, use_now, D_CLASS_CN, ZONE_ID, ZONE_10, TOT_UNITS, year_built, SITUS_ADDRESS_LINE1, parcel_match, parcel_dist_m, lat, lon)], file.path(O, "site_fate_sensitive.csv"))
message(nrow(S), " Denver sites (", sum(S$use_now != "No parcel match"), " on a parcel); ", nrow(SEN), " are now residential, park or civic/school/health with no cleanup record; ",
        sum(S$use_now == "Residential"), " residential in all (", sum(S$TOT_UNITS[S$use_now == "Residential"], na.rm = TRUE), " dwelling units)")
file.copy(file.path(O, c("site_fate_summary.csv", "site_fate_denver.csv", "site_fate_denver_pre1960.csv", "site_fate_zoning.csv")), A, overwrite = TRUE)
