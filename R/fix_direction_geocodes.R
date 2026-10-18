# Remove geocodes that contradict the address's own direction on the Denver street grid.
#   Rscript R/fix_direction_geocodes.R        (idempotent; run once, then the downstream scripts)
# Denver's grid numbers north/south from Ellsworth Avenue and east/west from Broadway. A listing such as "4000 S. KALAMATH, DENVER"
# lies south of Ellsworth (latitude about 39.64), but the geocoder's direction-loose pass can place it on the unprefixed north
# Kalamath Street (latitude about 39.77) — in the north Denver industrial corridor. Audit (Oct 2026) found Denver listings of this kind, nearly all in the 1965 edition. Rule: a Denver listing whose street starts with an explicit direction
# (S, N, E, W, or the word) and whose point lies more than about 500 m on the wrong side of the baseline is set to unlocated
# (lat/lon/site removed, geo_level "none"); sites left with no located listing are dropped; the others keep their remaining years.
# Files changed in place: data/results/CO_directory_listings_1961-2002.csv, data/by_year/*.csv, app/data/{sites, site_years,
# site_firms}.csv, and the same in data/full_inventory/ when present. The removed listings are written to
# data/results/geocode_direction_conflicts.csv.
suppressPackageStartupMessages(library(data.table))
ELLS <- 39.7163; BWAY <- -104.9875; TOL <- 0.005   # baselines (Ellsworth Ave latitude, Broadway longitude); ~500 m tolerance
dir_of <- function(street) { s <- toupper(trimws(ifelse(is.na(street), "", street)))
  m <- regmatches(s, regexec("^[0-9]+[A-Z]?\\s+(SOUTH|NORTH|EAST|WEST|S|N|E|W)\\.?\\s", s)); vapply(m, function(x) if (length(x) == 2) substr(x[2], 1, 1) else "", "") }
conflict <- function(street, city, lat, lon, level) { d <- dir_of(street); den <- toupper(trimws(ifelse(is.na(city), "", city))) == "DENVER" & !is.na(lat) & level %in% c("address", "address_approx")   # street-level points only
  den & ((d == "S" & lat > ELLS + TOL) | (d == "N" & lat < ELLS - TOL) | (d == "W" & lon > BWAY + TOL) | (d == "E" & lon < BWAY - TOL)) }
fix_set <- function(listings_f, sites_f, years_f = NULL, firms_f = NULL, by_year_dir = NULL, label = "") {
  if (!file.exists(listings_f)) return(invisible(NULL))
  L <- fread(listings_f, colClasses = c(sic = "character", zip = "character", est = "character", size = "character"))
  bad <- conflict(L$street, L$city, L$lat, L$lon, L$geo_level); message(label, ": ", sum(bad), " listings with a direction conflict")
  if (!any(bad)) return(invisible(NULL))
  out <- L[bad, .(year, name, street, city, lat, lon, site_id, fe_hazard)][, file := label]
  of <- "data/results/geocode_direction_conflicts.csv"; fwrite(if (file.exists(of)) unique(rbind(fread(of), out, fill = TRUE)) else out, of)
  hit <- unique(L$site_id[bad & !is.na(L$site_id) & nzchar(L$site_id)])
  L[bad, `:=`(lat = NA_real_, lon = NA_real_, site_id = NA_character_, geo_level = "none")]; fwrite(L, listings_f)
  if (!is.null(by_year_dir) && dir.exists(by_year_dir)) for (f in list.files(by_year_dir, "\\.csv$", full.names = TRUE)) {
    B <- fread(f, colClasses = c(zip = "character", sic_codes = "character")); b <- conflict(B$street_address, B$city, B$latitude, B$longitude, if ("geocode_level" %in% names(B)) B$geocode_level else rep("address", nrow(B)))
    if (any(b)) { B[b, `:=`(latitude = NA_real_, longitude = NA_real_, site_id = NA_character_)]; if ("geocode_level" %in% names(B)) B[b, geocode_level := "none"]; fwrite(B, f) } }
  if (file.exists(sites_f) && length(hit)) {
    S <- fread(sites_f, colClasses = c(GEOID = "character", zip = "character")); keep_years <- L[site_id %in% hit, .(yrs = list(sort(unique(year)))), by = site_id]
    gone <- setdiff(hit, keep_years$site_id); message(label, ": ", length(gone), " sites dropped (no located listing left), ", nrow(keep_years), " sites keep other years")
    S <- S[!site_id %in% gone]
    for (i in seq_len(nrow(keep_years))) { id <- keep_years$site_id[i]; y <- keep_years$yrs[[i]]; S[site_id == id, `:=`(first_year = min(y), last_year = max(y))] }
    fwrite(S, sites_f)
    if (!is.null(years_f) && file.exists(years_f)) { Y <- fread(years_f); ly <- unique(L[site_id %in% hit, .(site_id, year)])
      Y <- Y[!site_id %in% hit | paste(site_id, year) %in% paste(ly$site_id, ly$year)]; fwrite(Y, years_f) }
    if (!is.null(firms_f) && file.exists(firms_f)) { Fm <- fread(firms_f); if ("site_id" %in% names(Fm)) fwrite(Fm[!site_id %in% gone], firms_f) } }
}
fix_set("data/results/CO_directory_listings_1961-2002.csv", "app/data/sites.csv", "app/data/site_years.csv", "app/data/site_firms.csv", "data/by_year", "complete editions")
fix_set("data/full_inventory/CO_directory_listings_1961-2002.csv", "data/full_inventory/sites.csv", NULL, "data/full_inventory/site_firms.csv", "data/full_inventory/by_year", "full inventory")
