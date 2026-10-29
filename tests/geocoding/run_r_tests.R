# Run the R tests for the geocoding / site-building stages:   Rscript tests/geocoding/run_r_tests.R
# Needs the pytest run first (it writes tests/geocoding/.cache: the synthetic fixture and the Python results the parity tests read).
suppressPackageStartupMessages(library(testthat))
root <- normalizePath(file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE)[1])), "..", ".."))
Sys.setenv(AUDIT_ROOT = root)
res <- test_dir(file.path(root, "tests", "geocoding", "testthat"), reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
cat(sprintf("\nR tests: %d passed, %d failed, %d skipped\n", sum(df$passed), sum(df$failed), sum(df$skipped)))
if (sum(df$failed) > 0 || sum(df$error) > 0) quit(status = 1)
