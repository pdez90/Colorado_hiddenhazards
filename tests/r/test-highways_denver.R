E <- script_env("highways_denver.R")

# two parallel opposite one-way carriageways 30 m apart (1 km each) and one single freeway line (1 km) elsewhere
mk_H <- function(e1 = NA, s2 = 1960) sf::st_sf(name = c("I-25", "I-25", "I-70"), highway = "motorway", kind = "Freeway", start_year = c(1960, s2, 1965), end_year = c(e1, NA, NA),
  geometry = sf::st_sfc(line_xy(0, 0, 1000, 0), line_xy(1000, 30, 0, 30), line_xy(0, 5000, 1000, 5000), crs = UTM))

test_that("carriageway_weights(): opposite carriageways within 60 m each weigh 1/2, a single line weighs 1, so km of road are not doubled", {
  H <- mk_H(); w <- E$carriageway_weights(H)
  expect_equal(w, c(0.5, 0.5, 1))
  km <- sum(w * as.numeric(sf::st_length(H))) / 1000
  expect_equal(km, 2)                                            # 1 km of divided road + 1 km of single line
  expect_equal(sum(as.numeric(sf::st_length(H))) / 1000, 3)      # the unweighted sum counts the carriageways twice
  expect_equal(E$PAIR_M, 60)
})

test_that("carriageway_weights(): only a carriageway running the other way and in service at the same time pairs", {
  H <- mk_H(e1 = 1955, s2 = 1960); expect_equal(E$carriageway_weights(H), c(1, 1, 1))   # the first was removed before the second opened
  Hs <- mk_H(); sf::st_geometry(Hs)[2] <- sf::st_sfc(line_xy(0, 30, 1000, 30)); expect_equal(E$carriageway_weights(Hs), c(1, 1, 1))   # same direction: not a pair
  Hl <- mk_H(); Hl$highway[2] <- "motorway_link"; expect_equal(E$carriageway_weights(Hl), c(1, 1, 1))   # ramps are not freeway ways
  Hm <- mk_H(); Hm$kind[1:2] <- "Major road"; expect_equal(E$carriageway_weights(Hm), c(1, 1, 1))
})

test_that("carriageway_weights(): a partial overlap gives w = 1 - f/2", {
  H <- mk_H(); sf::st_geometry(H)[2] <- sf::st_sfc(line_xy(1000, 30, 500, 30))   # the second carriageway covers only the eastern half
  w <- E$carriageway_weights(H)
  expect_equal(w[2], 0.5)
  expect_true(w[1] > 0.7 && w[1] < 0.8)   # about half of line 1 lies within 60 m of line 2 (plus the buffer's end cap)
})

test_that("route_of(): the ref, else the route in the name; the Valley Highway is I-25; a second ref is dropped", {
  expect_equal(E$route_of(c("I-70", "", NA, NA, "I-25;US 87", NA), c("x", "I-225", "Valley Highway", "I 76", "x", NA)), c("I-70", "I-225", "I-25", "I-76", "I-25", ""))
  expect_equal(E$yr(c("1964-06-01", "~1958", NA)), c(1964L, 1958L, NA))
})
