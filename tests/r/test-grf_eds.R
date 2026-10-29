E <- script_env("grf_eds.R")

mk_ip <- function(enumdist, year = 1940, county = 310, pop = 100) data.table(YEAR = year, COUNTYICP = county, ENUMDIST = enumdist, pop = pop, black = pop / 10, denver_city = 1, mean_age = 30 + seq_along(enumdist))

test_that("ipums_ed(): 1940 labels are SD-ED-suffix with suffixes A-G, and counts are summed by label", {
  E$ip <- mk_ip(c(1602250, 1602501, 1602504, 1602505, 1602506, 1602507), pop = c(100, 50, 20, 30, 40, 10))
  out <- E$ipums_ed(1940)
  expect_setequal(out$ED, c("225", "250A", "250D", "250E", "250F", "250G"))
  expect_equal(out[ED == "225", pop], 100)
  expect_true("mean_age" %in% names(out))
})

test_that("ipums_ed(): an unknown 1940 suffix code stops", {
  E$ip <- mk_ip(c(1602250, 1602508))
  expect_error(E$ipums_ed(1940), "unknown ED suffix code 8")
})

test_that("ipums_ed(): two IPUMS districts mapping to one label stop instead of being pooled", {
  E$ip <- mk_ip(c(1602250, 1702250))            # SD 16 and SD 17 both have ED 225
  expect_error(E$ipums_ed(1940), "two IPUMS districts map to one ED label")
})

test_that("ipums_ed(): 1900-1930 labels are ENUMDIST mod 100000 and Denver is Arapahoe (ICP 50) before 1910", {
  E$ip <- rbind(mk_ip(c(100012, 100013), year = 1900, county = 50, pop = c(10, 20)), mk_ip(100012, year = 1900, county = 310, pop = 999))
  out <- E$ipums_ed(1900)
  expect_setequal(out$ED, c("12", "13")); expect_equal(sum(out$pop), 30)
  E$ip <- rbind(mk_ip(c(100012, 100013), year = 1920, county = 310, pop = c(10, 20)), mk_ip(100012, year = 1920, county = 50, pop = 999))
  expect_equal(sum(E$ipums_ed(1920)$pop), 30)
})

test_that("ipums_ed(): person-weighted means use pop weights", {
  E$ip <- mk_ip(c(1602250, 1602250), pop = c(100, 300)); E$ip$mean_age <- c(20, 40)
  expect_equal(E$ipums_ed(1940)$mean_age, 35)
})
