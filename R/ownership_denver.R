# Who owns Denver's rental housing? Ownership concentration from the Assessor's parcel records.
#
#   Rscript R/fetch_denver_property.R     (writes work/property/owners.csv)
#   Rscript R/ownership_denver.R
#
# Every residential parcel in the City and County of Denver, with its owner's name and mailing address (public records).
#   Units: the parcel's total units (1 for houses and condominium units). A unit is owner-occupied when the owner's mailing address is
#   the property itself (same street line and ZIP); for a 2+ unit building lived in by its owner, the other units count as rentals.
#   "Rental" therefore means not occupied by its owner: it also includes second homes and vacant units.
#   Owners: parcels are grouped into owners by normalised name (punctuation, LLC/INC/TRUST and similar suffixes removed). A second,
#   broader grouping also links names that share a mailing address (landlords who hold property through several LLCs at one office),
#   except addresses (with unit numbers) shared by more than 5 different individuals (tax or mortgage servicers, not landlords).
#   Owner types: public (city, state, federal, Denver Housing Authority, school and transit districts), company (LLC, corporation,
#   partnership, fund), trust, non-profit or religious, individual.
# Measures: owners and rental units by owner size; the share of rental units held by the largest owners; by tract, the share of rental
# units held by owners of 20+ and 100+ units, by companies and by owners outside Colorado; by 1938 HOLC grade; near historical sites.
# Outputs (aggregates only; no names): data/results/ownership/*.csv, ownership_summary.md; app/data/ownership_*.csv.
# The list of the largest owners, with names, is written only to work/property/top_owners_private.csv (git-ignored) for checking.
for (p in c("data.table", "sf")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(data.table); library(sf) })
sf_use_s2(FALSE); UTM <- 26913; D <- "work/property"; A <- "app/data"; O <- "data/results/ownership"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
if (!file.exists(file.path(D, "owners.csv"))) stop("run Rscript R/fetch_denver_property.R first (it now also writes owners.csv)")
num <- function(x) suppressWarnings(as.numeric(x))
P <- fread(file.path(D, "owners.csv"), colClasses = "character")
P <- P[!duplicated(SCHEDNUM)]
message(nrow(P), " parcels; property classes:"); print(P[, .N, by = D_CLASS_CN][order(-N)][1:min(.N, 40)])
# ---------------------------------------------------------------- residential parcels and units
P[, type := fcase(grepl("CONDO", D_CLASS_CN), "Condominium unit", grepl("ROW|TOWN", D_CLASS_CN), "Rowhouse / townhouse",
                  grepl("DUPLEX|TRIPLEX|TWO.?UNIT|THREE.?UNIT|2-?3 UNIT", D_CLASS_CN), "Duplex / triplex",
                  grepl("APART|MULTI|4-8|9\\+|UNITS", D_CLASS_CN), "Apartment building (4+ units)",
                  grepl("SINGLE|SFR|RESIDENTIAL$|RESIDENTIAL-SF|RESIDENTIAL - SF|MOBILE|MANUFACT", D_CLASS_CN), "Single-family house", default = NA_character_)]
P <- P[!is.na(type)]
P[, units := num(TOT_UNITS)]; P[is.na(units) | units < 1, units := fcase(type == "Duplex / triplex", 2, type == "Apartment building (4+ units)", 4, default = 1)]
P[type %in% c("Single-family house", "Condominium unit", "Rowhouse / townhouse"), units := pmin(units, 1)]
# ---------------------------------------------------------------- owner-occupancy (owner's mailing address = the property)
st_norm <- function(x) { x <- toupper(trimws(x)); x <- gsub("[.,#]", " ", x); x <- gsub("\\b(STREET)\\b", "ST", x); x <- gsub("\\b(AVENUE)\\b", "AVE", x)
  x <- gsub("\\b(BOULEVARD)\\b", "BLVD", x); x <- gsub("\\b(PLACE)\\b", "PL", x); x <- gsub("\\b(DRIVE)\\b", "DR", x); x <- gsub("\\b(COURT)\\b", "CT", x)
  x <- gsub("\\b(UNIT|APT|STE|SUITE)\\b", " ", x); gsub("\\s+", " ", trimws(x)) }
P[, `:=`(own_st = st_norm(OWNER_ADDRESS_LINE1), sit_st = st_norm(SITUS_ADDRESS_LINE1), own_zip = substr(gsub("\\D", "", OWNER_ZIP), 1, 5), sit_zip = substr(gsub("\\D", "", SITUS_ZIP), 1, 5))]
P[, owner_occ := own_st != "" & (own_st == sit_st | startsWith(own_st, paste0(sit_st, " ")) | startsWith(sit_st, paste0(own_st, " "))) & (own_zip == sit_zip | own_zip == "")]
P[, rental_units := fifelse(owner_occ, pmax(units - 1, 0), units)]
P[, out_of_state := !(toupper(trimws(OWNER_STATE)) %in% c("CO", "COLORADO", ""))]
# ---------------------------------------------------------------- owner type and owner groups
nm <- toupper(trimws(P$OWNER_NAME))
P[, owner_type := fcase(
  grepl("CITY (AND|&) COUNTY OF DENVER|^CITY OF |STATE OF COLORADO|UNITED STATES|U S A$|HOUSING AUTH|DENVER HOUSING|SCHOOL DIST|REGIONAL TRANSPORTATION|URBAN RENEWAL|COUNTY OF |DEPARTMENT OF|BOARD OF", nm), "Public",
  grepl("CHURCH|PARISH|DIOCESE|ARCHBISHOP|CONGREGATION|MINISTR|HABITAT FOR HUMANITY|NONPROFIT|NON-PROFIT|COMMUNITY LAND TRUST|MERCY HOUSING|CATHOLIC|SALVATION ARMY|VOLUNTEERS OF AMERICA|COALITION FOR THE HOMELESS", nm), "Non-profit or religious",
  grepl("\\bL ?L ?C\\b|\\bINC\\b|\\bCORP|\\bL ?P\\b|\\bLLLP\\b|\\bLTD\\b|COMPANY|\\bCO\\b$|PARTNERS|HOLDING|PROPERT|INVEST|APARTMENT|CAPITAL|\\bFUND|\\bREIT\\b|BORROWER|VENTURE|ENTERPRISE|GROUP|ASSOCIATES|REALTY|HOMES\\b|RENTAL|MANAGEMENT|\\bBANK\\b|ASSOCIATION|\\bASSN\\b|SERIES", nm), "Company",
  grepl("TRUST|TRUSTEE|\\bTR\\b|REVOCABLE|LIVING", nm), "Trust", default = "Individual")]
nm_norm <- function(x) { x <- toupper(x); x <- gsub("[^A-Z0-9& ]", " ", x)
  x <- gsub("\\b(L L C|LLC|INC|INCORPORATED|CORP|CORPORATION|CO|COMPANY|LP|LLLP|LTD|THE|TRUST|TRUSTEE|TR|ET AL|ETAL|REVOCABLE|LIVING|SERIES [A-Z0-9]+)\\b", " ", x)
  gsub("\\s+", " ", trimws(x)) }
P[, name_key := nm_norm(OWNER_NAME)]; P[name_key == "", name_key := paste0("blank_", SCHEDNUM)]
P[, addr_key := fifelse(own_st == "", NA_character_, paste(gsub("\\s+", " ", toupper(trimws(paste(OWNER_ADDRESS_LINE1, OWNER_ADDRESS_LINE2)))), own_zip))]   # unit numbers kept
# owners by name
P[, g_name := .GRP, by = name_key]
# owners by name or shared mailing address (connected components), skipping servicer-like addresses
P[, indiv_names_at_addr := uniqueN(name_key[owner_type == "Individual"]), by = addr_key]
P[, link_addr := !is.na(addr_key) & indiv_names_at_addr <= 5 & !owner_occ]
P[, g := g_name]
repeat { old <- P$g
  P[link_addr == TRUE, g := min(g), by = addr_key]; P[, g := min(g), by = name_key]
  if (identical(old, P$g)) break }
setnames(P, "g", "g_family")
message(uniqueN(P$g_name), " owner names; ", uniqueN(P$g_family), " owner families (names linked by shared mailing address)")
# ---------------------------------------------------------------- owner sizes and concentration (private owners; public owners shown separately)
band <- function(u) factor(fcase(u <= 1, "1 unit", u <= 4, "2-4 units", u <= 19, "5-19 units", u <= 99, "20-99 units", u <= 999, "100-999 units", default = "1,000+ units"),
                           levels = c("1 unit", "2-4 units", "5-19 units", "20-99 units", "100-999 units", "1,000+ units"))
size_tab <- function(gcol, label) {
  G <- P[rental_units > 0, .(rental = sum(rental_units), type = owner_type[which.max(rental_units)], out_state = sum(rental_units[out_of_state]) > sum(rental_units) / 2), by = c(gcol)]
  G[, size := band(rental)]
  S <- G[, .(owners = .N, rental_units = sum(rental)), by = size][order(size)][, `:=`(pct_owners = round(100 * owners / sum(owners), 2), pct_rental_units = round(100 * rental_units / sum(rental_units), 1))]
  S[, grouping := label]; list(G = G, S = S) }
SN <- size_tab("g_name", "by owner name"); SF <- size_tab("g_family", "by owner family (shared mailing address)")
SIZE <- rbind(SN$S, SF$S); setcolorder(SIZE, "grouping")
conc <- function(G, label, priv = TRUE) { G <- if (priv) G[type != "Public"] else G; G <- G[order(-rental)]; tot <- sum(G$rental); n <- nrow(G)
  data.table(grouping = label, owners = n, rental_units = tot,
             top10_pct = round(100 * sum(head(G$rental, 10)) / tot, 1), top50_pct = round(100 * sum(head(G$rental, 50)) / tot, 1), top100_pct = round(100 * sum(head(G$rental, 100)) / tot, 1),
             top1pct_owners_pct = round(100 * sum(head(G$rental, ceiling(n / 100))) / tot, 1), owners_20plus_pct = round(100 * sum(G$rental[G$rental >= 20]) / tot, 1),
             owners_100plus_pct = round(100 * sum(G$rental[G$rental >= 100]) / tot, 1), hhi = round(10000 * sum((G$rental / tot)^2), 1)) }
SFR_TYPES <- c("Single-family house", "Condominium unit", "Rowhouse / townhouse", "Duplex / triplex")
GS <- P[rental_units > 0 & type %in% SFR_TYPES, .(rental = sum(rental_units), type = owner_type[which.max(rental_units)]), by = g_family]
CONC <- rbind(conc(SN$G, "Private owners, by name"), conc(SF$G, "Private owners, by family"), conc(GS, "Private owners, by family: houses, condos, rowhouses, duplexes only"))
# public and non-profit share
TYPE <- P[rental_units > 0, .(rental_units = sum(rental_units), parcels = .N), by = owner_type][, pct_rental_units := round(100 * rental_units / sum(rental_units), 1)][order(-rental_units)]
OCC <- P[, .(parcels = .N, units = sum(units), owner_occupied_units = sum(units - rental_units), rental_units = sum(rental_units)), by = type][, pct_owner_occupied := round(100 * owner_occupied_units / units, 1)][order(-units)]
# ---------------------------------------------------------------- where: tracts, HOLC grades, near historical sites
P[, `:=`(x = num(SITUS_X_COORD), y = num(SITUS_Y_COORD))]; Q <- P[!is.na(x) & x > 0]
fam_size <- SF$G[, .(g_family, fam_rental = rental)]; Q <- merge(Q, fam_size, by = "g_family", all.x = TRUE); Q[is.na(fam_rental), fam_rental := 0]
pts <- st_transform(st_as_sf(Q[, .(x, y)], coords = c("x", "y"), crs = 2877), UTM)
TR <- st_transform(st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE), UTM); TR <- TR[substr(TR$GEOID, 1, 5) == "08031", ]
Q[, GEOID := TR$GEOID[vapply(st_within(pts, TR), function(i) if (length(i)) i[1] else NA_integer_, 1L)]]
HOLC <- st_make_valid(st_transform(st_read(file.path(A, "holc_denver.geojson"), quiet = TRUE), UTM)); HOLC <- HOLC[HOLC$grade %in% c("A", "B", "C", "D"), "grade"]
Q[, holc := { w <- st_within(pts, HOLC); vapply(w, function(i) if (length(i)) HOLC$grade[i[1]] else "Not graded", "") }]
S <- fread(file.path(A, "sites.csv"))[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx") & !is.na(lat) & !is.na(lon)][, .(kind = fifelse(radar == "Not on any list", "hidden", "known"), lat, lon)]
H <- fread(file.path(A, "historical_sites.csv"))[fe_hazard %in% c(TRUE, "True") & precision != "town" & !is.na(lat) & town == "DENVER"][, .(kind = "pre1960", lat, lon)]
SITES <- st_transform(st_as_sf(rbind(S, H), coords = c("lon", "lat"), crs = 4326), UTM)
for (k in c("hidden", "known", "pre1960")) Q[, (paste0("near_", k)) := lengths(st_is_within_distance(pts, SITES[SITES$kind == k, ], 400)) > 0]
summ <- function(d) d[, .(parcels = .N, units = sum(units), rental_units = sum(rental_units), pct_rental = round(100 * sum(rental_units) / sum(units), 1),
                          pct_rental_owner_20plus = round(100 * sum(rental_units[fam_rental >= 20]) / max(1, sum(rental_units)), 1),
                          pct_rental_owner_100plus = round(100 * sum(rental_units[fam_rental >= 100]) / max(1, sum(rental_units)), 1),
                          pct_rental_company = round(100 * sum(rental_units[owner_type == "Company"]) / max(1, sum(rental_units)), 1),
                          pct_rental_out_of_state = round(100 * sum(rental_units[out_of_state]) / max(1, sum(rental_units)), 1),
                          pct_rental_public = round(100 * sum(rental_units[owner_type == "Public"]) / max(1, sum(rental_units)), 1))]
BY_HOLC <- Q[, summ(.SD), by = .(holc)][order(holc)]
BY_SITE <- rbindlist(list(Q[near_hidden == TRUE, summ(.SD)][, area := "Within 400 m of a hidden site (1965-92, no inventory)"],
                          Q[near_known == TRUE, summ(.SD)][, area := "Within 400 m of a known site (1965-92, on an inventory)"],
                          Q[near_pre1960 == TRUE, summ(.SD)][, area := "Within 400 m of a pre-1960 hazardous trade"],
                          Q[!near_hidden & !near_known & !near_pre1960, summ(.SD)][, area := "More than 400 m from any historical site"],
                          Q[, summ(.SD)][, area := "All of Denver"])); setcolorder(BY_SITE, "area")
BY_TYPE_SITE <- rbindlist(list(Q[type %in% SFR_TYPES & (near_hidden | near_known | near_pre1960), summ(.SD)][, area := "Houses, condos, rowhouses, duplexes within 400 m of any historical site"],
                               Q[type %in% SFR_TYPES & !(near_hidden | near_known | near_pre1960), summ(.SD)][, area := "Houses, condos, rowhouses, duplexes farther away"])); setcolorder(BY_TYPE_SITE, "area")
BY_TR <- Q[!is.na(GEOID), summ(.SD), by = GEOID]
TP <- fread(file.path(A, "tract_panel.csv"), colClasses = c(GEOID = "character"))[census == 2020, .(GEOID, p_black, p_hisp, p_pov, p_owner, mrent_2020)]
HT <- fread(file.path(A, "health_tracts_study.csv"), colClasses = c(GEOID = "character"))
HT <- HT[, intersect(c("GEOID", "known_1965_92", "hidden_1965_92", "pre1960_trades"), names(HT)), with = FALSE]
BY_TR <- merge(merge(BY_TR, TP, by = "GEOID", all.x = TRUE), HT, by = "GEOID", all.x = TRUE)
# who lives where large landlords own: tract-level association, weighted by rental units (tracts with 50+ rental units)
TRM <- BY_TR[rental_units >= 50 & !is.na(p_black) & !is.na(p_pov)]
TRM[, `:=`(any_hidden = as.numeric(hidden_1965_92 > 0), any_known = as.numeric(known_1965_92 > 0), lrent = log(pmax(mrent_2020, 1)))]
ass <- function(yv) { f <- as.formula(paste(yv, "~ p_black + p_hisp + p_pov + any_hidden + any_known")); m <- lm(f, data = TRM, weights = rental_units)
  ct <- summary(m)$coefficients[-1, , drop = FALSE]
  data.table(outcome = yv, term = rownames(ct), estimate = round(ct[, 1], 3), se = round(ct[, 2], 3), p = signif(ct[, 4], 3), tracts = nobs(m)) }
ASSOC <- rbindlist(lapply(c("pct_rental_owner_20plus", "pct_rental_owner_100plus", "pct_rental_company", "pct_rental_out_of_state"), ass))
ASSOC[, term := c(p_black = "Black residents (per point of %)", p_hisp = "Hispanic residents (per point of %)", p_pov = "Poverty rate (per point of %)",
                  any_hidden = "Tract has a hidden 1965-92 site", any_known = "Tract has a known 1965-92 site")[term]]
# ---------------------------------------------------------------- write (aggregates only) and the private check list
TOP <- SF$G[order(-rental)][1:min(.N, 100)]
TOP[, example_names := vapply(g_family, function(gf) paste(head(unique(P[g_family == gf & rental_units > 0, OWNER_NAME]), 4), collapse = " | "), "")]
fwrite(TOP, file.path(D, "top_owners_private.csv"))
for (nm_ in c("SIZE", "CONC", "TYPE", "OCC", "BY_HOLC", "BY_SITE", "BY_TYPE_SITE", "BY_TR", "ASSOC")) {
  f <- c(SIZE = "owner_size", CONC = "concentration", TYPE = "owner_types", OCC = "occupancy_by_type", BY_HOLC = "by_holc", BY_SITE = "by_site_proximity",
         BY_TYPE_SITE = "by_site_proximity_small_buildings", BY_TR = "by_tract", ASSOC = "tract_associations")[[nm_]]
  fwrite(get(nm_), file.path(O, paste0(f, ".csv"))); fwrite(get(nm_), file.path(A, paste0("ownership_", f, ".csv"))) }
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
writeLines(c("# Who owns Denver's rental housing", "", sprintf("%s residential parcels, %s units, %s not occupied by their owner. Aggregates only.",
               format(nrow(P), big.mark = ","), format(sum(P$units), big.mark = ","), format(sum(P$rental_units), big.mark = ",")), "",
             "## Occupancy by property type", "", kab(OCC), "", "## Owner types", "", kab(TYPE), "", "## Owners by size", "", kab(SIZE), "", "## Concentration", "", kab(CONC), "",
             "## By 1938 HOLC grade", "", kab(BY_HOLC), "", "## Near historical sites", "", kab(BY_SITE), "", kab(BY_TYPE_SITE), "",
             "## Tract associations (weighted by rental units; tracts with 50+ rental units)", "", kab(ASSOC)), file.path(O, "ownership_summary.md"))
print(OCC); print(TYPE); print(SIZE); print(CONC); print(BY_HOLC); print(BY_SITE); print(ASSOC)
message("wrote ", O, "; the largest owners (names) are in ", file.path(D, "top_owners_private.csv"), " and are not published")
