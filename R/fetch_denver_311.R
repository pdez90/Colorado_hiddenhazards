# Denver 311 service requests handled by Community Planning & Development (neighborhood inspections: code enforcement) and by Public
# Health & Environment (residential health: mold, no heat, pests, water damage), from the City's open data (ArcGIS, one layer per year).
#
#   Rscript R/fetch_denver_311.R          years 2016 onward (as many yearly layers as the City publishes)
#   Rscript R/fetch_denver_311.R 2010     from 2010
#
# Writes work/denver311/311_<year>.csv (git-ignored: requests carry street addresses). Re-running skips years already downloaded.
# The layer list is read from the City's ArcGIS service directory, so later years are picked up when published.
options(timeout = 600)
for (p in c("data.table", "jsonlite")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE); Y0 <- if (length(args)) as.integer(args[1]) else 2016L
O <- "work/denver311"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
BASE <- "https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/arcgis/rest/services"
get_json <- function(u, tries = 4) { for (i in seq_len(tries)) { r <- tryCatch(jsonlite::fromJSON(u, simplifyVector = TRUE), error = function(e) NULL); if (!is.null(r)) return(r); Sys.sleep(3 * i) }
  stop("could not read ", u) }
S <- get_json(paste0(BASE, "?f=json"))$services
cand <- S$name[grepl("311", S$name)]
message("311 services published: ", paste(cand, collapse = ", "))
yr <- suppressWarnings(as.integer(sub(".*?((19|20)[0-9]{2}).*", "\\1", cand))); keep <- cand[!is.na(yr) & yr >= Y0 & grepl("request", cand, ignore.case = TRUE)]
WANT <- c("Case_Summary", "Case_Status", "Case_Source", "Case_Created_dttm", "Case_Created_Date", "Incident_Address_1", "Incident_Zip_Code", "Longitude", "Latitude",
          "Agency", "Division", "Major_Area", "Type", "Topic")
for (nm in keep) {
  y <- as.integer(sub(".*?((19|20)[0-9]{2}).*", "\\1", nm)); out <- file.path(O, sprintf("311_%d.csv", y))
  if (file.exists(out)) { message(nm, ": already downloaded"); next }
  L <- paste0(BASE, "/", nm, "/FeatureServer/0"); meta <- get_json(paste0(L, "?f=json"))
  flds <- meta$fields$name; step <- min(2000L, if (!is.null(meta$maxRecordCount)) as.integer(meta$maxRecordCount) else 1000L)
  agc <- flds[tolower(flds) == "agency"][1]; oid <- if (!is.null(meta$objectIdField)) meta$objectIdField else flds[meta$fields$type == "esriFieldTypeOID"][1]
  where <- if (!is.na(agc)) sprintf("%s LIKE '%%Planning%%' OR %s LIKE '%%Health%%' OR %s LIKE '%%Environment%%' OR %s LIKE '%%Neighborhood%%' OR %s LIKE '%%Excise%%'", agc, agc, agc, agc, agc) else "1=1"
  if (is.na(agc)) message(nm, ": no Agency field; downloading every request")
  of <- intersect(flds, WANT); if (!length(of)) of <- "*"
  n <- get_json(paste0(L, "/query?where=", URLencode(where, reserved = TRUE), "&returnCountOnly=true&f=json"))$count
  message(sprintf("%s: %s requests to read", nm, format(n, big.mark = ",")))
  parts <- list(); off <- 0
  while (off < n) {
    u <- paste0(L, "/query?where=", URLencode(where, reserved = TRUE), "&outFields=", paste(of, collapse = ","), "&returnGeometry=false&orderByFields=", oid,
                "&resultOffset=", off, "&resultRecordCount=", step, "&f=json")
    r <- get_json(u); a <- as.data.table(r$features$attributes); if (!nrow(a)) break
    parts[[length(parts) + 1]] <- a; off <- off + nrow(a)
    if (length(parts) %% 25 == 0) message("   ", format(off, big.mark = ","), " / ", format(n, big.mark = ","))
  }
  d <- rbindlist(parts, fill = TRUE)
  for (cc in intersect(c("Case_Created_dttm", "Case_Created_Date"), names(d))) if (is.numeric(d[[cc]])) set(d, j = cc, value = format(as.POSIXct(d[[cc]] / 1000, origin = "1970-01-01", tz = "America/Denver"), "%Y-%m-%d"))
  d[, year := y]; fwrite(d, out); message("   -> ", out, " (", nrow(d), " rows)")
}
message("done; ", length(list.files(O, "^311_")), " years in ", O)
