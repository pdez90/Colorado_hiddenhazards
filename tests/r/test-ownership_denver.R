E <- script_env("ownership_denver.R")

test_that("parcel_type(): residential classes; mixed-use buildings only with homes; hotels and motels excluded", {
  cls <- c("RESIDENTIAL-CONDOMINIUM", "RESIDENTIAL-ROWHOUSE", "RESIDENTIAL-DUPLEX", "RESIDENTIAL-TRIPLEX", "RESIDENTIAL-APARTMENT", "RESIDENTIAL-4 TO 8 UNITS", "RESIDENTIAL-SENIOR CITIZEN APT",
           "RESIDENTIAL-SENIOR CITIZEN APT", "RETAIL W/MIXED USE", "RETAIL W/MIXED USE", "HOTEL W/MIXED USE", "MOTEL W/MIXED USE", "SFR-RANCH", "COMMERCIAL-OFFICE", "VACANT LAND")
  tot <- c("1", "1", "2", "3", "12", "6", "80", "0", "4", "0", "120", "40", "1", "0", "")
  out <- E$parcel_type(cls, tot)
  expect_equal(out, c("Condominium unit", "Rowhouse / townhouse", "Duplex / triplex", "Duplex / triplex", "Apartment building (4+ units)", "Apartment building (4+ units)", "Apartment building (4+ units)",
                      NA, "Mixed-use building (homes with shops or offices)", NA, NA, NA, "Single-family house", NA, NA))
})

test_that("is_condo_master(): a condominium parcel with no owner name and the building's unit count is the master, not a home", {
  expect_equal(E$is_condo_master(c("Condominium unit", "Condominium unit", "Condominium unit", "Apartment building (4+ units)"), c("", "  ", "JANE DOE", ""), c("48", "1", "48", "48")),
               c(TRUE, FALSE, FALSE, FALSE))
})

test_that("unit_differs(): only clearly different unit numbers count", {
  expect_equal(E$unit_differs(c("N207", "F8", "6101", "204A", "201", "", "2H"), c("207N", "8F", "101", "204", "305", "4", "3H")), c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, TRUE))
})

test_that("unit_of() and addr_key(): unit numbers and the house number + street key", {
  expect_equal(E$unit_of(c("1234 MAIN ST APT 2H", "1234 MAIN ST # 0207", "1234 MAIN ST UNIT B", "1234 MAIN ST")), c("2H", "207", "B", ""))
  expect_equal(E$addr_key(c("1234 N. Main St", "1234 Main Street Unit 3", "1234 S MAIN CT", NA)), c("1234 MAIN", "1234 MAIN", "1234 MAIN", ""))
})

test_that("other_door(): a duplex owner mailed at the other door (same street, ZIP and side, within 4 numbers) lives in the building", {
  own_k <- c("1236 MAIN", "1235 MAIN", "1244 MAIN", "1236 MAIN", "1236 OAK", "1236 MAIN", "MAIN")
  sit_k <- c("1234 MAIN", "1234 MAIN", "1234 MAIN", "1234 MAIN", "1234 MAIN", "1234 MAIN", "1234 MAIN")
  own_zip <- c("80205", "80205", "80205", "80206", "80205", "", "80205"); sit_zip <- rep("80205", 7)
  expect_equal(E$other_door(own_k, sit_k, own_zip, sit_zip), c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE))
  #                                 other door | across the street | 10 numbers away | other ZIP | other street | no mailing ZIP | no number
})

test_that("nm_norm() and addr_norm(): legal suffixes and street spellings are normalised", {
  expect_equal(E$nm_norm(c("SMITH PROPERTIES, L.L.C.", "SMITH PROPERTY LLC", "THE JOHN SMITH REVOCABLE LIVING TRUST")), c("SMITH PROPERTY", "SMITH PROPERTY", "JOHN SMITH"))
  expect_equal(E$addr_norm(c("P.O. Box 12", "1234 North Main Street Suite 3", NA), c("80205-1234", "80205", "80205")), c("POBOX 12 80205", "1234 N MAIN ST STE 3 80205", NA))
})
