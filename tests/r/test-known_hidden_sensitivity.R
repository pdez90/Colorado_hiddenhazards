E <- script_env("known_hidden_sensitivity.R")

# five synthetic sites: firm's own record (entity), cleanup boundary, an unrelated RCRA notifier 35 m away, an unrelated TRI
# record 8 m away, and one with nothing inside any radius but an RCRA record 70 m away
mk <- function() {
  D <- data.table(site_id = paste0("S", 1:5), spread_m = c(0, 0, 0, 0, 0),
                  radar = c("TRI reporter", "Cleanup / contamination list", "RCRA hazardous-waste handler", "TRI reporter", "Not on any list"),
                  match_basis = c("same entity (name or address)", "inside a cleanup boundary", "nearby record only", "nearby record only", "none"))
  for (t in names(E$RULES)) { set(D, j = paste0(t, "_basis"), value = ""); set(D, j = paste0(t, "_prox_m"), value = NA_real_); set(D, j = paste0(t, "_nearest_m"), value = NA_real_) }
  D[1, `:=`(tri_basis = "entity", tri_nearest_m = 60)]
  D[2, cleanup_basis := "boundary"]
  D[3, `:=`(rcra_handler_basis = "prox", rcra_handler_prox_m = 35, rcra_handler_nearest_m = 35)]
  D[4, `:=`(tri_basis = "prox", tri_prox_m = 8, tri_nearest_m = 8)]
  D[5, rcra_handler_nearest_m := 70]
  D }

test_that("known_under(): the ladder of rules from looser to strict", {
  D <- mk()
  expect_equal(E$known_under(D, "published"), c(TRUE, TRUE, TRUE, TRUE, FALSE))
  expect_equal(E$known_under(D, "strict"), c(TRUE, TRUE, FALSE, FALSE, FALSE))
  expect_equal(E$known_under(D, "prox25"), c(TRUE, TRUE, FALSE, TRUE, FALSE))            # the 8 m TRI record still counts
  expect_equal(E$known_under(D, "prox10"), c(TRUE, TRUE, FALSE, TRUE, FALSE))
  expect_equal(E$known_under(D, "cleanup_tri_prox"), c(TRUE, TRUE, FALSE, TRUE, FALSE))  # the RCRA notifier no longer counts
  expect_equal(E$known_under(D, "wider"), c(TRUE, TRUE, TRUE, TRUE, TRUE))               # the RCRA record at 70 m is inside 2 x 40 m
  expect_error(E$known_under(D, "nonsense"))
})

test_that("known_under('wider'): the doubled radius grows with the spread and is capped at 250 m", {
  D <- mk()[5]; D[, rcra_handler_nearest_m := 120]
  expect_false(E$known_under(D, "wider")); D[, spread_m := 50]; expect_true(E$known_under(D, "wider"))
  D[, `:=`(spread_m = 500, rcra_handler_nearest_m = 249)]; expect_true(E$known_under(D, "wider"))
})

test_that("rules are nested where they should be: strict <= prox10 <= prox25 <= published <= wider", {
  D <- mk(); k <- function(d) E$known_under(D, d)
  expect_true(all(k("strict") <= k("prox10"))); expect_true(all(k("prox10") <= k("prox25")))
  expect_true(all(k("prox25") <= k("published"))); expect_true(all(k("published") <= k("wider")))
  expect_true(all(k("strict") <= k("cleanup_tri_prox"))); expect_true(all(k("cleanup_tri_prox") <= k("published")))
})

test_that("check_evidence(): the published status is rebuilt exactly from the evidence columns", {
  D <- mk(); expect_equal(E$check_evidence(D), 0L)
  D[3, rcra_handler_basis := ""]; expect_equal(E$check_evidence(D), 1L)
})

test_that("nearest_prox(): tier and distance of the nearest proximity-only record", {
  D <- mk(); P <- E$nearest_prox(D)
  expect_equal(P$tier, c(NA, NA, "rcra_handler", "tri", NA)); expect_equal(P$dist_m, c(NA, NA, 35, 8, NA))
  expect_equal(as.character(E$dist_band(c(5, 10, 24, 39, 60, 99))), c("0-10 m", "0-10 m", "10-25 m", "25-40 m", "40-75 m", "over 75 m"))
})

test_that("tract_classes() and compare_classes(): a tract with any hidden site is a hidden-site tract", {
  cls <- E$tract_classes(c("a", "a", "b", NA), c(TRUE, FALSE, TRUE, FALSE), c("a", "b", "c"))
  expect_equal(unname(cls), c("At least one hidden site", "Only known sites", "No hazardous-sector site"))
  T <- data.table(GEOID = letters[1:9], v = c(90, 80, 85, 50, 55, 60, 10, 20, 30))
  cls <- setNames(rep(c("At least one hidden site", "Only known sites", "No hazardous-sector site"), each = 3), letters[1:9])
  R <- E$compare_classes(T, cls, c(v = "score"))
  expect_equal(R$median_hidden, 85); expect_equal(R$median_known_only, 55); expect_equal(R$median_no_site, 20)
  expect_equal(R$p_hidden_vs_no_site, wilcox.test(c(90, 80, 85), c(10, 20, 30))$p.value)
})
