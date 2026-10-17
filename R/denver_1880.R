# Denver 1880: who lived next to the hazardous trades? Building-level residents (Brown University Urban Transition HGIS, 1880
# full-count census geocoded to buildings) against the hazardous-trade firms in the 1878-1885 Colorado State Business Directories.
#   Rscript R/denver_1880.R      -> data/results/denver_1880/*.csv, denver_1880_summary.md
# Inputs (not redistributed; Brown's conditions of use apply): work/census/brown/{ed1880,street1880,singleunit1880,multiunit1880}/*.shp
#   and work/census/brown/UTPalldat/UTP all dat/UTP matched to NAPP.dat ; data/historical/CO_pre1960_hazardous_listings.csv.
# The directory firms are placed by matching their printed 1880-era addresses ("323 Holladay") to Brown's geocoded buildings and
# street segments, which use the same pre-1887 numbering - so this does not depend on today's street grid.
suppressPackageStartupMessages({ library(sf); library(data.table); library(sandwich); library(lmtest) })
sf_use_s2(FALSE); UTM <- 26913; B <- "work/census/brown"; O <- "data/results/denver_1880"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
bf <- function(f) { p <- c(file.path(B, f), file.path(B, basename(f)), file.path(B, "UTP all dat", basename(f))); p <- p[file.exists(p)]; if (!length(p)) stop("missing Brown file: ", f); p[1] }   # zips unpacked into subfolders or flat
rd <- function(p) st_transform(st_read(bf(p), quiet = TRUE), UTM)
bld <- rbind(rd("singleunit1880/singleunit1880.shp")[, c("Match_addr", "address", "enumdist", "poptotB")],
             rd("multiunit1880/multiunit1880.shp")[, c("Match_addr", "address", "enumdist", "poptotB")])
bld <- bld[grepl("Denver, CO", bld$Match_addr), ]; bxy <- st_coordinates(bld)
seg <- rd("street1880/street1880.shp"); seg <- seg[seg$city == "Denver", c("Street", "Type", "Segment_id")]
ed <- rd("ed1880/ed1880.shp"); ed <- ed[grepl("Denver", ed$CityName), ]
message("Denver 1880: ", nrow(bld), " geocoded buildings, ", nrow(seg), " street segments, ", nrow(ed), " EDs")

# ---------------------------------------------------------------- residents
P <- fread(bf("UTPalldat/UTP all dat/UTP matched to NAPP.dat"), sep = "\t", encoding = "Latin-1", quote = "")
setnames(P, 1, "mergeID"); P <- P[citynameB == "DENVER"]
P[, racenameB := tolower(trimws(racenameB))]; P[, seiusB := suppressWarnings(as.numeric(seiusB))]
# occlabelB is an undocumented occupation-string id; the Duncan SEI (seiusB) is documented: 0 = no occupation, 8 = laborers n.e.c.
P[, `:=`(fb = nativityB == 5, black = racenameB %in% c("black", "mulatto"), chinese = racenameB == "chinese",
         german = BPLB %in% c("Germany", "Prussia", "Bavaria", "Austria"), irish = BPLB == "Ireland", british = BPLB %in% c("England", "Scotland", "Wales"),
         scandinavian = BPLB %in% c("Sweden", "Norway", "Denmark"), canadian = BPLB == "Canada", white = racenameB == "white",
         native_white = racenameB == "white" & nativityB != 5, other_fb = nativityB == 5 & !(BPLB %in% c("Germany", "Prussia", "Bavaria", "Austria", "Ireland", "England", "Scotland", "Wales", "Sweden", "Norway", "Denmark", "Canada", "China")), laborer = !is.na(seiusB) & seiusB == 8, employed = !is.na(seiusB) & seiusB > 0, sei = ifelse(!is.na(seiusB) & seiusB > 0, seiusB, NA_real_),
         adult = !is.na(suppressWarnings(as.numeric(ageB))) & suppressWarnings(as.numeric(ageB)) >= 18)]
P <- merge(P, data.table(match_addrB = bld$Match_addr, x = bxy[, 1], y = bxy[, 2], ed = bld$enumdist), by = "match_addrB")
message(nrow(P), " Denver residents at geocoded buildings; foreign born ", round(100 * mean(P$fb), 1), "%, Black ", round(100 * mean(P$black), 1), "%, Chinese ", round(100 * mean(P$chinese), 1), "%"); print(head(sort(table(P$racenameB), decreasing = TRUE), 8)); print(head(sort(table(P$BPLB), decreasing = TRUE), 12))

# ---------------------------------------------------------------- directory firms 1878-1885, placed on Brown's 1880 geography
L <- fread("data/historical/CO_pre1960_hazardous_listings.csv")[town == "DENVER" & year >= 1878 & year <= 1885 & !is.na(street) & street != ""]
norm <- function(s) { s <- toupper(s); s <- gsub("\\.", "", s); s <- gsub("\\b(STREET|ST|AVENUE|AVE|AV)\\b", "", s); trimws(gsub("\\s+", " ", s)) }
ALIAS <- c("HOLL" = "HOLLADAY", "LAR" = "LARIMER", "LAWR" = "LAWRENCE", "ARAP" = "ARAPAHOE", "CAL" = "CALIFORNIA", "CHAMP" = "CHAMPA", "WAZ" = "WAZEE", "BL" = "BLAKE", "CURT" = "CURTIS")
L[, num := as.integer(sub("^(\\d+).*", "\\1", street))]; L[, sname := norm(sub("^\\d+\\s*", "", street))]
L[, sname := ifelse(sname %in% names(ALIAS), ALIAS[sname], sname)]; L[, sname := sub("^([0-9]+)(ST|ND|RD|TH)$", "\\1", sname)]
bld$num <- as.integer(sub("^(\\d+).*", "\\1", bld$address)); bld$sname <- norm(sub("^\\d+\\s*", "", bld$address)); bld$sname <- sub("^([0-9]+)(ST|ND|RD|TH)$", "\\1", bld$sname)
seg$sname <- norm(seg$Street); seg$sname <- sub("^([0-9]+)(ST|ND|RD|TH)$", "\\1", seg$sname)
bt <- data.table(i = seq_len(nrow(bld)), num = bld$num, sname = bld$sname, x = bxy[, 1], y = bxy[, 2])
place <- function(num0, sname0) {
  c1 <- bt[sname == sname0 & !is.na(num) & num == num0]; if (nrow(c1)) return(c(c1$x[1], c1$y[1], 1))
  c2 <- bt[sname == sname0 & !is.na(num)]; if (nrow(c2) && !is.na(num0)) { dd <- abs(c2$num - num0); if (min(dd) <= 30) { k <- which.min(dd); return(c(c2$x[k], c2$y[k], 2)) } }
  s <- seg[seg$sname == sname0, ]; if (nrow(s)) { ctr <- st_coordinates(st_centroid(st_union(s))); return(c(ctr[1], ctr[2], 3)) }
  c(NA, NA, NA)
}
pl <- t(mapply(place, L$num, L$sname)); L[, `:=`(x = pl[, 1], y = pl[, 2], how = c("building", "nearest number on street", "street only")[pl[, 3]])]
F <- L[!is.na(x)]; message(nrow(F), " of ", nrow(L), " firm listings placed: ", paste(names(table(F$how)), table(F$how), sep = " = ", collapse = ", "))
F <- unique(F, by = c("x", "y", "sector"))                       # one point per firm-site and sector
fwrite(F[, .(year, name, street, sector, how, x, y)], file.path(O, "firms_1878_1885_placed.csv"))
Fst <- F[how != "street only"]                                     # exact or near-exact placements for the distance analysis

# ---------------------------------------------------------------- residents by distance to the nearest hazardous firm
dmin <- function(px, py, fx, fy) vapply(seq_along(px), function(i) sqrt(min((fx - px[i])^2 + (fy - py[i])^2)), 0)
P[, d_haz := dmin(x, y, Fst$x, Fst$y)]
for (sec in c("Smelting & refining", "Foundry", "Iron & steel works", "Machine shop / machinery", "Metal working", "Assay office", "Manufactured gas"))
  if (sum(Fst$sector == sec) >= 2) P[[paste0("d_", gsub("[^a-z]", "", tolower(sec)))]] <- dmin(P$x, P$y, Fst[sector == sec]$x, Fst[sector == sec]$y)
P[, band := cut(d_haz, c(-1, 100, 250, 500, 1e9), c("< 100 m", "100-250 m", "250-500 m", "> 500 m"))]
comp <- P[, .(residents = .N, pct_foreign_born = 100 * mean(fb), pct_german = 100 * mean(german), pct_irish = 100 * mean(irish), pct_british = 100 * mean(british),
              pct_scandinavian = 100 * mean(scandinavian), pct_black = 100 * mean(black), pct_chinese = 100 * mean(chinese),
              pct_laborers_employed = 100 * mean(laborer[adult & employed], na.rm = TRUE), mean_sei_employed = mean(sei[adult & employed], na.rm = TRUE)), by = band][order(band)]
fwrite(comp, file.path(O, "residents_by_distance.csv"))
# person-level models, building-clustered SE: log distance to the nearest hazardous firm (laborer / SEI among employed adults; SEI 0 = no occupation)
mods <- rbindlist(lapply(c("fb", "native_white", "white", "black", "chinese", "german", "irish", "british", "scandinavian", "canadian", "other_fb", "laborer"), function(v) {
  d <- if (v == "laborer") P[adult == TRUE & employed == TRUE] else P
  m <- glm(as.formula(paste(v, "~ log(d_haz + 10)")), family = binomial, data = d); ct <- coeftest(m, vcov. = vcovCL(m, cluster = d$match_addrB))
  data.table(outcome = v, odds_ratio_per_log_m = exp(ct[2, 1]), se = ct[2, 2], p = ct[2, 4], n = nrow(d)) }))
Pe <- P[adult == TRUE & employed == TRUE]; msei <- lm(sei ~ log(d_haz + 10), Pe); cs <- coeftest(msei, vcov. = vcovCL(msei, cluster = Pe$match_addrB))
mods <- rbind(mods, data.table(outcome = "sei (employed adults, linear)", odds_ratio_per_log_m = cs[2, 1], se = cs[2, 2], p = cs[2, 4], n = nobs(msei)))
fwrite(mods, file.path(O, "person_models.csv"))
# ED level: firm count vs Brown's ED composition (17 EDs - descriptive only)
edf <- st_join(st_as_sf(Fst, coords = c("x", "y"), crs = UTM), ed[, c("ED")], join = st_within); edc <- as.data.table(st_drop_geometry(edf))[, .(firms = .N), by = ED]
E <- merge(as.data.table(st_drop_geometry(ed))[, .(ED, pop = poptotE, pct_fb = fbEp, pct_black = blkEp, pct_german = germanEp, pct_irish = irishEp, mean_sei = meanseiE)], edc, by = "ED", all.x = TRUE)
E[is.na(firms), firms := 0]; fwrite(E[order(-firms)], file.path(O, "ed_composition_vs_firms.csv"))
# EDs with at least one placed hazardous firm vs. none (population-weighted means of Brown's ED composition)
EG <- E[, .(EDs = .N, population = sum(pop), pct_fb = weighted.mean(pct_fb, pop), pct_black = weighted.mean(pct_black, pop), pct_german = weighted.mean(pct_german, pop),
            pct_irish = weighted.mean(pct_irish, pop), mean_sei = weighted.mean(mean_sei, pop)), by = .(group = ifelse(firms > 0, "EDs with hazardous firms", "EDs without"))]
fwrite(EG, file.path(O, "ed_groups_1880.csv")); print(EG)

md <- c("# Denver 1880: residents of the hazardous-trade neighbourhoods", "",
        sprintf("Brown's 1880 HGIS gives %s Denver residents at %s geocoded buildings (%s EDs). The 1878-1885 business directories list %s hazardous-trade firms in Denver with a street; %s were placed on the 1880 map (%s at the building or within a few house numbers, %s at the street only).",
                format(nrow(P), big.mark = ","), format(nrow(bld), big.mark = ","), nrow(ed), nrow(L), nrow(F), nrow(Fst), nrow(F) - nrow(Fst)), "",
        "## Residents by distance to the nearest hazardous-trade firm (building-level placements)", "",
        "| band | residents | % foreign born | % German | % Irish | % British | % Scandinavian | % Black | % Chinese | % laborers (employed adults) | mean SEI (employed adults) |", "|---|---|---|---|---|---|---|---|---|---|---|",
        sprintf("| %s | %d | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |", comp$band, comp$residents, comp$pct_foreign_born, comp$pct_german, comp$pct_irish, comp$pct_british, comp$pct_scandinavian, comp$pct_black, comp$pct_chinese, comp$pct_laborers_employed, comp$mean_sei_employed), "",
        "## Person-level models (odds ratio per log-metre of distance; building-clustered SE; > 1 = more common farther away)", "",
        "| outcome | OR per log m | SE | p | n |", "|---|---|---|---|---|",
        sprintf("| %s | %.3f | %.3f | %.3g | %d |", mods$outcome, mods$odds_ratio_per_log_m, mods$se, mods$p, mods$n), "",
        "## Enumeration districts: hazardous firms and composition", "", "| ED | population | firms | % foreign born | % Black | % German | % Irish | mean SEI |", "|---|---|---|---|---|---|---|---|",
        sprintf("| %s | %s | %d | %.1f | %.1f | %.1f | %.1f | %.1f |", E$ED, E$pop, E$firms, E$pct_fb, E$pct_black, E$pct_german, E$pct_irish, E$mean_sei))
writeLines(md, file.path(O, "denver_1880_summary.md")); cat(md, sep = "\n")
