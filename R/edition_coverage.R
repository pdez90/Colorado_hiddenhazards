# Edition coverage: what each directory edition contributes and how complete our copy of it is.
#   Rscript R/edition_coverage.R   -> app/data/edition_coverage.csv (also data/results/edition_coverage.csv)
# Two series: the Colorado State Business Directory 1871-1956 (full-volume scans from CU Boulder's digital library, hazardous trades
# extracted by keyword; pipeline/historical/) and the Directory of Colorado Manufacturers 1961-2002 (page scans from CU Boulder
# Libraries, every manufacturer with a code; pipeline/). For the manufacturers' directory the number of scanned pages is the
# best guide to completeness (about 40 listings per page in every edition); the six editions flagged incomplete are the ones whose
# scans stop part-way through the geographic section or have missing pages (see the notes).
suppressPackageStartupMessages(library(data.table))
# ---- 1871-1956: business directory
H <- fread("data/historical/CO_pre1960_hazardous_listings.csv")
B <- H[, .(series = "Colorado State Business Directory", volumes = paste(sort(unique(vol)), collapse = "; "), pages = uniqueN(paste(vol, page)), listings = .N, hazardous = uniqueN(hfirm),
           street_level_pct = round(100 * mean(precision != "town"), 1), no_code_pct = NA_real_), by = year]
B[, `:=`(complete = TRUE, note = "full volume scanned (CU Boulder Libraries digital collection); only the hazardous trades are extracted, so counts are not all manufacturing")]
B[year == 1871, note := "Rocky Mountain Directory and Colorado Gazetteer 1871; full volume"]
B[year == 1950, note := "full volume; this edition uses numeric business codes, mapped directly, so more trades are captured than in the keyword-based editions"]
# ---- 1961-2002: manufacturers' directory
L <- fread("data/results/CO_directory_listings_1961-2002.csv", colClasses = c(sic = "character", naics = "character"))
M <- L[, .(series = "Directory of Colorado Manufacturers", volumes = paste(sort(unique(source_volume)), collapse = "; "), pages = uniqueN(paste(source_volume, page)), listings = .N, hazardous = uniqueN(estab_id[fe_hazard %in% c(TRUE, "True")]),
           street_level_pct = round(100 * mean(geo_level %in% c("address", "address_approx")), 1), no_code_pct = round(100 * mean(sic == "" & naics == ""), 1)), by = year]
INC <- c("1961" = "geographic section by county, pp. 2-88, with 31 pages missing (6-7, 21-23, 25, 27, 30, 37-49, 53-55, 61, 66-67, 70-71, 80, 87); pp. 37-49 cover Denver and El Paso counties",
         "1962" = "two files with 15-16 pages missing each; 7 of Denver County's 15 pages and all of Pueblo County absent",
         "1984" = "scan (file named DCM_1961_copy) ends with Denver on p. 73; all cities after Denver (Durango-Yuma) missing",
         "1985" = "part 1 has only pp. 2-10 (Berthoud-Brighton); cities before Berthoud and Broomfield-Delta (incl. Colorado Springs, Commerce City) missing; part 2 (Denver-Yuma) complete except p. 43",
         "1993" = "only part 1 received (Alamosa-Denver, pp. 3-74); all cities after Denver missing; 37% of listings carry no industry code",
         "2002" = "only part 2 received (Englewood-Woodland Park); part 1 (Agate-Denver, incl. Denver, Aurora, Boulder, Colorado Springs) missing")
M[, complete := !as.character(year) %in% names(INC)]; M[, note := ifelse(complete, "geographic section complete as scanned", INC[as.character(year)])]
E <- rbind(B, M)[order(year)]
setcolorder(E, c("series", "year", "volumes", "pages", "listings", "hazardous", "street_level_pct", "no_code_pct", "complete", "note"))
dir.create("data/results", showWarnings = FALSE); fwrite(E, "data/results/edition_coverage.csv"); fwrite(E, "app/data/edition_coverage.csv")
print(E[, .(series, year, pages, listings, hazardous, complete)])
