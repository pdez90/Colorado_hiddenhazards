# What became of the sites? Current parcel use of every historical hazardous site in the City and County of Denver.
#   Rscript R/site_fate.R
# Source: City and County of Denver assessor parcels, open-data feature service ODC_PROP_PARCELS_A (layer 245; no key). For every site
# point one REST query returns the parcel it falls in with the assessor's property class (D_CLASS_CN, e.g. "SINGLE FAMILY-RANCH",
# "INDUSTRIAL-WAREHOUSE", "EXEMPT-SCHOOL"), the current zone district (ZONE_ID), dwelling units and the year the present building was
# built. Responses are cached in work/site_fate/parcels_by_point.csv so a rerun only fetches new points.
# Every site (1965-1992 manufacturers' directory, hazardous sectors) and every street-level pre-1960 hazardous trade in Denver County is
# scored: broad use today; whether the current building post-dates the last directory listing (redeveloped); whether the zone is still
# industrial. Outputs (data/results/site_fate/, copies in app/data/):
#   site_fate_denver.csv          one row per 1965-92 site: last directory year, regulatory status, parcel class, zone, year built, use today
#   site_fate_denver_pre1960.csv  the same for pre-1960 business-directory trades
#   site_fate_summary.csv         use today by decade the site was last listed (counts and %), both series
#   site_fate_sensitive.csv       1965-92 sites now under residential, school, park or health use, with no cleanup record ("hidden conversions")
# This is the Frickel & Elliott (2008) land-use-conversion question for the whole inventory rather than a sample; Sanborn sheets and the
# Denver Public Library's reverse street directories are the archival check for a sample of these.
suppressPackageStartupMessages({ library(sf); library(data.table); library(jsonlite) })
sf_use_s2(FALSE); W <- "work/site_fate"; O <- "data/results/site_fate"; A <- "app/data"; for (d in c(W, O)) dir.create(d, showWarnings = FALSE, recursive = TRUE)
SVC <- "https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/arcgis/rest/services/ODC_PROP_PARCELS_A/FeatureServer/245/query"
FLD <- c("SCHEDNUM", "PROP_CLASS", "D_CLASS", "D_CLASS_CN", "ZONE_ID", "TOT_UNITS", "RES_ORIG_YEAR_BUILT", "COM_ORIG_YEAR_BUILT", "SITUS_ADDRESS_LINE1", "OWNER_NAME", "LAND_AREA")
# ---- 1. sites and pre-1960 trades in Denver County
sites <- fread(file.path(A, "sites.csv"), colClasses = c(GEOID = "character"))[!is.na(lat) & fe_hazard %in% c(TRUE, "True") & substr(GEOID, 1, 5) == "08031"]
hist <- fread(file.path(A, "historical_sites.csv"), colClasses = c(GEOID = "character"))[!is.na(lat) & precision != "town" & fe_hazard %in% c(TRUE, "True") & toupper(town) == "DENVER"]
PTS <- unique(rbind(sites[, .(lon, lat)], hist[, .(lon, lat)]))[, key := sprintf("%.6f,%.6f", lon, lat)]
message(nrow(sites), " manufacturers' sites, ", nrow(hist), " pre-1960 trades, ", nrow(PTS), " distinct points")
# ---- 2. parcel at each point (cached)
f_cache <- file.path(W, "parcels_by_point.csv")
PC <- if (file.exists(f_cache)) fread(f_cache, colClasses = "character") else data.table(key = character())
todo <- PTS[!key %in% PC$key]
if (nrow(todo)) {
  message("querying the Denver parcel service for ", nrow(todo), " points (about ", round(nrow(todo) * 0.4 / 60), " min)")
  one <- function(lon, lat, key) {
    u <- paste0(SVC, "?where=1%3D1&geometry=", lon, "%2C", lat, "&geometryType=esriGeometryPoint&inSR=4326&spatialRel=esriSpatialRelIntersects",
                "&outFields=", paste(FLD, collapse = "%2C"), "&returnGeometry=false&f=json")
    r <- tryCatch(fromJSON(u, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(r) || is.null(r$features) || !length(r$features)) return(data.table(key = key, SCHEDNUM = NA_character_))
    a <- as.data.table(r$features$attributes)[1]; a[, key := key]; a[] }
  new <- rbindlist(lapply(seq_len(nrow(todo)), function(i) { if (i %% 100 == 0) message("  ", i, "/", nrow(todo)); one(todo$lon[i], todo$lat[i], todo$key[i]) }), fill = TRUE)
  for (k in setdiff(FLD, names(new))) new[[k]] <- NA
  PC <- rbind(PC, new[, c("key", FLD), with = FALSE][, lapply(.SD, as.character)], fill = TRUE); fwrite(PC, f_cache) }
PC <- unique(PC, by = "key")
for (k in c("TOT_UNITS", "RES_ORIG_YEAR_BUILT", "COM_ORIG_YEAR_BUILT", "LAND_AREA")) PC[[k]] <- suppressWarnings(as.numeric(PC[[k]]))
PC[, year_built := pmax(RES_ORIG_YEAR_BUILT, COM_ORIG_YEAR_BUILT, na.rm = TRUE)]; PC[!is.finite(year_built) | year_built < 1800, year_built := NA]
message(sum(!is.na(PC$SCHEDNUM)), " of ", nrow(PC), " points fall on an assessor parcel")
# ---- 3. broad classes
broad <- function(cls, zone) { cls <- toupper(ifelse(is.na(cls), "", cls)); zone <- toupper(ifelse(is.na(zone), "", zone))
  fcase(cls == "", "No parcel match",
        grepl("SINGLE FAM|DUPLEX|TRIPLEX|ROWHOUSE|TOWNHOUSE|CONDO|APARTMENT|MULTI|RESIDENTIAL|MOBILE|MIXED USE.*RES", cls), "Residential",
        grepl("INDUSTRIAL|WAREHOUSE|UTILIT|RAILROAD|MANUFACTUR", cls), "Industrial / utility",
        grepl("VACANT", cls), "Vacant",
        grepl("EXEMPT", cls) & grepl("PARK|OPEN SPACE|CEMETERY|RECREATION", cls), "Park / open space",
        grepl("EXEMPT|SCHOOL|CHURCH|HOSPITAL|RELIGIOUS|GOVERNMENT|CHARIT|EDUCATION", cls), "Civic / school / health",
        grepl("COMMERCIAL|OFFICE|RETAIL|STORE|HOTEL|MOTEL|RESTAURANT|PARKING|GARAGE|SERVICE|BANK|THEATER|SHOPPING", cls), "Commercial / office",
        default = "Other") }
score <- function(d) { d <- merge(d[, key := sprintf("%.6f,%.6f", lon, lat)], PC[, .(key, SCHEDNUM, PROP_CLASS, D_CLASS_CN, ZONE_ID, TOT_UNITS, year_built, SITUS_ADDRESS_LINE1, OWNER_NAME, LAND_AREA)], by = "key", all.x = TRUE)
  d[, use_now := broad(D_CLASS_CN, ZONE_ID)]; d[, zone_industrial := grepl("^I($|[-AB])", toupper(ZONE_ID))]   # I-A, I-B, I-MX-* and the former-code IA/IB districts
  d[, redeveloped := !is.na(year_built) & year_built > last_year]; d[, last_decade := paste0(floor(last_year / 10) * 10, "s")]; d[, key := NULL]; d[] }
S <- score(sites[, .(site_id, address, first_year, last_year, radar, fe_sectors, lat, lon)])
H <- score(hist[, .(hfirm, name, street, first_year, last_year, sectors, persists_to_1961plus, lat, lon)])
fwrite(S, file.path(O, "site_fate_denver.csv")); fwrite(H, file.path(O, "site_fate_denver_pre1960.csv"))
# ---- 4. summaries
lab <- c(S = "Manufacturers' directory sites 1965-1992", H = "Business-directory hazardous trades 1891-1956")
SM <- rbind(S[, .(series = lab["S"], n = .N), by = .(last_decade, use_now)], H[, .(series = lab["H"], n = .N), by = .(last_decade, use_now)])
SM[, pct := round(100 * n / sum(n), 1), by = .(series, last_decade)]; setorder(SM, series, last_decade, -n); fwrite(SM, file.path(O, "site_fate_summary.csv"))
ST <- rbind(S[, .(series = lab["S"], n = .N), by = use_now], H[, .(series = lab["H"], n = .N), by = use_now]); ST[, pct := round(100 * n / sum(n), 1), by = series]
print(dcast(ST, use_now ~ series, value.var = "pct", fill = 0))
Z <- rbind(S[use_now != "No parcel match", .(series = lab["S"], n = .N, pct_zone_industrial = round(100 * mean(zone_industrial), 1), pct_redeveloped = round(100 * mean(redeveloped), 1), median_year_built = median(year_built, na.rm = TRUE))],
           H[use_now != "No parcel match", .(series = lab["H"], n = .N, pct_zone_industrial = round(100 * mean(zone_industrial), 1), pct_redeveloped = round(100 * mean(redeveloped), 1), median_year_built = median(year_built, na.rm = TRUE))])
print(Z); fwrite(Z, file.path(O, "site_fate_zoning.csv"))
SEN <- S[use_now %in% c("Residential", "Park / open space", "Civic / school / health") & radar == "Not on any list"]
fwrite(SEN[, .(site_id, address, first_year, last_year, fe_sectors, use_now, D_CLASS_CN, ZONE_ID, TOT_UNITS, year_built, lat, lon)], file.path(O, "site_fate_sensitive.csv"))
message(nrow(S), " Denver sites (", sum(S$use_now != "No parcel match"), " on a parcel); ", nrow(SEN), " are now residential, park or civic/school/health with no cleanup record; ",
        sum(S$use_now == "Residential"), " residential in all (", sum(S$TOT_UNITS[S$use_now == "Residential"], na.rm = TRUE), " dwelling units)")
file.copy(file.path(O, c("site_fate_summary.csv", "site_fate_denver.csv", "site_fate_denver_pre1960.csv", "site_fate_zoning.csv")), A, overwrite = TRUE)
