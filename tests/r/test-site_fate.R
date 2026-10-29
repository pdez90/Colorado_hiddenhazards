E <- script_env("site_fate.R")

test_that("addr_parts(): a letter suffix is dropped from the number, an address without a number keeps the street", {
  a <- E$addr_parts(c("4300A BLAKE ST", "Blake St", "1200 W Larimer Street Bldg 2", "2300 S. Santa Fe Dr", ""))
  expect_equal(a$num, c("4300", "", "1200", "2300", "")); expect_equal(a$sname, c("BLAKE", "BLAKE", "LARIMER", "SANTA FE", ""))
  expect_equal(a$dir, c("", "", "W", "S", "")); expect_equal(a$stype, c("ST", "ST", "ST", "DR", ""))
})

# candidate parcels within 40 m of one site point: the same address, the other side of the street (nearest), and two doors down
mk_pc <- function() { PC <- data.table(pkey = "p", SCHEDNUM = c("A", "B", "C", "D"), PROP_CLASS = "x", D_CLASS_CN = c("INDUSTRIAL-WAREHOUSE", "SINGLE FAMILY-RANCH", "COMMERCIAL-OFFICE", "VACANT LAND"),
                                        ZONE_ID = "I-A", ZONE_10 = "I-A", TOT_UNITS = 0, year_built = c(1950, 1980, 1990, NA), LAND_AREA = 1000,
                                        SITUS_ADDRESS_LINE1 = c("1200 LARIMER ST", "1201 LARIMER ST", "1210 LARIMER ST", "1205 BLAKE ST"), SITUS_ADDR_NBR = NA_character_, dist_m = c(15, 5, 20, 30))
  PC[, c("p_num", "p_dir", "p_sname", "p_stype") := E$addr_parts(SITUS_ADDRESS_LINE1)]; PC }
E$PC <- mk_pc()
site <- function(addr) data.table(site_id = 1L, address = addr, last_year = 1970, lat = 39.75, lon = -104.99, pkey = "p")

test_that("pick(): rule 1 same address beats the nearer parcel across the street", {
  s <- E$pick(site("1200 Larimer St"), "address"); expect_equal(s$SCHEDNUM, "A"); expect_equal(s$parcel_match, "same address")
  s2 <- E$pick(site("1200 W Larimer"), "address"); expect_equal(s2$SCHEDNUM, "A")   # a direction missing on one side is no conflict
})

test_that("pick(): rule 2 same street and side, nearest house number", {
  expect_equal(E$pick(site("1204 Larimer St"), "address")$SCHEDNUM, "A")      # even: 1200 (4 away) over 1210 (6 away)
  expect_equal(E$pick(site("1208 Larimer St"), "address")$SCHEDNUM, "C")
  s <- E$pick(site("1203 Larimer St"), "address"); expect_equal(s$SCHEDNUM, "B"); expect_equal(s$parcel_match, "same street and side, nearest number")
})

test_that("pick(): rule 3 same street, nearest parcel, for an address without a number", {
  s <- E$pick(site("Larimer St")[, street := address], "street"); expect_equal(s$SCHEDNUM, "B"); expect_equal(s$parcel_match, "same street, nearest parcel")
})

test_that("pick(): rule 4 nearest parcel of any street; no parcel within 40 m", {
  s <- E$pick(site("500 Wazee St"), "address"); expect_equal(s$SCHEDNUM, "B"); expect_equal(s$parcel_match, "nearest parcel")
  far <- site("1200 Larimer St")[, pkey := "elsewhere"]; s2 <- E$pick(far, "address"); expect_true(is.na(s2$SCHEDNUM)); expect_equal(s2$parcel_match, "no parcel within 40 m")
})

test_that("pick(): the type decides between streets of one name (Larimer St vs Larimer Ct)", {
  E$PC <- rbind(mk_pc(), mk_pc()[1][, `:=`(SCHEDNUM = "E", SITUS_ADDRESS_LINE1 = "1200 LARIMER CT", p_stype = "CT", dist_m = 1)])
  expect_equal(E$pick(site("1200 Larimer St"), "address")$SCHEDNUM, "A"); expect_equal(E$pick(site("1200 Larimer Ct"), "address")$SCHEDNUM, "E")
  E$PC <- mk_pc()
})

test_that("broad(): assessor classes to broad uses", {
  expect_equal(E$broad(c("SINGLE FAMILY-RANCH", "INDUSTRIAL-WAREHOUSE", "EXEMPT-SCHOOL", "EXEMPT-PARK", "VACANT LAND", "COMMERCIAL-OFFICE", NA, "FARM"), "I-A"),
               c("Residential", "Industrial / utility", "Civic / school / health", "Park / open space", "Vacant", "Commercial / office", "No parcel match", "Other"))
})
