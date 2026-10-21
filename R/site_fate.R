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
PTS <- unique(rbind(sites[, .(lon, lat)], hist[, .(lon, lat)]))[, pkey := sprintf("%.6f,%.6f", lon, lat)]
message(nrow(sites), " manufacturers' sites, ", nrow(hist), " pre-1960 trades, ", nrow(PTS), " distinct points")
# ---- 2. nearest parcel to each point (cached). Sites were geocoded to street addresses, so most points sit on the street centreline or
#          the kerb rather than inside the lot: the query asks for every parcel within SEARCH_M metres and keeps the nearest one.
SEARCH_M <- 40; FLD2 <- c("ZONE_10", "SITUS_ADDR_NBR", "SITUS_STR_NAME")
f_cache <- file.path(W, "parcels_by_point.csv"); if (file.exists(f_cache) && !"dist_m" %in% names(fread(f_cache, nrows = 1))) file.rename(f_cache, file.path(W, "parcels_by_point_v1.csv"))
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
    a <- as.data.table(st_drop_geometry(g)); a$dist_m <- round(d, 1); a <- a[order(dist_m)][1]; a$pkey <- pkey; a[] }
  new <- rbindlist(lapply(seq_len(nrow(todo)), function(i) { if (i %% 100 == 0) message("  ", i, "/", nrow(todo)); one(todo$lon[i], todo$lat[i], todo$pkey[i]) }), fill = TRUE)
  for (k in setdiff(c(FLD, FLD2, "dist_m"), names(new))) new[[k]] <- NA
  PC <- rbind(PC, new[, c("pkey", FLD, FLD2, "dist_m"), with = FALSE][, lapply(.SD, as.character)], fill = TRUE); fwrite(PC, f_cache) }
PC <- copy(unique(PC, by = "pkey"))
for (k in c("TOT_UNITS", "RES_ORIG_YEAR_BUILT", "COM_ORIG_YEAR_BUILT", "LAND_AREA", "dist_m")) PC[[k]] <- suppressWarnings(as.numeric(PC[[k]]))
PC[, year_built := pmax(RES_ORIG_YEAR_BUILT, COM_ORIG_YEAR_BUILT, na.rm = TRUE)]; PC[!is.finite(year_built) | year_built < 1800, year_built := NA]
message(sum(!is.na(PC$SCHEDNUM)), " of ", nrow(PC), " points have an assessor parcel within ", SEARCH_M, " m (median distance ", round(median(PC$dist_m, na.rm = TRUE)), " m)")
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
score <- function(d) { d <- merge(d[, pkey := sprintf("%.6f,%.6f", lon, lat)], PC[, .(pkey, SCHEDNUM, PROP_CLASS, D_CLASS_CN, ZONE_ID, ZONE_10, TOT_UNITS, year_built, SITUS_ADDRESS_LINE1, LAND_AREA, parcel_dist_m = dist_m)], by = "pkey", all.x = TRUE)   # owner names stay in the work/ cache only
  d[, use_now := broad(D_CLASS_CN, ZONE_ID)]; d[, zone_industrial := grepl("^I-?(A|B|MX)", toupper(ZONE_ID))]   # I-A, I-B, I-MX-* and the former-code IA/IB districts
  d[, redeveloped := !is.na(year_built) & year_built > last_year]; d[, last_decade := paste0(floor(last_year / 10) * 10, "s")]; d[, pkey := NULL]; d[] }
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
fwrite(SEN[, .(site_id, address, first_year, last_year, fe_sectors, use_now, D_CLASS_CN, ZONE_ID, ZONE_10, TOT_UNITS, year_built, parcel_dist_m, lat, lon)], file.path(O, "site_fate_sensitive.csv"))
message(nrow(S), " Denver sites (", sum(S$use_now != "No parcel match"), " on a parcel); ", nrow(SEN), " are now residential, park or civic/school/health with no cleanup record; ",
        sum(S$use_now == "Residential"), " residential in all (", sum(S$TOT_UNITS[S$use_now == "Residential"], na.rm = TRUE), " dwelling units)")
file.copy(file.path(O, c("site_fate_summary.csv", "site_fate_denver.csv", "site_fate_denver_pre1960.csv", "site_fate_zoning.csv")), A, overwrite = TRUE)
