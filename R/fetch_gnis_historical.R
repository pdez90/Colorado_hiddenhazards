# Colorado places missing from data/historical/gnis_places_co.csv, for the pre-1960 layer (a listing reviewed to a town not in the
# gazetteer cannot be placed).
#   Rscript R/fetch_gnis_historical.R     -> data/historical/gnis_places_co_historical.csv
# Source: USGS Geographic Names Information System (public domain), from The National Map staged products: the August 2021 full Colorado
# file (Archive/MainDomestic/CO_Features_20210825.txt), the current Topical "Historical Features" file and the current Colorado Domestic
# Names file. Result (3 November 2026): one place. GNIS has no record, or a record without coordinates (Hortense, Swan City, Bullion
# City...), for the vanished camps in the 1870s-80s directories (Mosquito, Dora, Robinson, Orodelfan, Parrot City...), so the ~90
# listings reviewed to them stay unplaced; spelling variants and absorbed places are mapped by hand in data/historical/town_aliases.csv.
# Keeps Colorado populated places (not locales: a locale named "Park" or "Glen" could be anything) whose name is not already in gnis_places_co.csv;
# names upper case with any "(historical)" suffix dropped; where a name occurs more than once a current record is preferred over a
# historical one, then the first by feature id.
suppressPackageStartupMessages(library(data.table))
BASE <- "https://prd-tnm.s3.amazonaws.com/StagedProducts/GeographicNames/"
SRC <- c(arch = paste0(BASE, "Archive/MainDomestic/CO_Features_20210825.txt"),
         hist = paste0(BASE, "Topical/HistoricalFeatures_National_Text.zip"),
         dom  = paste0(BASE, "DomesticNames/DomesticNames_CO_Text.zip"))
dir.create("work/gnis", showWarnings = FALSE, recursive = TRUE)
options(timeout = max(600, getOption("timeout")))
read_gnis <- function(url, tag) {
  z <- file.path("work/gnis", basename(url))
  if (!file.exists(z)) download.file(url, z, mode = "wb")
  if (grepl("\\.zip$", z)) {
    f <- grep("\\.txt$", unzip(z, list = TRUE)$Name, value = TRUE)[1]; stopifnot(!is.na(f))
    unzip(z, files = f, exdir = file.path("work/gnis", tag), overwrite = TRUE); z <- file.path("work/gnis", tag, f)
  }
  D <- fread(z, sep = "|", quote = "", encoding = "UTF-8", colClasses = "character")
  setnames(D, sub("^\ufeff", "", tolower(names(D))))
  st <- intersect(c("state_name", "state_alpha"), names(D))[1]; stopifnot(!is.na(st))
  need <- c("feature_id", "feature_name", "feature_class", "county_name", "prim_lat_dec", "prim_long_dec"); stopifnot(all(need %in% names(D)))
  D <- D[get(st) %in% c("Colorado", "CO"), ..need]
  D[, hist := tag == "hist" | grepl("\\(historical\\)", feature_name, ignore.case = TRUE)]
  D
}
D <- rbindlist(lapply(names(SRC), function(k) read_gnis(SRC[[k]], k)))
P <- D[feature_class == "Populated Place"]
P[, name := toupper(trimws(gsub("\\s*\\(historical\\)", "", feature_name, ignore.case = TRUE)))]
P[, `:=`(lat = as.numeric(prim_lat_dec), lon = as.numeric(prim_long_dec))]
P <- P[is.finite(lat) & is.finite(lon) & lat != 0]
setorder(P, name, hist, feature_id); P <- P[!duplicated(name)]
cur <- toupper(fread("data/historical/gnis_places_co.csv", select = "name")$name)
S <- P[!name %in% cur, .(name, feature_class, county_name, lat = round(lat, 6), lon = round(lon, 6), hist)]
fwrite(S, "data/historical/gnis_places_co_historical.csv")
message(sprintf("%d Colorado populated places not in gnis_places_co.csv (%d historical) -> data/historical/gnis_places_co_historical.csv",
                nrow(S), sum(S$hist)))
