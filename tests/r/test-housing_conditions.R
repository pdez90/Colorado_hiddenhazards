E <- script_env("housing_conditions_denver.R")

test_that("addr_parts(): house number, direction, street name and type, each spelled one way; units dropped", {
  a <- E$addr_parts(c("100 N Main St", "100 South Main Street Apt 2", "100 MAIN CT", "1200 ST PAUL ST", "100 Saint Paul Street #4", "100 W. 38th Ave.", "Main St", NA))
  expect_equal(a$num, c("100", "100", "100", "1200", "100", "100", "", ""))
  expect_equal(a$dir, c("N", "S", "", "", "", "W", "", ""))
  expect_equal(a$sname, c("MAIN", "MAIN", "MAIN", "ST PAUL", "ST PAUL", "38TH", "", ""))
  expect_equal(a$stype, c("ST", "ST", "CT", "ST", "ST", "AVE", "", ""))
})

test_that("akey_of(): N/S and ST/CT are kept apart (the old key dropped them)", {
  a <- E$addr_parts(c("100 N Main St", "100 S Main St", "100 Main St", "100 Main Ct", "Main St"))
  k <- E$akey_of(a)
  expect_equal(k, c("100 N MAIN ST", "100 S MAIN ST", "100 MAIN ST", "100 MAIN CT", ""))
  expect_equal(uniqueN(k[1:4]), 4)
})

test_that("compat(): a request matches a building wherever both give a part; a missing ZIP, direction or type is no conflict", {
  BK <- data.table(bkey = c("b1", "b2", "b3"), num = c("100", "100", "200"), dir = c("N", "S", ""), sname = c("MAIN", "MAIN", "OAK"), stype = c("ST", "ST", "AVE"), zip = c("80205", "80205", "80206"))
  Q <- data.table(i = 1:4, num = c("100", "100", "200", "200"), dir = c("", "N", "", "E"), sname = c("MAIN", "MAIN", "OAK", "OAK"), stype = c("ST", "", "", "AVE"), zip = c("80205", "", "80206", "80206"))
  m <- E$compat(Q, BK)
  expect_equal(m[i == 1, bkey], c("b1", "b2"))        # two buildings fit: not a unique match
  expect_equal(m[i == 2, bkey], "b1")                  # the direction decides
  expect_equal(m[i == 3, bkey], "b3")
  expect_equal(m[i == 4, bkey], "b3")                  # the building has no direction: no conflict
  u <- m[, if (.N == 1) .SD, by = i]; expect_equal(u$i, 2:4)
})

test_that("order_building_parcels(): the building's owner is the named family holding most of its rental units, ties broken the same way", {
  P <- data.table(SCHEDNUM = c("1", "2", "3", "4", "5"), bkey = c("b", "b", "b", "b", "c"),
                  owner_type = c("Unknown (no name recorded)", "Individual", "Company", "Company", "Individual"), g_family = c(9, 1, 2, 2, 3),
                  rental_units = c(40, 0, 3, 3, 1), units = c(40, 1, 3, 3, 1))
  o <- E$order_building_parcels(copy(P))
  expect_equal(o[bkey == "b", SCHEDNUM][1], "3")        # family 2 holds 6 rental units; the nameless master parcel never stands for the building
  expect_equal(o[bkey == "b", owner_type][1], "Company")
  expect_equal(o[bkey == "b", SCHEDNUM][1:2], c("3", "4"))
  P2 <- data.table(SCHEDNUM = c("7", "6"), bkey = "d", owner_type = "Individual", g_family = c(5, 6), rental_units = c(2, 2), units = c(2, 2))
  expect_equal(E$order_building_parcels(copy(P2))$SCHEDNUM, c("7", "6"))   # equal: lower family id first, then SCHEDNUM
})

test_that("nonres_addresses(): the addresses of non-residential parcels, except those shared with a residential parcel", {
  P0 <- data.table(SCHEDNUM = c("1", "2", "3", "4"), SITUS_ADDRESS_LINE1 = c("100 MAIN ST", "200 MAIN ST", "200 MAIN ST", "MAIN ST"), SITUS_ZIP = c("80205", "80205", "80205", "80205"))
  P <- data.table(SCHEDNUM = c("1", "3"), bkey = c("100 MAIN ST 80205", "200 MAIN ST 80205"))
  nr <- E$nonres_addresses(P0, P)
  expect_equal(nrow(nr), 0)                                                # 200 MAIN ST is also a residential building; MAIN ST has no number
  P0b <- rbind(P0, data.table(SCHEDNUM = "5", SITUS_ADDRESS_LINE1 = "300 OAK AVE", SITUS_ZIP = "80206"))
  nr2 <- E$nonres_addresses(P0b, P); expect_equal(nrow(nr2), 1); expect_equal(nr2$sname, "OAK"); expect_equal(nr2$zip, "80206")
})

test_that("z5(): five-digit ZIPs", { expect_equal(E$z5(c("80205-1234", "80205", NA, "8020")), c("80205", "80205", "", "8020")) })
