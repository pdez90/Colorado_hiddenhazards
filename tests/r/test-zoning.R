E23 <- script_env("zoning_2023.R"); EOT <- script_env("zoning_over_time.R")

test_that("zoning_2023 cat_of(): I-MX is industrial mixed use, Industrial is housing-not-allowed, MixedUse*/Residential*/Commercial map to their categories", {
  out <- E23$cat_of(c("Industrial", "MixedUse_High", "Residential_Low", "MobileHome", "Commercial", "OpenSpace", "Industrial"), c("I-A", "C-MX-5", "E-SU-D", "MH", "C-1", "OS-A", "I-MX-3"))
  expect_equal(as.character(out), c(E23$CATS[1], E23$CATS[3], E23$CATS[4], E23$CATS[4], E23$CATS[5], E23$CATS[6], E23$CATS[2]))
  expect_true(is.factor(out)); expect_equal(levels(out), E23$CATS)
})

to_ll <- function(x, y) { p <- sf::st_transform(sf::st_sfc(sf::st_point(c(x, y)), crs = UTM), 4326); sf::st_coordinates(p)[1, ] }

test_that("zoning_2023 locate(): a site in no polygon takes the nearest polygon within 50 m; farther sites stay unmatched and are counted", {
  ZJ <- sf::st_sf(zone2023 = factor(c(E23$CATS[1], E23$CATS[4]), E23$CATS), GenZone2 = c("Industrial", "Residential_Low"), Local_zon = c("I-A", "E-SU-D"), jurisd = "Denver",
                  geometry = sf::st_sfc(sq(0, 0, 1000), sq(1200, 0, 1000), crs = UTM))
  E23$ZJ <- ZJ; E23$AREA <- sf::st_sfc(sq(-500, -500, 4000), crs = UTM); E23$MATCH <- list()
  pts <- rbind(to_ll(500, 500), to_ll(1030, 500), to_ll(1100, 500), to_ll(600, 600), to_ll(1150, 2500))   # inside A; 30 m from A (gap); 100 m from both; inside A; a duplicate id 1,500 m away
  d <- data.table(site_id = c(1L, 2L, 3L, 4L, 4L), lon = pts[, 1], lat = pts[, 2], GEOID = c("08031000100", "08031000100", "08005000100", "08031000100", "08031000100"))
  invisible(capture.output(r <- E23$locate(copy(d), "site_id", "test")))
  expect_equal(r[site_id == 1, match], "inside polygon"); expect_equal(as.character(r[site_id == 1, zone2023]), E23$CATS[1])
  expect_equal(r[site_id == 2, match], "nearest polygon within 50 m"); expect_equal(as.character(r[site_id == 2, zone2023]), E23$CATS[1])
  expect_false(3L %in% r$site_id)                       # 100 m from any polygon: left out
  expect_equal(r[site_id == 4, .N], 1); expect_equal(r[site_id == 4, match], "inside polygon")   # one row per site (the first)
  expect_equal(r[site_id == 2, where], "Denver County")
  expect_equal(unname(E23$MATCH$site_id[c("n_area", "near", "unmatched")]), c(4, 1, 1))
  expect_equal(E23$NEAR_M, 50)
})

test_that("zoning_2023 pct_tab(): percentages within each group", {
  d <- data.table(series = c("a", "a", "a", "b"), zone2023 = c("x", "x", "y", "y"))
  r <- E23$pct_tab(d, "series"); expect_equal(r[series == "a", n], 3); expect_equal(r[series == "a", x], 66.7); expect_equal(r[series == "b", y], 100)
})

test_that("zoning_over_time nza_cat(): the 2023 layer gets a 'Commercial (housing not allowed)' category kept apart from mixed use", {
  out <- EOT$nza_cat(c("I-MX-3", "I-A", "C-MX-5", "C-1", "E-SU-D", "MH", "OS-A"), c("MixedUse_High", "Industrial", "MixedUse_Med", "Commercial", "Residential_Low", "MobileHome", "OpenSpace"))
  expect_equal(out, c("Industrial mixed use", "Industrial", "Commercial or mixed use", "Commercial (housing not allowed)", "Residential", "Residential", "Open space, civic, other"))
  expect_true("Commercial (housing not allowed)" %in% EOT$CATS)
  expect_false("Commercial (housing not allowed)" %in% EOT$city_cat(c("I-MX-3", "I-A", "C-MX-5", "E-SU-D", "PUD-G 1", "OS-A"), c("Industrial", "Industrial", "Commercial Mixed Use", "Residential", "PUD", "Open Space")))
})

test_that("zoning_over_time city_cat(): the city layer's districts", {
  expect_equal(EOT$city_cat(c("I-MX-3", "I-A", "C-MX-5", "E-SU-D", "PUD-G 1", "OS-A"), c("Industrial", "Industrial", "Commercial Mixed Use", "Residential", "PUD", "Open Space")),
               c("Industrial mixed use", "Industrial", "Commercial or mixed use", "Residential", "PUD (custom district)", "Open space, civic, other"))
})

test_that("zoning 1955 inputs: industrial cell runs are disjoint I-1/I-2 runs on the scan's 16-px grid, and the 23 control points fit to within 20 m", {
  cl <- fread(file.path(ROOT, "data/raw/zoning_1955/zone_cells_1955.csv"))
  expect_setequal(unique(cl$zone), c("I-1", "I-2")); expect_true(all(cl$col1 >= cl$col0))
  expect_true(all(cl$row >= 0 & cl$row < 5847 %/% 16 & cl$col1 < 6000 %/% 16))
  ov <- cl[, .(c = unlist(Map(seq, col0, col1))), by = row][, .N, by = .(row, c)]; expect_true(all(ov$N == 1))   # no cell in two runs
  g <- fread(file.path(ROOT, "data/raw/zoning_1955/gcps_1955.csv")); expect_equal(nrow(g), 23L)
  fx <- lm(X ~ px_x + px_y + I(px_x^2) + I(px_x * px_y) + I(px_y^2), g); fy <- lm(Y ~ px_x + px_y + I(px_x^2) + I(px_x * px_y) + I(px_y^2), g)
  expect_lt(sqrt(mean(residuals(fx)^2 + residuals(fy)^2)), 20)
  ck <- fread(file.path(ROOT, "data/raw/zoning_1955/check_sample_1955.csv")); expect_equal(nrow(ck), 60L); expect_gte(mean(ck$predicted == ck$judged), 0.95)
})
