# Download the public-domain Library of Congress Sanborn maps of Denver (1887, 1890-1893, 1903-1904).
#
#   Rscript R/fetch_loc_sanborn.R                 catalogue of every sheet + the title, index and key pages of each volume
#   Rscript R/fetch_loc_sanborn.R sheets          also the sheets listed in data/raw/sanborn_loc/sheets_to_fetch.csv (columns: item, image_id)
#
# Source: Library of Congress, Geography and Map Division, Sanborn Fire Insurance Maps (no known restrictions on publication).
#   https://www.loc.gov/collections/sanborn-maps/   Denver items sanborn00985_001 to _007.
# Writes data/raw/sanborn_loc/catalogue.csv (one row per sheet image: edition, volume, sequence, LOC image id, IIIF service, page link)
# and JPEGs at half resolution in work/sanborn_loc/ (git-ignored; re-downloadable). Re-running skips files already downloaded.
options(timeout = 600)
for (p in c("data.table", "jsonlite")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
W <- "work/sanborn_loc"; R0 <- "data/raw/sanborn_loc"; dir.create(W, showWarnings = FALSE, recursive = TRUE); dir.create(R0, showWarnings = FALSE, recursive = TRUE)
ITEMS <- data.table(item = sprintf("sanborn00985_%03d", 1:7), edition = c("1887", rep("1890-1893", 3), rep("1903-1904", 3)), volume = c(1, 1, 2, 3, 1, 2, 3))
CAT <- file.path(R0, "catalogue.csv")
if (!file.exists(CAT)) {
  C <- rbindlist(lapply(seq_len(nrow(ITEMS)), function(i) {
    it <- ITEMS[i]; Sys.sleep(2)
    txt <- tryCatch(paste(readLines(sprintf("https://www.loc.gov/item/%s/?fo=json", it$item), warn = FALSE), collapse = ""), error = function(e) "")
    if (!nzchar(txt)) { message(it$item, ": could not read the catalogue"); return(NULL) }
    j <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
    res_url <- tryCatch(j$resources[[1]]$url, error = function(e) NA_character_)
    svc <- unique(regmatches(txt, gregexpr("https://tile\\.loc\\.gov/image-services/iiif/service:[^/\"]+", txt))[[1]])
    code <- sub(".*\\.(g[0-9]+)/?$", "\\1", res_url)                       # this volume's own images only (the record also links its sister volumes)
    svc <- svc[grepl(paste0(":", code, ":"), svc, fixed = TRUE)]
    if (!length(svc)) return(NULL)
    id <- sub(".*:", "", svc)
    message(it$item, " (", it$edition, " vol. ", it$volume, "): ", length(svc), " images")
    data.table(item = it$item, edition = it$edition, volume = it$volume, seq = seq_along(svc), image_id = id, iiif = svc,
               page = sprintf("%s?sp=%d", res_url, seq_along(svc)),
               kind = fcase(grepl("titl", id), "title", grepl("-ind", id), "index", grepl("key", id), "key map", default = "sheet")) }))
  fwrite(C, CAT); message("catalogue: ", nrow(C), " images")
}
C <- fread(CAT)
get_img <- function(iiif, image_id, edition, volume, pct = 50) {
  f <- file.path(W, sprintf("%s_v%d_%s.jpg", gsub("-", "_", edition), volume, image_id))
  if (file.exists(f) && file.size(f) > 10000) return(invisible(TRUE))
  Sys.sleep(1)
  ok <- tryCatch({ download.file(sprintf("%s/full/pct:%d/0/default.jpg", iiif, pct), f, mode = "wb", quiet = TRUE); TRUE }, error = function(e) FALSE, warning = function(w) FALSE)   # a truncated transfer only warns
  if (!ok) { message("  failed: ", image_id); if (file.exists(f)) file.remove(f) }
  invisible(ok) }
# title, index and key pages, plus the first two images of each volume (indexes are sometimes catalogued as plain sheets)
FRONT <- C[kind != "sheet" | seq <= 3]
message("front matter: ", nrow(FRONT), " images")
for (i in seq_len(nrow(FRONT))) with(FRONT[i], get_img(iiif, image_id, edition, volume))
if ("sheets" %in% args) {
  L <- fread(file.path(R0, "sheets_to_fetch.csv"))
  S <- merge(C, L, by = c("item", "image_id"))
  message("sheets: ", nrow(S), " of ", nrow(L), " requested")
  for (i in seq_len(nrow(S))) { with(S[i], get_img(iiif, image_id, edition, volume)); if (i %% 20 == 0) message("  ", i, " / ", nrow(S)) }
}
message("work/sanborn_loc: ", length(list.files(W)), " images, ", round(sum(file.size(list.files(W, full.names = TRUE))) / 1e6), " MB")
