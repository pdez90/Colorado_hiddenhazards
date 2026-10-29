# String similarity identical to rapidfuzz (Python) as used by the pipeline: fuzz.ratio, fuzz.token_set_ratio,
# fuzz.token_sort_ratio. Indel distance = Levenshtein with substitution cost 2. No preprocessing (rapidfuzz >= 3 default).
indel_dist <- function(a, b) drop(utils::adist(a, b, costs = list(insertions = 1, deletions = 1, substitutions = 2)))
fz_ratio <- function(a, b) { n <- nchar(a) + nchar(b); ifelse(n == 0, 100, 100 * (1 - indel_dist(a, b) / n)) }
toks <- function(s) { t <- strsplit(trimws(s), "\\s+")[[1]]; t[nzchar(t)] }
fz_token_sort_ratio <- function(a, b) fz_ratio(paste(sort(toks(a), method = "radix"), collapse = " "), paste(sort(toks(b), method = "radix"), collapse = " "))
fz_token_set_ratio <- function(a, b) {
  ta <- unique(toks(a)); tb <- unique(toks(b))
  if (!length(ta) || !length(tb)) return(0)
  inter <- intersect(ta, tb); dab <- setdiff(ta, tb); dba <- setdiff(tb, ta)
  if (length(inter) && (!length(dab) || !length(dba))) return(100)
  sab <- paste(sort(dab, method = "radix"), collapse = " "); sba <- paste(sort(dba, method = "radix"), collapse = " ")
  sect_len <- nchar(paste(inter, collapse = " ")); ab_len <- nchar(sab); ba_len <- nchar(sba)
  sect_ab <- sect_len + (sect_len != 0) + ab_len; sect_ba <- sect_len + (sect_len != 0) + ba_len
  res <- 100 * (1 - indel_dist(sab, sba) / (sect_ab + sect_ba))
  if (sect_len == 0) return(res)
  max(res, 100 * (1 - (sect_ab - sect_len) / (sect_len + sect_ab)), 100 * (1 - (sect_ba - sect_len) / (sect_len + sect_ba)))
}
# number of distinct tokens two strings share (for the "at least two shared informative words" rule in build_sites)
fz_shared_tokens <- function(a, b) length(intersect(unique(toks(a)), unique(toks(b))))
