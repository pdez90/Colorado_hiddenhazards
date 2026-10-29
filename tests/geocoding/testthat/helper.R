# Shared setup for the R tests in tests/geocoding/testthat. ROOT is the repository; CACHE holds what the pytest run wrote
# (synthetic fixture + Python results). Run with:  Rscript tests/geocoding/run_r_tests.R   (after pytest tests/geocoding)
find_root <- function() {
  r <- Sys.getenv("AUDIT_ROOT", "")
  if (nzchar(r)) return(normalizePath(r))
  d <- normalizePath(getwd())
  for (i in 1:6) { if (file.exists(file.path(d, "pipeline", "tiger_geocode.py"))) return(d); d <- dirname(d) }
  stop("repository root not found; set AUDIT_ROOT")
}
ROOT <- find_root()
CACHE <- file.path(ROOT, "tests", "geocoding", ".cache")
SYNTH <- file.path(CACHE, "synthetic")
# R/build_sites.R and R/fix_direction_geocodes.R skip their pipeline run when TESTING exists or AUDIT_TESTING is set (source() evaluates
# in the global environment, so both are set)
TESTING <- TRUE; assign("TESTING", TRUE, envir = globalenv()); Sys.setenv(AUDIT_TESTING = "1")
need_cache <- function(f) { p <- file.path(CACHE, f); if (!file.exists(p)) testthat::skip(paste("missing", p, "- run pytest tests/geocoding first")); p }
