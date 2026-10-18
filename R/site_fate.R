# What became of the sites? Current land use of every historical hazardous site in the City and County of Denver.
#   Rscript R/site_fate.R
# Source: Denver Community Planning and Development, "CPD Land Use 2022" (parcel polygons with the planning land-use category and the
# assessor's property class; ArcGIS feature service on Denver's open-data org, no key). Paged through the REST API in 2,000-record
# pages for the bounding box of the Denver core tracts and cached in work/site_fate/denver_landuse_2022.geojson.
# Every site (1965-1992 manufacturers' directory, hazardous sectors) and every street-level pre-1960 hazardous trade in Denver County is
# joined to the parcel it falls in. Outputs (data/results/site_fate/, copies in app/data/):
#   site_fate_denver.csv        one row per site: last directory year, regulatory status, parcel land use and class today
#   site_fate_summary.csv       current use by decade the site was last listed (counts and %), sites vs pre-1960 trades
#   site_fate_sensitive.csv     sites now under residential, school, park or health use, with no cleanup record ("hidden conversions")
# This is the Frickel & Elliott (2008) land-use-conversion question for the whole inventory rather than a sample; Sanborn sheets and the
# Denver Public Library's reverse street directories are the archival check for a sample of these.
suppressPackageStartupMessages({ library(sf); library(data.table); library(jsonlite) })
sf_use_s2(FALSE); W <- "work/site_fate"; O <- "data/results/site_fate"; A <- "app/data"; for (d in c(W, O)) dir.create(d, showWarnings = FALSE, recursive = TRUE)
SVC <- "https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/arcgis/rest/services/CPD_Land_Use_2022/FeatureServer/0/query"
# ---- 1. parcels (cached)
f_lu <- file.path(W, "denver_landuse_2022.geojson")
if (!file.exists(f_lu)) {
  core <- st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE); bb <- st_bbox(core[core$county == "08031" | core$core %in% c(TRUE, "TRUE"), ])
  env <- sprintf("%f,%f,%f,%f", bb["xmin"] - 0.02, bb["ymin"] - 0.02, bb["xmax"] + 0.02, bb["ymax"] + 0.02)
  pages <- list(); off <- 0; repeat {
    u <- paste0(SVC, "?where=1%3D1&geometry=", URLencode(env, reserved = TRUE), "&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects",
                "&outFields=SCHEDNUM,D_CLASS,D_CLASS_CN,CPD_LANDUSE,TOTAL_UNITS&outSR=4326&resultOffset=", off, "&resultRecordCount=2000&f=geojson")
    tmp <- tempfile(fileext = ".geojson"); ok <- tryCatch({ download.file(u, tmp, quiet = TRUE); TRUE }, error = function(e) FALSE)
    if (!ok) stop("could not reach Denver's land-use service; try again later or check the service name in this script")
    g <- tryCatch(st_read(tmp, quiet = TRUE), error = function(e) NULL); if (is.null(g) || !nrow(g)) break
    pages[[length(pages) + 1]] <- g; message("parcels: ", off + nrow(g)); off <- off + 2000; if (nrow(g) < 2000) break }
  LU <- do.call(rbind, pages); st_write(LU, f_lu, quiet = TRUE) }
LU <- st_make_valid(st_read(f_lu, quiet = TRUE)); LU$CPD_LANDUSE[is.na(LU$CPD_LANDUSE) | LU$CPD_LANDUSE == ""] <- "Unknown"
message(nrow(LU), " parcels; land-use categories: ", paste(names(sort(table(LU$CPD_LANDUSE), decreasing = TRUE)), collapse = ", "))
# ---- 2. sites and pre-1960 trades in Denver County
sites <- fread(file.path(A, "sites.csv"), colClasses = c(GEOID = "character"))[!is.na(lat) & fe_hazard %in% c(TRUE, "True") & substr(GEOID, 1, 5) == "08031"]
hist <- fread(file.path(A, "historical_sites.csv"), colClasses = c(GEOID = "character"))[!is.na(lat) & precision != "town" & fe_hazard %in% c(TRUE, "True") & town == "DENVER"]
pt <- function(d) st_as_sf(d, coords = c("lon", "lat"), crs = 4326, remove = FALSE)
jn <- function(p) { j <- st_join(pt(p), LU[, c("SCHEDNUM", "D_CLASS", "D_CLASS_CN", "CPD_LANDUSE", "TOTAL_UNITS")], join = st_within, left = TRUE); j <- j[!duplicated(j[[1]]), ]; as.data.table(st_drop_geometry(j)) }
S <- jn(sites[, .(site_id, address, first_year, last_year, radar, fe_sectors, lat, lon)]); H <- jn(hist[, .(hfirm, name, street, first_year, last_year, sectors, persists_to_1961plus, lat, lon)])
# broad classes for the tables
broad <- function(lu, cls) { lu <- tolower(ifelse(is.na(lu), "unknown", lu)); cls <- tolower(ifelse(is.na(cls), "", cls))
  fcase(grepl("single|multi|residential|duplex|row|condo|apartment", lu) | grepl("residential|apartment|condo|single fam|duplex", cls), "Residential",
        grepl("industrial|utility|utilities|warehouse|transportation|rail", lu) | grepl("industrial|warehouse", cls), "Industrial / utility",
        grepl("commercial|office|retail|mixed", lu) | grepl("commercial|office|retail|hotel", cls), "Commercial / office",
        grepl("park|open space|golf|cemetery", lu) | grepl("park|cemetery", cls), "Park / open space",
        grepl("school|educat|civic|public|church|hospital|institution", lu) | grepl("school|church|hospital|public|exempt", cls), "Civic / school / health",
        grepl("vacant", lu) | grepl("vacant", cls), "Vacant",
        is.na(lu) | lu == "unknown", "No parcel match", default = "Other") }
S[, use_now := broad(CPD_LANDUSE, D_CLASS_CN)]; H[, use_now := broad(CPD_LANDUSE, D_CLASS_CN)]
S[, last_decade := paste0(floor(last_year / 10) * 10, "s")]; H[, last_decade := paste0(floor(last_year / 10) * 10, "s")]
fwrite(S, file.path(O, "site_fate_denver.csv")); fwrite(H, file.path(O, "site_fate_denver_pre1960.csv"))
# ---- 3. summaries
SM <- rbind(S[, .(series = "Manufacturers' directory sites 1965-1992", n = .N), by = .(last_decade, use_now)],
            H[, .(series = "Business-directory hazardous trades 1891-1956", n = .N), by = .(last_decade, use_now)])
SM[, pct := round(100 * n / sum(n), 1), by = .(series, last_decade)]; setorder(SM, series, last_decade, -n)
fwrite(SM, file.path(O, "site_fate_summary.csv"))
ST <- rbind(S[, .(series = "Manufacturers' directory sites 1965-1992", n = .N), by = use_now], H[, .(series = "Business-directory hazardous trades 1891-1956", n = .N), by = use_now])
ST[, pct := round(100 * n / sum(n), 1), by = series]; print(dcast(ST, use_now ~ series, value.var = "pct"))
SEN <- S[use_now %in% c("Residential", "Park / open space", "Civic / school / health") & radar == "Not on any list"]
fwrite(SEN[, .(site_id, address, first_year, last_year, fe_sectors, use_now, CPD_LANDUSE, D_CLASS_CN, TOTAL_UNITS, lat, lon)], file.path(O, "site_fate_sensitive.csv"))
message(nrow(S), " Denver sites joined (", sum(S$use_now != "No parcel match"), " on a parcel); ", nrow(SEN), " are now residential, park or civic/school/health with no cleanup record")
file.copy(file.path(O, c("site_fate_summary.csv", "site_fate_denver.csv", "site_fate_denver_pre1960.csv")), A, overwrite = TRUE)
