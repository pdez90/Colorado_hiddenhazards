# 1880-1940 neighbourhood composition for Denver from the IPUMS USA full-count censuses, via the IPUMS API.
# Needs the same IPUMS API key as fetch_census.R AND registration for IPUMS USA (https://usa.ipums.org, "Register": one-time,
# same login; the extract is refused with "not registered for usa" until that is done).
#
#   Rscript R/fetch_ipums_fullcount.R
#
# What it does: requests the 100% census files for 1880, 1900, 1910, 1920, 1930 and 1940 (1890 was destroyed) restricted to
# Colorado, downloads them to work/ipums/ (Colorado only: ~60-250 MB per year), and aggregates every person record to
# county x enumeration district: population, Black, foreign born, foreign born by region of birth, Hispanic (IPUMS HISPAN,
# inferred before 1970), and labourers (OCC1950 970-979). Output: work/census/denver_ed_1880_1940.csv.
# Geography: enumeration districts (ENUMDIST) are the finest public geography; to map them you need the ED boundaries:
#   1880 - Brown University Urban Transition HGIS (Denver is one of the 39 cities):   https://s4.ad.brown.edu/Projects/UTP2/DPages/Default.aspx
#   1900-1940 - Brown's Geographic Reference File gives every household's street, house number and ED for 191 cities, and
#   1930/1940 ED maps and street grids for the largest cities: https://s4.ad.brown.edu/Projects/UTP2/citymaps.htm
#   Both are free but ask for your e-mail and acceptance of their conditions of use (no redistribution, scholarly use).
#   Street addresses themselves are NOT in the public IPUMS files.
if (!requireNamespace("ipumsr", quietly = TRUE)) install.packages("ipumsr")
suppressPackageStartupMessages({ library(ipumsr); library(data.table) })
key <- Sys.getenv("IPUMS_API_KEY"); if (!nzchar(key)) stop("set IPUMS_API_KEY")
set_ipums_api_key(key, overwrite = TRUE, save = FALSE)
dir.create("work/ipums", showWarnings = FALSE, recursive = TRUE); dir.create("work/census", showWarnings = FALSE, recursive = TRUE)
SAMPLES <- c("us1880e", "us1900m", "us1910m", "us1920c", "us1930d", "us1940b")        # 100% databases
VARS <- c("YEAR", "SERIAL", "PERNUM", "COUNTYICP", "CITY", "ENUMDIST", "SEX", "AGE", "RACE", "HISPAN", "BPL", "NATIVITY", "YRIMMIG", "OCC1950", "IND1950")
dat <- Sys.glob("work/ipums/*.dat.gz")
if (!length(dat)) {
  ext <- define_extract_micro("usa", description = "Colorado full count 1880-1940, ED-level composition",
    samples = SAMPLES, variables = c(list(var_spec("STATEFIP", case_selections = "08")), as.list(VARS)))
  sub <- submit_extract(ext); message("submitted IPUMS USA extract ", sub$number, " (full count, Colorado); large extracts take 10-60 min")
  sub <- wait_for_extract(sub); files <- download_extract(sub, download_dir = "work/ipums", overwrite = TRUE)
  dat <- Sys.glob("work/ipums/*.dat.gz")
}
ddi <- read_ipums_ddi(Sys.glob("work/ipums/*.xml")[1]); D <- as.data.table(read_ipums_micro(ddi, verbose = FALSE))
message(nrow(D), " person records, years ", paste(sort(unique(D$YEAR)), collapse = " "))
# region of birth from BPL (IPUMS general codes): 1-120 US and territories; 150 Canada; 200 Mexico; 210-399 other Americas;
# 400-499 Europe; 500-599 Asia; 600 Africa; 700-800 Oceania; 900+ abroad n.s. / unknown
D[, region := fcase(BPL < 150, "US", BPL == 200, "Mexico", BPL >= 150 & BPL < 400, "other Americas",
                    BPL >= 400 & BPL < 500, "Europe", BPL >= 500 & BPL < 600, "Asia", default = "other/unknown")]
D[, `:=`(fb = BPL >= 150 & BPL < 900, black = RACE == 2, hisp = HISPAN > 0 & HISPAN < 9, laborer = OCC1950 >= 970 & OCC1950 <= 979,
         foreign_parent = NATIVITY %in% 2:4)]
ED <- D[, .(pop = .N, black = sum(black), fb = sum(fb), fb_mexico = sum(region == "Mexico"), fb_europe = sum(region == "Europe"),
            fb_asia = sum(region == "Asia"), hisp = sum(hisp), foreign_parentage = sum(foreign_parent), laborers = sum(laborer),
            denver_city = mean(CITY == 1710)), by = .(YEAR, COUNTYICP, ENUMDIST)]   # IPUMS CITY 1710 = Denver, CO
# Denver flag for the ED: CITY where it is coded; otherwise the County of Denver (ICP 310, from 1902) or, in 1880/1900, Arapahoe County (ICP 50;
# the city was ~92% of the county: 1880 EDs 1-17 are the city, as in Brown's 1880 HGIS)
ED[, denver := denver_city > 0.5 | (denver_city == 0 & (COUNTYICP == 310 | (YEAR < 1910 & COUNTYICP == 50)))]
fwrite(ED, "work/census/denver_ed_1880_1940.csv")
print(ED[denver == TRUE, .(EDs = .N, pop = sum(pop), pct_black = round(100 * sum(black) / sum(pop), 1), pct_fb = round(100 * sum(fb) / sum(pop), 1),
                            pct_hisp = round(100 * sum(hisp) / sum(pop), 1)), by = YEAR])
message("wrote work/census/denver_ed_1880_1940.csv (denver = Denver city by IPUMS CITY 1710, else county 310 / Arapahoe 50 before 1902). Join to ED boundaries from Brown's Urban Transition project to map.")
