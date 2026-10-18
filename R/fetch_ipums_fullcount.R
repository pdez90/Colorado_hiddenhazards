# 1880-1940 neighbourhood composition for Colorado from the IPUMS USA full-count censuses, via the IPUMS API.
# Needs the same IPUMS API key as fetch_census.R AND registration for IPUMS USA (https://usa.ipums.org, "Register": one-time,
# same login; the extract is refused with "not registered for usa" until that is done).
#
#   Rscript R/fetch_ipums_fullcount.R
#
# Requests the 100% census files for 1880, 1900, 1910, 1920, 1930 and 1940 (1890 was destroyed) restricted to Colorado, downloads
# them to work/ipums/ (Colorado only, ~250 MB) and aggregates every person record to county x enumeration district (ENUMDIST, the
# finest public geography; the public files carry no addresses). If a previous download lacks any of the variables below, a new
# extract is requested automatically. Output: work/census/denver_ed_1880_1940.csv (every Colorado ED; `denver` flags the city).
# Variables (availability varies by census; the aggregation handles the gaps):
#   geography   COUNTYICP, CITY, ENUMDIST, GQ, FARM
#   people      SEX, AGE, MARST, RACE, HISPAN, BPL, MBPL, FBPL, NATIVITY, CITIZEN, YRIMMIG, MTONGUE, SPEAKENG, CHBORN (1900-10), VETSTAT
#   schooling   LIT (to 1930), SCHOOL, EDUC (1940)
#   work        OCC1950, IND1950, OCCSCORE, SEI, LABFORCE, CLASSWKR, EMPSTAT (1930-40), INCWAGE and WKSWORK1 (1940)
#   housing     OWNERSHP, MORTGAGE (1900-40), VALUEH and RENT (1930-40), RADIO (1930), NFAMS, RELATE (boarders)
#   mobility    MIGRATE5, MIGPLAC5 (1940: residence in 1935 -> who moved into a district 1935-40)
# ED boundaries: Brown's 1880 HGIS, and this project's reconstruction from Brown's address files (R/grf_eds.R).
if (!requireNamespace("ipumsr", quietly = TRUE)) install.packages("ipumsr")
suppressPackageStartupMessages({ library(ipumsr); library(data.table) })
key <- Sys.getenv("IPUMS_API_KEY"); if (!nzchar(key)) stop("set IPUMS_API_KEY")
set_ipums_api_key(key, overwrite = TRUE, save = FALSE)
dir.create("work/ipums", showWarnings = FALSE, recursive = TRUE); dir.create("work/census", showWarnings = FALSE, recursive = TRUE)
SAMPLES <- c("us1880e", "us1900m", "us1910m", "us1920c", "us1930d", "us1940b")        # 100% databases
VARS <- c("YEAR", "SERIAL", "PERNUM", "COUNTYICP", "CITY", "ENUMDIST", "GQ", "FARM", "NFAMS", "RELATE",
          "SEX", "AGE", "MARST", "RACE", "HISPAN", "BPL", "MBPL", "FBPL", "NATIVITY", "CITIZEN", "YRIMMIG", "MTONGUE", "SPEAKENG", "CHBORN", "VETSTAT",
          "LIT", "SCHOOL", "EDUC", "OCC1950", "IND1950", "OCCSCORE", "SEI", "LABFORCE", "CLASSWKR", "EMPSTAT", "INCWAGE", "WKSWORK1",
          "OWNERSHP", "MORTGAGE", "VALUEH", "RENT", "RADIO", "MIGRATE5", "MIGPLAC5")   # RADIO (1930) is not in the public full count; it is dropped automatically
# use the newest downloaded extract that has every variable; otherwise request a new one
ddis <- Sys.glob("work/ipums/*.xml"); use <- NULL
CORE_NEW <- c("OWNERSHP", "MIGRATE5", "IND1950", "SEI", "LIT", "CITIZEN")     # a download counts as complete when it has these (variables absent from every sample are dropped at request time)
for (f in rev(sort(ddis))) { v <- read_ipums_ddi(f)$var_info$var_name; if (all(CORE_NEW %in% v)) { use <- f; break } }
if (is.null(use)) {
  message("requesting a new IPUMS USA extract with ", length(VARS), " variables (previous downloads lack some)")
  vars <- VARS; sub <- NULL
  for (attempt in 1:12) {                         # the API rejects variables absent from every selected sample; drop them and retry
    ext <- define_extract_micro("usa", description = "Colorado full count 1880-1940, ED-level composition (all fields)",
      samples = SAMPLES, variables = c(list(var_spec("STATEFIP", case_selections = "08")), as.list(vars)))
    sub <- tryCatch(submit_extract(ext), error = function(e) e)
    if (!inherits(sub, "error")) break
    bad <- unique(regmatches(conditionMessage(sub), gregexpr("[A-Z0-9]+(?=: This variable is not available)", conditionMessage(sub), perl = TRUE))[[1]])
    if (!length(bad)) stop(sub); message("not in these samples, dropped: ", paste(bad, collapse = ", ")); vars <- setdiff(vars, bad) }
  if (inherits(sub, "error")) stop(sub)
  message("submitted IPUMS USA extract ", sub$number, " (full count, Colorado, ", length(vars), " variables); large extracts take 10-60 min")
  sub <- wait_for_extract(sub); files <- download_extract(sub, download_dir = "work/ipums", overwrite = TRUE)
  use <- grep("\\.xml$", files, value = TRUE)[1]; if (is.na(use)) use <- rev(sort(Sys.glob("work/ipums/*.xml")))[1]
}
ddi <- read_ipums_ddi(use); D <- as.data.table(read_ipums_micro(ddi, verbose = FALSE))
for (v in VARS) if (!v %in% names(D)) D[[v]] <- NA_integer_
message(nrow(D), " person records, years ", paste(sort(unique(D$YEAR)), collapse = " "), " (", basename(use), ")")
na0 <- function(x) { x <- as.numeric(x); x[is.na(x)] <- 0; x }
# region of birth from BPL (IPUMS general codes): 1-120 US and territories; 150 Canada; 200 Mexico; 210-399 other Americas;
# 400-499 Europe; 500-599 Asia; 600 Africa; 700-800 Oceania; 900+ abroad n.s. / unknown
D[, BPL := as.numeric(BPL)]
D[, region := fcase(BPL < 150, "US", BPL == 200, "Mexico", BPL >= 150 & BPL < 400, "other Americas", BPL >= 400 & BPL < 500, "Europe", BPL >= 500 & BPL < 600, "Asia", default = "other/unknown")]
D[, `:=`(fb = BPL >= 150 & BPL < 900, black = RACE == 2, white = RACE == 1, hisp = na0(HISPAN) > 0 & na0(HISPAN) < 9, laborer = na0(OCC1950) >= 970 & na0(OCC1950) <= 979,
         foreign_parent = NATIVITY %in% 2:4, adult = AGE >= 18, child = AGE < 15, aged = AGE >= 65, male = SEX == 1, married = MARST %in% 1:2 & AGE >= 15)]
D[, `:=`(recent_immig = fb & na0(YRIMMIG) > 0 & (YEAR - na0(YRIMMIG)) <= 10,
         naturalized = na0(CITIZEN) == 2, noncitizen = na0(CITIZEN) %in% 3:4,
         mt_spanish = na0(MTONGUE) == 12, mt_german = na0(MTONGUE) == 2, mt_italian = na0(MTONGUE) == 10, no_english = na0(SPEAKENG) == 1 & AGE >= 10,
         illiterate = na0(LIT) %in% 1:3 & AGE >= 10, lit_universe = na0(LIT) > 0 & AGE >= 10, in_school = na0(SCHOOL) == 2 & AGE >= 5 & AGE <= 17, school_universe = na0(SCHOOL) > 0 & AGE >= 5 & AGE <= 17,
         hs_grad = na0(EDUC) >= 6 & AGE >= 25, educ_universe = na0(EDUC) > 0 & AGE >= 25,
         employed = na0(LABFORCE) == 2 & (is.na(EMPSTAT) | na0(EMPSTAT) %in% c(0, 1)), in_labforce = na0(LABFORCE) == 2, unemployed = na0(EMPSTAT) == 2,
         haz_industry = na0(IND1950) %in% c(336:339, 346:349, 356:359, 376:379, 466:469, 476:478, 206:239), railroad = na0(IND1950) == 506,
         manufacturing = na0(IND1950) >= 306 & na0(IND1950) <= 499,
         wage = fifelse(na0(INCWAGE) > 0 & na0(INCWAGE) < 999998, as.numeric(INCWAGE), NA_real_),
         veteran = na0(VETSTAT) == 2, children_born = fifelse(na0(CHBORN) > 0, na0(CHBORN) - 1, NA_real_), mother = na0(CHBORN) > 0,
         head = RELATE == 1, boarder = na0(RELATE) %in% 12:13 | (na0(RELATE) >= 1200 & na0(RELATE) < 1300), gq = na0(GQ) >= 3,
         owner_hh = na0(OWNERSHP) == 1 & RELATE == 1, renter_hh = na0(OWNERSHP) == 2 & RELATE == 1, mortgaged_hh = na0(OWNERSHP) == 1 & RELATE == 1 & na0(MORTGAGE) >= 2, tenure_hh = na0(OWNERSHP) > 0 & RELATE == 1,
         value_h = fifelse(RELATE == 1 & na0(OWNERSHP) == 1 & na0(VALUEH) > 0 & na0(VALUEH) < 9999998, as.numeric(VALUEH), NA_real_),
         rent_h = fifelse(RELATE == 1 & na0(OWNERSHP) == 2 & na0(RENT) > 0 & na0(RENT) < 9998, as.numeric(RENT), NA_real_),
         radio_hh = RELATE == 1 & na0(RADIO) == 2, radio_universe = RELATE == 1 & na0(RADIO) > 0,
         mover = na0(MIGRATE5) %in% 2:4, mover_universe = na0(MIGRATE5) %in% 1:4, mover_other_state = na0(MIGRATE5) %in% 3:4,
         sei_v = fifelse(na0(LABFORCE) == 2 & na0(SEI) > 0, as.numeric(SEI), NA_real_), occscore_v = fifelse(na0(LABFORCE) == 2 & na0(OCCSCORE) > 0, as.numeric(OCCSCORE), NA_real_))]
ED <- D[, .(pop = .N, households = sum(head), black = sum(black), white = sum(white), fb = sum(fb), fb_mexico = sum(region == "Mexico"), fb_europe = sum(region == "Europe"), fb_asia = sum(region == "Asia"),
            fb_canada = sum(BPL == 150), hisp = sum(hisp), foreign_parentage = sum(foreign_parent), laborers = sum(laborer),
            recent_immig = sum(recent_immig), naturalized = sum(naturalized), noncitizen = sum(noncitizen), mt_spanish = sum(mt_spanish), mt_german = sum(mt_german), mt_italian = sum(mt_italian), no_english = sum(no_english),
            children = sum(child), aged = sum(aged), adults = sum(adult), males = sum(male), married = sum(married), adults15 = sum(AGE >= 15),
            illiterate = sum(illiterate), lit_universe = sum(lit_universe), in_school = sum(in_school), school_universe = sum(school_universe), hs_grad = sum(hs_grad), educ_universe = sum(educ_universe),
            employed = sum(employed), in_labforce = sum(in_labforce), unemployed = sum(unemployed), haz_industry = sum(haz_industry), railroad = sum(railroad), manufacturing = sum(manufacturing),
            mean_sei = mean(sei_v, na.rm = TRUE), mean_occscore = mean(occscore_v, na.rm = TRUE), median_wage = as.numeric(median(wage, na.rm = TRUE)), wage_n = sum(!is.na(wage)),
            veterans = sum(veteran), children_ever_born = sum(children_born, na.rm = TRUE), mothers = sum(mother), boarders = sum(boarder), group_quarters = sum(gq),
            owner_hh = sum(owner_hh), renter_hh = sum(renter_hh), mortgaged_hh = sum(mortgaged_hh), tenure_hh = sum(tenure_hh), median_value = as.numeric(median(value_h, na.rm = TRUE)), value_n = sum(!is.na(value_h)),
            median_rent = as.numeric(median(rent_h, na.rm = TRUE)), rent_n = sum(!is.na(rent_h)), radio_hh = sum(radio_hh), radio_universe = sum(radio_universe),
            movers = sum(mover), mover_universe = sum(mover_universe), movers_other_state = sum(mover_other_state),
            denver_city = mean(CITY == 1710)), by = .(YEAR, COUNTYICP, ENUMDIST)]   # IPUMS CITY 1710 = Denver, CO
for (v in c("mean_sei", "mean_occscore", "median_wage", "median_value", "median_rent")) ED[is.nan(get(v)), (v) := NA_real_]
# a question the census did not ask that year (e.g. year of immigration in 1880 and 1940), or asked only on the 1940 sample line
# (~5% of persons: mother tongue, veteran status, children ever born, parents' birthplace), must be MISSING, not 0: the counts built
# from it are set to NA for every ED of that year.
SRC <- list(YRIMMIG = "recent_immig", CITIZEN = c("naturalized", "noncitizen"), MTONGUE = c("mt_spanish", "mt_german", "mt_italian"), SPEAKENG = "no_english",
            LIT = c("illiterate", "lit_universe"), SCHOOL = c("in_school", "school_universe"), EDUC = c("hs_grad", "educ_universe"), LABFORCE = c("employed", "in_labforce"),
            EMPSTAT = "unemployed", IND1950 = c("haz_industry", "railroad", "manufacturing"), OCC1950 = "laborers", VETSTAT = "veterans", CHBORN = c("children_ever_born", "mothers"),
            OWNERSHP = c("owner_hh", "renter_hh", "tenure_hh"), MORTGAGE = "mortgaged_hh", RADIO = c("radio_hh", "radio_universe"), MIGRATE5 = c("movers", "mover_universe", "movers_other_state"),
            HISPAN = "hisp", NATIVITY = "foreign_parentage", SEI = "mean_sei", OCCSCORE = "mean_occscore", INCWAGE = "median_wage", VALUEH = "median_value", RENT = "median_rent")
asked <- D[, lapply(.SD, function(v) any(!is.na(v) & as.numeric(v) != 0)), by = YEAR, .SDcols = intersect(names(SRC), names(D))]   # not asked = no valid value at all that year
SAMPLE_1940 <- c("MTONGUE", "VETSTAT", "CHBORN", "NATIVITY")                                        # 1940 sample-line questions (~5% of persons)
for (src in intersect(names(SRC), names(D))) { yrs <- c(asked[get(src) == FALSE]$YEAR, if (src %in% SAMPLE_1940) 1940L)
  for (yr in intersect(yrs, unique(ED$YEAR))) { ED[YEAR == yr, (intersect(SRC[[src]], names(ED))) := NA_real_]; message(yr, ": ", src, " not asked (or 1940 sample line only) -> ", paste(SRC[[src]], collapse = ", "), " set to NA") } }
# Denver flag: CITY where coded (rural Arapahoe EDs of 1880/1900 have CITY = 0 and are NOT Denver); where CITY is missing, the County
# of Denver (ICP 310, from 1902) or, in 1880/1900, Arapahoe County (ICP 50).
# NB the 'boarders' count is IPUMS general RELATE 12-13: other non-relatives of the household head (boarders, lodgers, roomers,
# employees, other non-relatives) and institutional inmates - labelled "non-relatives" in the app and paper.
ED[, denver := fifelse(is.na(denver_city), COUNTYICP == 310 | (YEAR < 1910 & COUNTYICP == 50), denver_city > 0.5)]   # CITY decides wherever IPUMS codes it
fwrite(ED, "work/census/denver_ed_1880_1940.csv")
print(ED[denver == TRUE, .(EDs = .N, pop = sum(pop), pct_black = round(100 * sum(black) / sum(pop), 1), pct_fb = round(100 * sum(fb) / sum(pop), 1), pct_hisp = round(100 * sum(hisp) / sum(pop), 1),
                            pct_owner_hh = round(100 * sum(owner_hh) / pmax(sum(tenure_hh), 1), 1), pct_movers_1935_40 = round(100 * sum(movers) / pmax(sum(mover_universe), 1), 1)), by = YEAR])
message("wrote work/census/denver_ed_1880_1940.csv (", ncol(ED), " columns; every Colorado ED, denver = Denver city).")
