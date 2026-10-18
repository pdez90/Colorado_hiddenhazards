# Sanborn archival check for the street-level pre-1960 hazardous trades listed 1887-1904 in Denver.
#   Rscript R/sanborn_check.R
# Each of the 20 trades in data/results/site_fate/archival_check_sanborn_1887_1904.csv was read on the 1890 Sanborn Fire Insurance
# Map of Denver (Library of Congress, Geography and Map Division, vols 1-2; public domain): the sheet was found from the volume's
# street index and the block face read at the listed house number. The CSV holds the reading (use_shown_on_sheet), a verdict
# (matches_geocode: yes / partial / no / inconclusive) and the IIIF URL of the sheet region that was read (sheet_crop_url).
# This script downloads those regions to data/raw/sanborn_1890/<hfirm>.jpg so the readings can be checked by eye, and prints the tally.
suppressPackageStartupMessages(library(data.table))
f <- "data/results/site_fate/archival_check_sanborn_1887_1904.csv"; O <- "data/raw/sanborn_1890"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
S <- fread(f)
for (i in seq_len(nrow(S))) {
  out <- file.path(O, paste0(S$hfirm[i], ".jpg"))
  if (file.exists(out) && file.size(out) > 1000) next
  ok <- tryCatch({ download.file(S$sheet_crop_url[i], out, mode = "wb", quiet = TRUE); TRUE }, error = function(e) FALSE)
  message(sprintf("%-8s %-14s %s", S$hfirm[i], S$street[i], if (ok) "downloaded" else "FAILED"))
  Sys.sleep(1)
}
print(S[, .N, by = matches_geocode][order(-N)])
print(S[, .(hfirm, street, sectors, matches_geocode, use_shown_on_sheet)])
