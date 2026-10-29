EB <- script_env("benchmarks.R"); ES <- script_env("statewide.R"); ED <- script_env("descriptive_sequences.R")

test_that("benchmarks gisjoin_county(): the county FIPS from the NHGIS county GISJOIN (G0801010 is Pueblo, 101; the old reading dropped the hundreds digit)", {
  expect_equal(EB$gisjoin_county(c("G0801010", "G0800310", "G0800010", "G0801250")), c("101", "031", "001", "125"))
  expect_equal(unname(EB$cty_names[EB$gisjoin_county("G0801010")]), "Pueblo")
  expect_false(EB$gisjoin_county("G0801010") == sprintf("%03d", as.integer(substr("G0801010", 6, 8)) %/% 10))   # the pre-fix reading gave 010
})

test_that("benchmarks has_edition(): a census counts only with a directory edition within two years (1900 excluded)", {
  ed <- c(1878, 1882, 1892, 1910, 1912, 1921, 1930, 1941)
  expect_true(EB$has_edition(1880, ed)); expect_true(EB$has_edition(1910, ed)); expect_true(EB$has_edition(1920, ed)); expect_true(EB$has_edition(1940, ed))
  expect_false(EB$has_edition(1900, ed))      # 1892 and 1910 are both more than two years away
  expect_false(EB$has_edition(1900, c(1897, 1903)))
  expect_true(EB$has_edition(1900, c(1898)))
})

test_that("benchmarks: hazardous sectors in SIC and NAICS", {
  expect_equal(EB$HAZ_SIC, c("28", "29", "30", "33", "34", "35", "37")); expect_equal(length(EB$HAZ_NAICS), 7)
})

test_that("statewide county_region(): Arapahoe is Denver through the 1900 census and 'rest of Colorado' from 1910; Denver County is Denver", {
  expect_equal(ES$county_region(c("005", "005", "005", "031", "031"), c(1880, 1900, 1910, 1910, 1940)),
               c("Denver (Arapahoe before 1902)", "Denver (Arapahoe before 1902)", "rest of Colorado", "Denver (Arapahoe before 1902)", "Denver (Arapahoe before 1902)"))
  expect_equal(ES$county_region(c("065", "101", "021", "123"), 1920), c("mining counties", "Pueblo", "southern Hispano counties", "rest of Colorado"))
})

test_that("statewide REG(): today's regions by county FIPS", {
  expect_equal(ES$REG(c("031", "005", "001", "041", "101", "013", "077", "999")), c("Denver", "Denver suburbs", "Denver suburbs", "Colorado Springs (El Paso)", "Pueblo", "Boulder, Larimer, Weld", "Grand Junction (Mesa)", "rest of Colorado"))
  expect_equal(ES$per(c(1965, 1980, 1983, 1992)), c("1965-1980", "1965-1980", "1981-1992", "1981-1992"))
})

test_that("descriptive_sequences share_in(): share of each cell inside a layer", {
  cells <- sf::st_sf(cid = 1:3, geometry = sf::st_sfc(sq(0, 0, 100), sq(200, 0, 100), sq(400, 0, 100), crs = UTM))
  layer <- sf::st_sfc(sq(50, 0, 300), crs = UTM)   # covers half of cell 1, all of cell 2, none of cell 3
  expect_equal(ED$share_in(cells, layer), c(0.5, 1, 0))
})

test_that("descriptive_sequences lq(): location quotients against the city share, census by census", {
  G <- data.table(census = rep(c(1900, 1910), each = 2), cls4 = rep(c("D", "A"), 2), pop = 1000, black = c(150, 50, 300, 100), hisp = c(20, 20, 40, 40), fb = c(100, 100, 100, 100),
                  laborers = c(300, 100, 300, 100), owner_hh = c(50, 150, 60, 140), tenure_hh = 200, firms = c(2, 0, 3, 0), firms_ever = c(2, 0, 3, 0))
  x <- ED$lq(G, "cls4")
  expect_equal(x[census == 1900 & cls4 == "D", lq_black], round((150 / 1000) / (200 / 2000), 2))
  expect_equal(x[census == 1910 & cls4 == "A", lq_black], 0.5); expect_equal(x[cls4 == "A", lq_hisp], c(1, 1))
  expect_equal(x[census == 1900 & cls4 == "D", owner_ratio], round((50 / 200) / (200 / 400), 2))
  expect_equal(x[census == 1900 & cls4 == "D", cells_with_firm], 1); expect_equal(ED$pct(c(1, NA, 3), c(10, 10, 20)), 10)
})
