# Download the IPUMS Multigenerational Longitudinal Panel (MLP) links for Colorado through the IPUMS API, and write them in the form
# R/mlp_residential_history.R reads.
#
#   Rscript R/fetch_ipums_mlp.R
#
# The IPUMS API cannot request "linked census" extracts, and the MLP crosswalk files need a browser login. But the MLP's Historical
# Identification Key (HIK) is an ordinary variable: a person linked across censuses carries the same HIK in each. So this script requests
# the 1910, 1920, 1930 and 1940 complete-count censuses for Colorado with HISTID and HIK (same IPUMS_API_KEY and IPUMS USA registration as
# R/fetch_ipums_fullcount.R), and pairs each 1940 record with the same person's earlier record through the HIK.
# Restricting the request to Colorado is enough here: the residential histories only use earlier addresses in Denver. (People who lived
# outside Colorado earlier simply have no earlier link in these files.)
# Output: work/mlp/hik_<year>_1940.csv with columns histid<year>, histid1940 (one file per earlier census); the extract stays in work/ipums/mlp/.
if (!requireNamespace("ipumsr", quietly = TRUE)) install.packages("ipumsr", repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(ipumsr); library(data.table) })
key <- Sys.getenv("IPUMS_API_KEY"); if (!nzchar(key)) stop("set IPUMS_API_KEY (as for R/fetch_census.R)")
set_ipums_api_key(key, overwrite = TRUE, save = FALSE)
D <- "work/ipums/mlp"; dir.create(D, showWarnings = FALSE, recursive = TRUE); dir.create("work/mlp", showWarnings = FALSE, recursive = TRUE)
SAMPLES <- c("us1910m", "us1920c", "us1930d", "us1940b")                 # 100% databases
ddi <- rev(sort(Sys.glob(file.path(D, "*.xml"))))[1]
if (is.na(ddi)) {
  ext <- define_extract_micro("usa", description = "Colorado full count 1910-1940 with MLP links (HISTID, HIK)", samples = SAMPLES,
                              variables = list(var_spec("STATEFIP", case_selections = "08"), "HISTID", "HIK"), data_format = "csv")
  sub <- submit_extract(ext); message("submitted IPUMS USA extract ", sub$number, "; full-count extracts take 10-60 minutes")
  sub <- wait_for_extract(sub); f <- download_extract(sub, download_dir = D, overwrite = TRUE)
  ddi <- grep("\\.xml$", f, value = TRUE)[1]; if (is.na(ddi)) ddi <- rev(sort(Sys.glob(file.path(D, "*.xml"))))[1] }
X <- as.data.table(read_ipums_micro(read_ipums_ddi(ddi), vars = c("YEAR", "HISTID", "HIK"), verbose = FALSE))
X[, `:=`(HISTID = toupper(trimws(as.character(HISTID))), HIK = trimws(as.character(HIK)))]
X <- X[!is.na(HIK) & nzchar(HIK) & !grepl("^0+$", HIK)]                           # unlinked people carry no key
message(format(nrow(X), big.mark = ","), " Colorado records with an MLP key: ", paste(capture.output(print(X[, .N, by = YEAR][order(YEAR)])), collapse = " "))
Y40 <- X[YEAR == 1940, .(HIK, histid1940 = HISTID)]
for (y in c(1910, 1920, 1930)) {
  Z <- merge(X[YEAR == y, .(HIK, h = HISTID)], Y40, by = "HIK")[!duplicated(histid1940)]
  setnames(Z, "h", paste0("histid", y)); f <- sprintf("work/mlp/hik_%d_1940.csv", y)
  fwrite(Z[, c(paste0("histid", y), "histid1940"), with = FALSE], f); message(f, ": ", format(nrow(Z), big.mark = ","), " people in Colorado in both ", y, " and 1940") }
