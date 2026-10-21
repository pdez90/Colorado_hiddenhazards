# Who owns Denver's rental housing? Ownership concentration from the Assessor's parcel records.
#
#   Rscript R/fetch_denver_property.R     (writes work/property/owners.csv)
#   Rscript R/ownership_denver.R
#
# Every residential parcel in the City and County of Denver, with its owner's name and mailing address (public records).
#   Parcels: houses, condominium units, rowhouses, duplexes/triplexes, apartment buildings and senior-citizen apartments, and mixed-use
#   buildings ("RETAIL W/MIXED USE" and the like) that have homes (Assessor's total units above 0; hotels and motels excluded, their units being rooms). Condominium "master" parcels with
#   no owner name and the whole building's unit count are dropped: the units themselves are separate parcels.
#   Units: the parcel's total units (1 for houses and condominium units). A unit is owner-occupied when the owner's mailing address is
#   the property itself (same street line and ZIP; for condominium units and rowhouses, also the same unit number when both records
#   carry one; for duplexes and triplexes, a mailing address at the other door, up to 4 house numbers away on the same side of the
#   same street, also counts); for a 2+ unit building lived in by its owner, the other units count as rentals.
#   "Rental" therefore means not occupied by its owner: it also includes second homes and vacant units.
#   Owners: parcels are grouped into owners by normalised name (punctuation, LLC/INC/TRUST and similar suffixes removed). A second,
#   broader grouping also links names that share a mailing address (landlords who hold property through several LLCs at one office),
#   except addresses (with unit numbers) shared by more than 5 different individuals or 40 different names (servicers, registered
#   agents); public and non-profit owners are never linked.
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
P[, type := fcase(grepl("^RESIDENTIAL[- ]CONDO", D_CLASS_CN), "Condominium unit", grepl("^RESIDENTIAL-ROWHOUSE", D_CLASS_CN), "Rowhouse / townhouse",
                  grepl("^RESIDENTIAL-(DUPLEX|TRIPLEX)", D_CLASS_CN), "Duplex / triplex",
                  grepl("^RESIDENTIAL-(APARTMENT|4 TO 8 UNITS|MULTI UNIT)", D_CLASS_CN), "Apartment building (4+ units)",
                  grepl("^RESIDENTIAL-SENIOR CITIZEN APT", D_CLASS_CN) & num(TOT_UNITS) > 0, "Apartment building (4+ units)",
                  grepl("W/MIXED USE$", D_CLASS_CN) & !grepl("HOTEL|MOTEL", D_CLASS_CN) & num(TOT_UNITS) > 0, "Mixed-use building (homes with shops or offices)",   # hotel units are rooms, not homes
                  grepl("^SFR", D_CLASS_CN), "Single-family house", default = NA_character_)]   # Assessor classes; commercial condominiums, land and mixed-use buildings without homes excluded
P <- P[!is.na(type)]
# condominium master parcels: no owner name and the building's total units; the units are their own parcels, so the master would count twice
P <- P[!(type == "Condominium unit" & !nzchar(trimws(OWNER_NAME)) & !is.na(num(TOT_UNITS)) & num(TOT_UNITS) > 1)]
P[, units := num(TOT_UNITS)]; P[is.na(units) | units < 1, units := fcase(type == "Duplex / triplex", 2, type == "Apartment building (4+ units)", 4, default = 1)]
P[type %in% c("Single-family house", "Condominium unit", "Rowhouse / townhouse"), units := pmin(units, 1)]
# ---------------------------------------------------------------- owner-occupancy (owner's mailing address = the property)
# Compare house number + street name only: direction words (N, E, ...), street types and ZIP+4 differ between the situs and mailing
# records of the same address. A missing ZIP on either side does not block a match. Unit numbers are compared separately below.
addr_key <- function(x) { x <- toupper(trimws(ifelse(is.na(x), "", x))); x <- gsub("[.,#]", " ", x); x <- sub("\\b(UNIT|APT|STE|SUITE)\\b.*$", "", x)
  x <- gsub("\\b(N|S|E|W|NORTH|SOUTH|EAST|WEST)\\b", " ", x)
  x <- gsub("\\b(ST|STREET|AVE|AVENUE|AV|BLVD|BOULEVARD|PL|PLACE|DR|DRIVE|CT|COURT|WAY|LN|LANE|RD|ROAD|PKWY|PARKWAY|CIR|CIRCLE|TER|TERRACE)\\b", " ", x)
  w <- strsplit(trimws(gsub("\\s+", " ", x)), " "); vapply(w, function(t) paste(head(t, 2), collapse = " "), "") }
P[, `:=`(own_k = addr_key(OWNER_ADDRESS_LINE1), sit_k = addr_key(SITUS_ADDRESS_LINE1), own_zip = substr(gsub("\\D", "", OWNER_ZIP), 1, 5), sit_zip = substr(gsub("\\D", "", SITUS_ZIP), 1, 5))]
P[, owner_occ := sit_k != "" & own_k == sit_k & (own_zip == sit_zip | own_zip == "" | sit_zip == "")]
occ0 <- copy(P$owner_occ)
# unit numbers ("APT 2H", "UNIT 2H", "# 2H" are the same unit): a condominium or rowhouse owner whose mailing address is another unit of
# the same building lives there but not in this unit, so this one is a rental
unit_of <- function(x) { x <- toupper(ifelse(is.na(x), "", x)); rx <- "(#|\\bUNIT\\b|\\bAPT\\b|\\bSTE\\b|\\bSUITE\\b)"
  u <- fifelse(grepl(rx, x), sub(paste0(".*", rx, "\\s*"), "", x), ""); u <- gsub("[^A-Z0-9]", "", u); sub("^0+(?=.)", "", u, perl = TRUE) }
P[, `:=`(own_u = unit_of(paste(OWNER_ADDRESS_LINE1, OWNER_ADDRESS_LINE2)), sit_u = unit_of(SITUS_ADDRESS_LINE1))]
P[owner_occ & type %in% c("Condominium unit", "Rowhouse / townhouse") & own_u != "" & sit_u != "" & own_u != sit_u, owner_occ := FALSE]
# a duplex or triplex has one door (house number) per unit, but only one goes on the parcel record: an owner mailed at the other door
# (same street and ZIP, same side of the street, house number within 4) lives in the building
hnum <- function(k) suppressWarnings(as.integer(sub(" .*", "", k))); hstreet <- function(k) sub("^[^ ]* ?", "", k)
P[type == "Duplex / triplex" & !owner_occ & own_zip != "" & own_zip == sit_zip & hstreet(sit_k) != "" & hstreet(own_k) == hstreet(sit_k) &
  !is.na(hnum(own_k)) & !is.na(hnum(sit_k)) & abs(hnum(own_k) - hnum(sit_k)) <= 4 & hnum(own_k) %% 2L == hnum(sit_k) %% 2L, owner_occ := TRUE]
message(sprintf("owner-occupancy: %d condominium/rowhouse parcels mailed to another unit now rentals; %d duplex/triplex parcels mailed to the other door now owner-occupied",
                sum(occ0 & !P$owner_occ), sum(!occ0 & P$owner_occ)))
P[, rental_units := fifelse(owner_occ, pmax(units - 1, 0), units)]
P[, out_of_state := !(toupper(trimws(OWNER_STATE)) %in% c("CO", "COLORADO", ""))]
# ---------------------------------------------------------------- owner type and owner groups
nm <- toupper(trimws(P$OWNER_NAME))
P[, owner_type := fcase(
  grepl("CITY (AND|&) COUNTY OF DENVER|^CITY OF |STATE OF COLORADO|UNITED STATES|U S A$|HOUSING AUTH|DENVER HOUSING|SCHOOL DIST|REGIONAL TRANSPORTATION|URBAN RENEWAL|COUNTY OF |DEPARTMENT OF|BOARD OF", nm), "Public",
  grepl("CHURCH|PARISH|DIOCESE|ARCHBISHOP|CONGREGATION|MINISTR|HABITAT FOR HUMANITY|NONPROFIT|NON-PROFIT|COMMUNITY LAND TRUST|MERCY HOUSING|CATHOLIC|SALVATION ARMY|VOLUNTEERS OF AMERICA|COALITION FOR THE HOMELESS", nm), "Non-profit or religious",
  grepl("\\bL ?L ?C\\b|\\bINC\\b|\\bCORP|\\bL ?P\\b|\\bLLLP\\b|\\bLTD\\b|COMPANY|\\bCO\\b$|PARTNERS|HOLDING|PROPERT|INVEST|APARTMENT|CAPITAL|\\bFUND|\\bREIT\\b|BORROWER|VENTURE|ENTERPRISE|GROUP|ASSOCIATES|REALTY|HOMES\\b|RENTAL|MANAGEMENT|\\bBANK\\b|ASSOCIATION|\\bASSN\\b|SERIES", nm), "Company",
  grepl("TRUST|TRUSTEE|\\bTR\\b|REVOCABLE|LIVING", nm), "Trust", default = "Individual")]
# ---------------------------------------------------------------- linking owners, in stages (after Hangen & O'Brien 2025; An et al. 2024)
# S1 raw: the Assessor's owner name and mailing address exactly as recorded.
# S2 cleaned: names cleaned (punctuation, number words to numerals, spelling variants of legal forms, legal suffixes dropped) and
#    addresses normalised (directions, street types, suite/unit and PO box spellings). Companies are identified by cleaned name alone;
#    individuals and trusts by cleaned name and mailing address (two "John Smiths" at different addresses are two people).
# S3 fuzzy: near-identical name + address strings (3-gram cosine similarity >= 0.85, within the same mailing ZIP and name initial)
#    are joined when the names alone are also near-identical (similarity >= 0.85: a shared servicer address must not carry two
#    different names over the line), unless their numbers (also those inside words, as in "UNIT4B"), generational suffixes (Jr, Sr,
#    II) or middle initials differ.
# S4 families: S3 owners sharing a mailing address are joined (private owners only; not at addresses shared by more than 5
#    individuals or 40 names, or PO boxes used by more than 5 names, unless the address is on the audited list
#    data/raw/ownership/audited_addresses.csv, stored as hashes: address-named LLCs of one operator, checked by hand).
# S5 registry (when work/registry/co_business_entities.csv exists, from R/fetch_landlord_data.R): company owners are matched by cleaned
#    name to the Colorado Secretary of State business registry, and families are joined when their entities share a principal
#    address or an individual registered agent. Registered-agent firms, and agents or addresses serving more than 10 (agents) or 25
#    (addresses) registry entities, or more than 20 Denver owner families, are never used as links (they would chain unrelated owners).
for (p in c("Matrix", "igraph", "digest")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
NUMW <- c(ONE = 1, TWO = 2, THREE = 3, FOUR = 4, FIVE = 5, SIX = 6, SEVEN = 7, EIGHT = 8, NINE = 9, TEN = 10, ELEVEN = 11, TWELVE = 12, THIRTEEN = 13,
          FOURTEEN = 14, FIFTEEN = 15, SIXTEEN = 16, SEVENTEEN = 17, EIGHTEEN = 18, NINETEEN = 19, TWENTY = 20, THIRTY = 30, FORTY = 40, FIFTY = 50)
nm_clean <- function(x) { x <- toupper(ifelse(is.na(x), "", x)); x <- gsub("[.,']", "", x); x <- gsub("[^A-Z0-9& ]", " ", x)
  for (w in names(NUMW)) x <- gsub(paste0("\\b", w, "\\b"), NUMW[[w]], x)
  x <- gsub("\\bAND\\b", "&", x)
  x <- gsub("\\bLIMITED LIABILITY (COMPANY|CO)\\b|\\bL L C\\b|\\bL\\s?L\\s?C\\b", "LLC", x)
  x <- gsub("\\bL L L P\\b|\\bLLLP\\b", "LLLP", x); x <- gsub("\\bLIMITED PARTNERSHIP\\b|\\bL P\\b", "LP", x)
  x <- gsub("\\bINCORPORATED\\b|\\bINCORPORATION\\b", "INC", x)
  x <- gsub("\\bCORPORATION\\b|\\bCORPORATON\\b|\\bCORPORAITON\\b|\\bCORPRATION\\b|\\bCORPORTION\\b|\\bCRP\\b|\\bCP\\b", "CORP", x)
  x <- gsub("\\bCOMPANY\\b|\\bCOMPNAY\\b|\\bCOMAPNY\\b", "CO", x)
  x <- gsub("\\bPROPERTIES\\b|\\bPROPERTYS\\b|\\bPROPS?\\b", "PROPERTY", x); x <- gsub("\\bHOLDINGS\\b", "HOLDING", x)
  x <- gsub("\\bINVESTMENTS\\b", "INVESTMENT", x); x <- gsub("\\bASSOCIATES\\b|\\bASSOCS?\\b", "ASSOC", x); x <- gsub("\\bPARTNERS\\b|\\bPARTNERSHIP\\b", "PARTNER", x)
  gsub("\\s+", " ", trimws(x)) }
nm_norm <- function(x) { x <- nm_clean(x)
  x <- gsub("\\b(LLC|LLLP|LP|INC|CORP|CO|LTD|THE|TRUST|TRUSTEE|TRUSTEES|TR|ET AL|ETAL|REVOCABLE|LIVING|SERIES [A-Z0-9]+)\\b", " ", x)
  gsub("\\s+", " ", trimws(x)) }
STT <- c(STREET = "ST", AVENUE = "AVE", AV = "AVE", BOULEVARD = "BLVD", PLACE = "PL", DRIVE = "DR", COURT = "CT", LANE = "LN", ROAD = "RD", PARKWAY = "PKWY",
         CIRCLE = "CIR", TERRACE = "TER", HIGHWAY = "HWY", NORTH = "N", SOUTH = "S", EAST = "E", WEST = "W", SUITE = "STE", APARTMENT = "UNIT", APT = "UNIT", NUMBER = "UNIT")
addr_norm <- function(line, zip) { x <- toupper(ifelse(is.na(line), "", line)); x <- gsub("[.,']", "", x)
  x <- gsub("\\bP\\s?O\\s?(BOX|BX|DRAWER)\\b|\\bPOST OFFICE BOX\\b|^BOX\\b|\\bPOB\\b", " POBOX ", x); x <- gsub("#", " UNIT ", x)
  x <- gsub("[^A-Z0-9 ]", " ", x); for (w in names(STT)) x <- gsub(paste0("\\b", w, "\\b"), STT[[w]], x)
  x <- gsub("\\b(UNIT|STE) (UNIT|STE)\\b", "\\1", x); x <- gsub("\\s+", " ", trimws(x))
  z <- substr(gsub("\\D", "", ifelse(is.na(zip), "", zip)), 1, 5); fifelse(x == "", NA_character_, paste(x, z)) }
P[, raw_key := paste(gsub("\\s+", " ", toupper(trimws(OWNER_NAME))), "|", gsub("\\s+", " ", toupper(trimws(paste(OWNER_ADDRESS_LINE1, OWNER_ADDRESS_LINE2)))), own_zip)]
P[!nzchar(trimws(OWNER_NAME)), `:=`(raw_key = paste0("blank_", SCHEDNUM), owner_type = "Unknown (no name recorded)")]
P[, `:=`(name_key = nm_norm(OWNER_NAME), addr_n = addr_norm(paste(OWNER_ADDRESS_LINE1, OWNER_ADDRESS_LINE2), OWNER_ZIP))]
P[name_key == "", name_key := paste0("blank_", SCHEDNUM)]
P[, po_box := grepl("POBOX", addr_n)]
P[, addr_key := addr_n]
P[, s2_key := fifelse(owner_type %in% c("Individual", "Trust"), paste(name_key, "@", fifelse(is.na(addr_n), "", addr_n)), name_key)]
P[, g_raw := .GRP, by = raw_key]; P[, g_clean := .GRP, by = s2_key]
# S3: fuzzy joins between S2 owners
K <- unique(P[owner_type %in% c("Company", "Trust", "Individual") & !grepl("^blank_", name_key), .(s2_key, name_key, addr_n, own_zip, owner_type)], by = "s2_key")
K[, str := paste(name_key, fifelse(is.na(addr_n), "", addr_n))][, blk := paste(own_zip, substr(name_key, 1, 2))]
qg <- function(s) { s <- paste0(" ", s, " "); n <- nchar(s); substring(s, 1:(n - 2), 3:n) }
fuzzy_pairs <- function(d) { if (nrow(d) < 2) return(NULL)
  g <- lapply(d$str, qg); ug <- unique(unlist(g)); M <- Matrix::sparseMatrix(i = rep(seq_along(g), lengths(g)), j = match(unlist(g), ug), x = 1, dims = c(length(g), length(ug)))
  M <- Matrix::Diagonal(x = 1 / sqrt(Matrix::rowSums(M^2))) %*% M; S <- Matrix::triu(Matrix::tcrossprod(M), k = 1)
  S <- Matrix::summary(as(S, "TsparseMatrix")); S <- S[S$x >= 0.85, , drop = FALSE]; if (!nrow(S)) return(NULL)
  data.table(a = d$s2_key[S$i], b = d$s2_key[S$j], na = d$name_key[S$i], nb = d$name_key[S$j]) }
# 3-gram cosine similarity of two names on their own (the same measure as above, pair by pair)
qsim <- function(a, b) mapply(function(x, y) { gx <- table(qg(x)); gy <- table(qg(y)); k <- intersect(names(gx), names(gy))
  sum(gx[k] * gy[k]) / sqrt(sum(gx^2) * sum(gy^2)) }, a, b, USE.NAMES = FALSE)
sp <- split(K, by = "blk"); big <- vapply(sp, nrow, 1L) > 4000
if (any(big)) sp <- c(sp[!big], unlist(lapply(sp[big], function(d) split(d, by = substr(d$name_key, 1, 4))), recursive = FALSE))
FZ <- rbindlist(lapply(sp, fuzzy_pairs))
if (nrow(FZ)) {
  FZ <- FZ[qsim(na, nb) >= 0.85]
  tk <- function(s, f) vapply(strsplit(s, " "), function(t) paste(sort(t[f(t)]), collapse = " "), "")
  # every run of digits in the name, also when attached to letters ("UNIT4B", "2ND"), so 123 MAIN LLC and 124 MAIN LLC stay apart
  dg <- function(s) vapply(regmatches(s, gregexpr("[0-9]+", s)), function(t) paste(sort(t), collapse = " "), "")
  gen_t <- function(t) t %in% c("JR", "SR", "II", "III", "IV"); ini_t <- function(t) nchar(t) == 1 & !grepl("[0-9&]", t)
  FZ <- FZ[dg(na) == dg(nb) & tk(na, gen_t) == tk(nb, gen_t) & (tk(na, ini_t) == tk(nb, ini_t) | tk(na, ini_t) == "" | tk(nb, ini_t) == "")]
}
comp_of <- function(nodes, edges) { edges <- as.data.frame(edges); names(edges) <- c("a", "b")
  gr <- igraph::graph_from_data_frame(edges, directed = FALSE, vertices = data.frame(name = unique(c(nodes, edges$a, edges$b))))
  cm <- igraph::components(gr)$membership; unname(cm[nodes]) }
P[, g_name := comp_of(s2_key, if (nrow(FZ)) FZ[, .(a, b)] else data.frame(a = character(), b = character()))]
message(sprintf("fuzzy step: %d pairs of near-identical owner names joined", nrow(FZ)))
# S4: families by shared mailing address, skipping servicer-like addresses
AUD <- if (file.exists("data/raw/ownership/audited_addresses.csv")) fread("data/raw/ownership/audited_addresses.csv")$addr_md5 else character(0)
ua <- unique(fifelse(is.na(P$addr_key), "", P$addr_key)); P[, addr_md5 := vapply(ua, function(a) digest::digest(a, algo = "md5", serialize = FALSE), "")[match(fifelse(is.na(addr_key), "", addr_key), ua)]]
P[, `:=`(indiv_names_at_addr = uniqueN(g_name[owner_type == "Individual"]), names_at_addr = uniqueN(g_name)), by = addr_key]
# link by address only for private landlords: never public or non-profit owners, never owner-occupiers, and not at addresses shared by
# more than 5 different individuals or more than 40 different names (tax servicers, registered agents), nor PO boxes used by more than
# 5 names (tax-bill processing boxes serve several unrelated investors), unless audited
P[, link_addr := !is.na(addr_key) & (addr_md5 %in% AUD | (indiv_names_at_addr <= 5 & names_at_addr <= 40 & (!po_box | names_at_addr <= 5))) & !owner_occ & owner_type %in% c("Company", "Trust", "Individual")]
P[, g_family := comp_of(paste0("n", g_name), rbind(data.frame(a = character(), b = character()),
                                                     unique(P[link_addr == TRUE, .(a = paste0("n", g_name), b = paste0("a", addr_key))])))]
# S5: the Colorado business registry
REG_F <- "work/registry/co_business_entities.csv"; P[, g_registry := g_family]; HAVE_REG <- file.exists(REG_F)
rough_addr <- function(a, z) { k <- gsub("[^A-Z0-9]", "", toupper(ifelse(is.na(a), "", a))); fifelse(k == "", NA_character_, paste0(k, "_", substr(gsub("\\D", "", ifelse(is.na(z), "", z)), 1, 5))) }
if (HAVE_REG) {
  R0 <- fread(REG_F, colClasses = "character")
  R0[, ra := rough_addr(paste(principaladdress1, principaladdress2), principalzipcode)]
  R0[, agent := fifelse(nzchar(agentlastname) & !nzchar(agentorganizationname), gsub("\\s+", " ", toupper(trimws(paste(agentfirstname, agentlastname)))), NA_character_)]
  agent_office <- unique(R0[nzchar(agentorganizationname), rough_addr(agentprincipaladdress1, agentprincipalzipcode)])
  ra_n <- R0[!is.na(ra), .N, by = ra]; ag_n <- R0[!is.na(agent), .N, by = agent]
  ok_ra <- setdiff(ra_n[N <= 25, ra], agent_office); ok_ag <- ag_n[N <= 10, agent]
  ft <- function(x) sub(" .*", "", toupper(trimws(x))); comp_first <- unique(ft(P[owner_type == "Company", OWNER_NAME]))
  R1 <- R0[ft(entityname) %in% comp_first]; R1[, name_key := nm_norm(entityname)]
  M1 <- merge(unique(P[owner_type == "Company", .(name_key, g_family)]), R1[, .(name_key, ra, agent)], by = "name_key", allow.cartesian = TRUE)
  P[, ra_own := rough_addr(paste(OWNER_ADDRESS_LINE1, OWNER_ADDRESS_LINE2), OWNER_ZIP)]
  EK <- unique(rbind(M1[ra %in% ok_ra, .(f = g_family, k = paste0("ra:", ra))], M1[agent %in% ok_ag, .(f = g_family, k = paste0("ag:", agent))],
                     P[link_addr == TRUE & ra_own %in% ok_ra & ra_own %in% M1$ra, .(f = g_family, k = paste0("ra:", ra_own))]))
  EK <- EK[, if (uniqueN(f) <= 20) .SD, by = k]                                         # no key may join more than 20 Denver owner families
  EK <- EK[, if (uniqueN(f) >= 2) .SD, by = k]
  fam <- unique(P$g_family); cm <- comp_of(paste0("f", fam), EK[, .(paste0("f", f), k)]); P[, g_registry := cm[match(g_family, fam)]]
  # a chain of links can still snowball: components joining more than 30 families fall back to their families
  big <- P[, .(nf = uniqueN(g_family)), by = g_registry][nf > 30, g_registry]
  P[g_registry %in% big, g_registry := max(cm) + g_family]
  message(sprintf("registry: %d Denver company owner names found in the registry (of %d); %d linking keys; %d families -> %d (%d chains of 30+ families left unlinked)",
                  uniqueN(M1$name_key), uniqueN(P[owner_type == "Company", name_key]), uniqueN(EK$k), uniqueN(P$g_family), uniqueN(P$g_registry), length(big)))
  RL <- P[rental_units > 0, .(families = uniqueN(g_family), rental = sum(rental_units), names = paste(head(unique(OWNER_NAME), 6), collapse = " | ")), by = g_registry][families > 1][order(-rental)]
  fwrite(RL, file.path(D, "registry_links_private.csv"))                                  # for checking by hand; never published
  rm(R0, R1); invisible(gc())
}
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
conc <- function(G, label, priv = TRUE) { G <- if (priv) G[!type %in% c("Public", "Unknown (no name recorded)")] else G; G <- G[order(-rental)]; tot <- sum(G$rental); n <- nrow(G)
  data.table(grouping = label, owners = n, rental_units = tot,
             top10_pct = round(100 * sum(head(G$rental, 10)) / tot, 1), top50_pct = round(100 * sum(head(G$rental, 50)) / tot, 1), top100_pct = round(100 * sum(head(G$rental, 100)) / tot, 1),
             top1pct_owners_pct = round(100 * sum(head(G$rental, ceiling(n / 100))) / tot, 1), owners_20plus_pct = round(100 * sum(G$rental[G$rental >= 20]) / tot, 1),
             owners_100plus_pct = round(100 * sum(G$rental[G$rental >= 100]) / tot, 1), hhi = round(10000 * sum((G$rental / tot)^2), 1)) }
SFR_TYPES <- c("Single-family house", "Condominium unit", "Rowhouse / townhouse", "Duplex / triplex")
GS <- P[rental_units > 0 & type %in% SFR_TYPES, .(rental = sum(rental_units), type = owner_type[which.max(rental_units)]), by = g_family]
CONC <- rbind(conc(SN$G, "Private owners, by name"), conc(SF$G, "Private owners, by family"), conc(GS, "Private owners, by family: houses, condos, rowhouses, duplexes only"))
# how much linking reveals: concentration at each stage (Hangen & O'Brien 2025)
gtab <- function(gcol) P[rental_units > 0, .(rental = sum(rental_units), type = owner_type[which.max(rental_units)]), by = c(gcol)]
LADDER <- rbindlist(list(conc(gtab("g_raw"), "S1 raw name and mailing address, exact"), conc(gtab("g_clean"), "S2 cleaned names and addresses"),
                         conc(gtab("g_name"), "S3 + near-identical names (fuzzy)"), conc(gtab("g_family"), "S4 + shared mailing address (owner families)"),
                         if (HAVE_REG) conc(gtab("g_registry"), "S5 + Colorado business registry (principal address, individual agent)")))
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
# check against the 2020 census: owner-occupied share of units by tract (Assessor) vs owner-occupied share of occupied units (census)
VAL <- BY_TR[!is.na(p_owner) & units >= 100, .(tracts = .N, assessor_owner_occupied = round(100 - weighted.mean(pct_rental, units), 1),
                                              census_owner_occupied = round(weighted.mean(p_owner, units), 1), correlation = round(cor(100 - pct_rental, p_owner), 2))]
fwrite(VAL, file.path(O, "validation_census_tenure.csv")); print(VAL)
# who lives where large landlords own: tract-level association, weighted by rental units (tracts with 50+ rental units)
TRM <- BY_TR[rental_units >= 50 & !is.na(p_black) & !is.na(p_pov)]
TRM[, `:=`(any_hidden = as.numeric(hidden_1965_92 > 0), any_known = as.numeric(known_1965_92 > 0), lrent = log(pmax(mrent_2020, 1)))]
ass <- function(yv) { f <- as.formula(paste(yv, "~ p_black + p_hisp + p_pov + any_hidden + any_known")); m <- lm(f, data = TRM, weights = rental_units)
  ct <- summary(m)$coefficients[-1, , drop = FALSE]
  data.table(outcome = yv, term = rownames(ct), estimate = round(ct[, 1], 3), se = round(ct[, 2], 3), p = signif(ct[, 4], 3), tracts = nobs(m)) }
ASSOC <- rbindlist(lapply(c("pct_rental_owner_20plus", "pct_rental_owner_100plus", "pct_rental_company", "pct_rental_out_of_state"), ass))
ASSOC[, term := c(p_black = "Black residents (per point of %)", p_hisp = "Hispanic residents (per point of %)", p_pov = "Poverty rate (per point of %)",
                  any_hidden = "Tract has a hidden 1965-92 site", any_known = "Tract has a known 1965-92 site")[term]]
# ---------------------------------------------------------------- where landlords live (Preis 2024; Hochstenbach 2022)
# From the owner's mailing ZIP: on the property, elsewhere in Denver, the metro (ZIP centre within 40 km of downtown), elsewhere in
# Colorado, another state. Distance from the property's ZIP centre to the mailing ZIP centre, and the two ZIPs' median household income
# and non-Hispanic white share (ACS 5-year, ZCTAs; R/fetch_landlord_data.R). Mailing addresses can be a manager's or a tax agent's office
# rather than where the owner lives; PO boxes are flagged.
ZA <- "data/raw/acs/zcta_acs.csv"; ZGF <- "data/raw/acs/zcta_gazetteer_2020.csv"; LOC <- NULL
if (file.exists(ZA) && file.exists(ZGF)) {
  za <- fread(ZA, colClasses = c(zcta = "character")); zg <- fread(ZGF, colClasses = c(zcta = "character"))
  hav <- function(a1, o1, a2, o2) { r <- pi / 180; 6371 * 2 * asin(sqrt(sin((a2 - a1) * r / 2)^2 + cos(a1 * r) * cos(a2 * r) * sin((o2 - o1) * r / 2)^2)) }
  wmed <- function(x, w) { k <- !is.na(x) & !is.na(w); x <- x[k]; w <- w[k]; if (!length(x)) return(NA_real_); o <- order(x); x[o][which(cumsum(w[o]) >= sum(w) / 2)[1]] }
  den_zips <- unique(P$sit_zip[nzchar(P$sit_zip)])
  L <- Q[rental_units > 0 & !owner_type %in% c("Public", "Unknown (no name recorded)")]
  L <- merge(L, zg[, .(own_zip = zcta, olat = lat, olon = lon)], by = "own_zip", all.x = TRUE)
  L <- merge(L, zg[, .(sit_zip = zcta, slat = lat, slon = lon)], by = "sit_zip", all.x = TRUE)
  L <- merge(L, za[, .(own_zip = zcta, o_inc = med_hh_income, o_white = pct_white_nh)], by = "own_zip", all.x = TRUE)
  L <- merge(L, za[, .(sit_zip = zcta, s_inc = med_hh_income, s_white = pct_white_nh)], by = "sit_zip", all.x = TRUE)
  L[, `:=`(d_km = hav(slat, slon, olat, olon), d_den = hav(39.7392, -104.9903, olat, olon), co = toupper(trimws(OWNER_STATE)) %in% c("CO", "COLORADO"))]
  L[, where := fcase(owner_occ, "Lives on the property", co & own_zip %in% den_zips & toupper(trimws(OWNER_CITY)) == "DENVER", "Elsewhere in Denver",
                     co & !is.na(d_den) & d_den <= 40, "Denver metro (within 40 km)", co, "Elsewhere in Colorado", !co & !is.na(olat), "Another state", default = "Unknown or abroad")]
  L[, `:=`(size = band(fam_rental), absent = !owner_occ)]
  WHERE <- c("Lives on the property", "Elsewhere in Denver", "Denver metro (within 40 km)", "Elsewhere in Colorado", "Another state", "Unknown or abroad")
  locs <- function(d) { a <- d[absent == TRUE]; tot <- sum(d$rental_units)
    w <- lapply(WHERE, function(k) round(100 * sum(d$rental_units[d$where == k]) / tot, 1)); names(w) <- paste0("pct_", gsub("_$", "", gsub("[^a-z0-9]+", "_", tolower(WHERE))))
    c(list(rental_units = tot), w, list(
      median_km_to_owner = round(wmed(a$d_km, a$rental_units), 1),
      pct_po_box = round(100 * sum(a$rental_units[a$po_box]) / max(1, sum(a$rental_units)), 1),
      owner_zip_income = round(weighted.mean(a$o_inc, a$rental_units, na.rm = TRUE)), property_zip_income = round(weighted.mean(a$s_inc, a$rental_units, na.rm = TRUE)),
      pct_owner_zip_richer_25 = round(100 * sum(a$rental_units[!is.na(a$o_inc) & !is.na(a$s_inc) & a$o_inc > 1.25 * a$s_inc]) / max(1, sum(a$rental_units[!is.na(a$o_inc) & !is.na(a$s_inc)])), 1),
      owner_zip_pct_white = round(weighted.mean(a$o_white, a$rental_units, na.rm = TRUE), 1), property_zip_pct_white = round(weighted.mean(a$s_white, a$rental_units, na.rm = TRUE), 1))) }
  LOC <- rbindlist(list(
    L[, locs(.SD)][, `:=`(group = "All private rental units", value = "all")],
    L[, locs(.SD), by = .(value = as.character(size))][, group := "Owner family size (rental units in Denver)"],
    L[, locs(.SD), by = .(value = owner_type)][, group := "Owner type"],
    L[, locs(.SD), by = .(value = holc)][, group := "1938 HOLC grade"],
    L[near_hidden == TRUE, locs(.SD)][, `:=`(group = "Historical sites", value = "Within 400 m of a hidden site")],
    L[near_known == TRUE, locs(.SD)][, `:=`(group = "Historical sites", value = "Within 400 m of a known site")],
    L[near_pre1960 == TRUE, locs(.SD)][, `:=`(group = "Historical sites", value = "Within 400 m of a pre-1960 hazardous trade")],
    L[!near_hidden & !near_known & !near_pre1960, locs(.SD)][, `:=`(group = "Historical sites", value = "More than 400 m from any")]), fill = TRUE)
  setcolorder(LOC, c("group", "value")); LOC <- LOC[order(group, value)]
  print(LOC)
} else message("owner location skipped: run Rscript R/fetch_landlord_data.R for ", ZA, " and ", ZGF)
# ---------------------------------------------------------------- write (aggregates only) and the private check list
TOP <- SF$G[order(-rental)][1:min(.N, 100)]
TOP[, example_names := vapply(g_family, function(gf) paste(head(unique(P[g_family == gf & rental_units > 0, OWNER_NAME]), 4), collapse = " | "), "")]
fwrite(TOP, file.path(D, "top_owners_private.csv"))
fwrite(P[, .(SCHEDNUM, owner_type, out_of_state, owner_occ, po_box, units, rental_units, type, g_name, g_family, g_registry)], file.path(D, "parcel_owner_groups_private.csv"))
for (nm_ in c("SIZE", "CONC", "TYPE", "OCC", "BY_HOLC", "BY_SITE", "BY_TYPE_SITE", "BY_TR", "ASSOC", "LADDER", if (!is.null(LOC)) "LOC")) {
  f <- c(SIZE = "owner_size", CONC = "concentration", TYPE = "owner_types", OCC = "occupancy_by_type", BY_HOLC = "by_holc", BY_SITE = "by_site_proximity",
         BY_TYPE_SITE = "by_site_proximity_small_buildings", BY_TR = "by_tract", ASSOC = "tract_associations", LADDER = "linking_stages", LOC = "owner_location")[[nm_]]
  fwrite(get(nm_), file.path(O, paste0(f, ".csv"))); fwrite(get(nm_), file.path(A, paste0("ownership_", f, ".csv"))) }
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
writeLines(c("# Who owns Denver's rental housing", "", sprintf("%s residential parcels, %s units, %s not occupied by their owner. Aggregates only.",
               format(nrow(P), big.mark = ","), format(sum(P$units), big.mark = ","), format(sum(P$rental_units), big.mark = ",")), "",
             "## Occupancy by property type", "", kab(OCC), "", "## Owner types", "", kab(TYPE), "", "## Owners by size", "", kab(SIZE), "", "## Concentration", "", kab(CONC), "", "## Concentration at each linking stage", "", kab(LADDER), "", if (!is.null(LOC)) c("## Where owners are (mailing address)", "", kab(LOC), ""),
             "## By 1938 HOLC grade", "", kab(BY_HOLC), "", "## Near historical sites", "", kab(BY_SITE), "", kab(BY_TYPE_SITE), "",
             "## Tract associations (weighted by rental units; tracts with 50+ rental units)", "", kab(ASSOC)), file.path(O, "ownership_summary.md"))
print(OCC); print(TYPE); print(SIZE); print(CONC); print(LADDER); print(BY_HOLC); print(BY_SITE); print(ASSOC)
message("wrote ", O, "; the largest owners (names) are in ", file.path(D, "top_owners_private.csv"), " and are not published")
