# Helpers for the R analysis tests.
#
# The analysis scripts in R/ run top to bottom with data on disk. The tests never run them; they parse each file and evaluate only
# the top-level assignments that define functions (`name <- function(...)`) and simple constants (`name <- "..."`, `name <- c(...)`,
# `name <- list(...)` built from literals), so the pure logic can be exercised on small synthetic inputs without any data.
suppressPackageStartupMessages({ library(testthat); library(data.table); library(sf) })
sf::sf_use_s2(FALSE)

ROOT <- local({                                              # repository root: the directory that holds R/ and app/
  d <- normalizePath(getwd(), mustWork = TRUE)
  for (i in 1:4) { if (dir.exists(file.path(d, "R")) && dir.exists(file.path(d, "app"))) return(d); d <- dirname(d) }
  stop("cannot find the repository root from ", getwd()) })
rfile <- function(name) file.path(ROOT, "R", name)

SAFE_FUNS <- c("c", "list", "setNames", "paste0", "paste", "sprintf", ":", "-", "(", "rep", "seq", "seq_len", "as.integer", "as.numeric", "as.character", "toupper", "tolower", "names")

is_const <- function(e) {                                    # a literal, or a whitelisted call whose arguments are all constants
  if (is.null(e) || is.atomic(e)) return(TRUE)
  if (is.symbol(e)) return(FALSE)
  if (is.call(e)) { f <- e[[1]]; if (!is.symbol(f) || !as.character(f) %in% SAFE_FUNS) return(FALSE)
    args <- as.list(e)[-1]; return(all(vapply(args, is_const, TRUE))) }
  FALSE }

is_fun <- function(e) is.call(e) && identical(e[[1]], as.symbol("function"))

# Evaluate `name <- function(...)` (and, with consts = TRUE, constant) assignments of a script into `env`. Returns the environment.
source_functions <- function(path, env = new.env(parent = globalenv()), consts = TRUE) {
  exprs <- parse(path, keep.source = FALSE)
  for (e in exprs) {
    if (!is.call(e) || !as.character(e[[1]]) %in% c("<-", "=") || length(e) != 3 || !is.symbol(e[[2]])) next
    rhs <- e[[3]]
    if (is_fun(rhs) || (consts && is_const(rhs))) eval(e, env)
  }
  env }

# Memoised loading: each script's functions are extracted once per test run.
.ENVS <- new.env()
script_env <- function(name) { if (is.null(.ENVS[[name]])) .ENVS[[name]] <- source_functions(rfile(name)); .ENVS[[name]] }

# Small geometry helpers for synthetic sf objects (UTM 13N, EPSG:26913, metres)
UTM <- 26913
sq <- function(x0, y0, w, h = w) sf::st_polygon(list(rbind(c(x0, y0), c(x0 + w, y0), c(x0 + w, y0 + h), c(x0, y0 + h), c(x0, y0))))
line_xy <- function(x0, y0, x1, y1) sf::st_linestring(rbind(c(x0, y0), c(x1, y1)))
