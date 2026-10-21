# Denver's zoning ordinances, 1923-1956, from the City's archive of scanned ordinances (Municode MuniDocs; public records).
#
#   Rscript R/fetch_denver_ordinances.R
#
# 1. Searches the archive's full text (Municode's library search, the same one the website uses) for zoning terms and keeps the
#    ordinances of 1923-1956: the 1925 zoning ordinance (No. 14, Series of 1925), its amendments, and the changes to the zone map up to
#    the 1956 code. Writes data/raw/ordinances/zoning_candidates.csv (ordinance number, archive id). The list in the repository was
#    built with these queries through the website's own search on 21 October 2026 (the search service refuses scripted requests from
#    some machines with HTTP 403); the search below runs only if that file is missing. 560 ordinances, after dropping those that matched
#    only "Series of 1925" or "Ordinance No. 14" (every 1925 ordinance carries the former).
# 2. Downloads each ordinance's scanned PDF (work/ordinances/pdf/, git-ignored) and extracts its text layer (the archive's own OCR) to
#    data/raw/ordinances/text/<ordinance>.txt. Re-running skips what is already there.
# Source: https://library.municode.com/co/denver/munidocs/munidocs (City and County of Denver, Clerk and Recorder).
options(timeout = 300, HTTPUserAgent = "Mozilla/5.0 (research; Denver zoning history)")
for (p in c("data.table", "jsonlite", "pdftools")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages(library(data.table))
R0 <- "data/raw/ordinances"; TX <- file.path(R0, "text"); PD <- "work/ordinances/pdf"
for (d in c(R0, TX, PD)) dir.create(d, showWarnings = FALSE, recursive = TRUE)
Y0 <- 1923; Y1 <- 1956
HDR <- c(Accept = "application/json, text/plain, */*", Referer = "https://library.municode.com/co/denver/munidocs/munidocs",
         `User-Agent` = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36")
QUERIES <- c("zoning", "\"district to a\"", "\"district to an\"", "\"changed from\"", "\"zoning ordinance\"", "\"district map\"", "\"zone map\"", "rezone", "rezoned", "zoned",
             "\"Residence A\"", "\"Business B\"", "\"Commercial A\"", "\"Industrial A\"", "\"Industrial B\"")
CAND <- file.path(R0, "zoning_candidates.csv")
if (!file.exists(CAND)) {
  getj <- function(u) { for (i in 1:4) { f <- tempfile(); ok <- tryCatch({ download.file(u, f, quiet = TRUE, headers = HDR); TRUE }, error = function(e) FALSE, warning = function(w) FALSE)
    if (ok) return(jsonlite::fromJSON(f, simplifyVector = FALSE)); Sys.sleep(3 * i) }; stop("the archive's search refused the request (", u, "); use the list in the repository") }
  hits <- list()
  for (q in QUERIES) { p <- 1
    repeat {
      u <- sprintf("https://library.municode.com/localapi/search?clientId=11266&contentTypeId=MUNIDOCS&fragmentSize=300&isAdvanced=false&isAutocomplete=false&mode=CLIENTMODE&pageNum=%d&pageSize=100&searchText=%s&sort=0&stateId=6&titlesOnly=false",
                   p, URLencode(q, reserved = TRUE))
      r <- getj(u); if (!length(r$hits)) break
      for (h in r$hits) { yr <- suppressWarnings(as.integer(substr(h$title, 1, 4)))
        if (length(h$ancestors) && identical(h$ancestors[[1]]$title, "Ordinances") && !is.na(yr) && yr >= Y0 && yr <= Y1)
          hits[[length(hits) + 1]] <- data.table(ordinance = h$title, node_id = h$nodeId, year = yr, query = gsub("\"", "", q),
                                                 snippet = substr(gsub("\\s+", " ", gsub("<[^>]+>", "", h$contentFragment)), 1, 300)) }
      if (p * 100 >= r$numberOfHits) break; p <- p + 1; Sys.sleep(0.3) }
    message(sprintf("  %-20s %d ordinances so far", q, if (length(hits)) uniqueN(rbindlist(hits)$node_id) else 0L)) }
  H <- rbindlist(hits)[, .(year = year[1], queries = paste(unique(query), collapse = ";"), snippet = snippet[1]), by = .(ordinance, node_id)][order(ordinance)]
  H <- H[!queries %in% c("Series of 1925", "Ordinance No. 14", "Series of 1925;Ordinance No. 14")]
  fwrite(H, CAND); message(nrow(H), " candidate ordinances -> ", CAND)
}
H <- fread(CAND, colClasses = "character"); nfail <- 0; nrun <- 0      # nrun: failures in a row
for (i in seq_len(nrow(H))) {
  txt <- file.path(TX, paste0(H$ordinance[i], ".txt")); if (file.exists(txt)) next
  pdf <- file.path(PD, paste0(H$ordinance[i], ".pdf"))
  if (!file.exists(pdf) || file.size(pdf) < 1000) {
    ok <- tryCatch({ download.file(sprintf("https://mcclibraryfunctions.azurewebsites.us/api/munidocDownload/31287/%s/pdf", H$node_id[i]), pdf, mode = "wb", quiet = TRUE,
                                headers = c(HDR[c("Referer", "User-Agent")], Accept = "application/pdf,*/*")); TRUE },
                   error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) { message("  failed: ", H$ordinance[i]); if (file.exists(pdf)) file.remove(pdf); nfail <- nfail + 1; nrun <- nrun + 1
      if (nrun >= 10) stop("ten downloads in a row failed: the archive may be refusing downloads from R; run again later"); next }
    nrun <- 0
    Sys.sleep(0.5) }
  t <- tryCatch(pdftools::pdf_text(pdf), error = function(e) NULL); if (is.null(t)) { message("  unreadable: ", H$ordinance[i]); next }
  writeLines(paste(sprintf("=== page %d ===\n%s", seq_along(t), t), collapse = "\n"), txt)
  if (i %% 50 == 0) message("  ", i, " / ", nrow(H))
}
message(length(list.files(TX)), " ordinance texts in ", TX)
