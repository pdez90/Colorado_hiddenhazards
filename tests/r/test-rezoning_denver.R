E <- script_env("rezoning_denver.R")

# ---------------------------------------------------------------- synthetic ordinance texts (as the OCR'd scans look)
ORD1 <- c("=== page 1 ===", "BOOK A-14 PAGE 690",
  "ORDINANCE NO. 12, SERIES OF 1930. A BILL For an ordinance amending the zone map of Ordinance No. 14, Series of 1925.",
  "BE IT ENACTED BY THE COUNCIL OF THE CITY AND COUNTY OF DENVER:",
  "Section 1. That the zone map be amended so that the following described property is changed from Residence \"B\" District to Business \"C\" District:",
  "Beginning at the intersection of the center line of West 38th Avenue and the center line of Tejon Street, thence east along the center line of",
  "West 38th Avenue to the center line of Shoshone Street, thence south 125 feet, thence west to Tejon Street, thence north to the point of beginning.",
  "Section 2. This ordinance shall take effect upon publication. PASSED AND ENACTED March 3, 1930.",
  "=== page 2 ===", "BOARD OF ADJUSTMENT, City and County of Denver. To the Honorable Mayor and City Council.",
  "Gentlemen: The Board of Adjustment recommends that the property described be changed from Residence \"B\" District to Business \"C\" District,",
  "and further that Block 7, Highland Park be changed from Residence \"A\" District to Residence \"B\" District. Respectfully submitted.")
ORD2 <- c("ORDINANCE NO. 44 SERIES OF 1938. BE IT ENACTED BY THE COUNCIL:",
  "Section 1. That the following described property be and the same is hereby chaaged fror:i Reshlence \"A\" District t.o Industrial \"A\" District:",
  "Beginning at a point on the center line of 47th Avenue 300 feet east of Milwaukee Street, thence east 600 feet, thence south to the alley.",
  "Section 2. That the following be changed tram Residence \"e\" District to Business \"B\" District: Lots 1 to 4, Block 2, Ivanhoe.",
  "Section 3. This ordinance shall take effect upon publication.")
ORD3 <- c("ORDINANCE NO. 7 SERIES OF 1955. BE IT ENACTED BY THE COUNCIL:",
  "Section 1. That the zoning map of the Revised Municipal Code be amended so that the following is changed from R-2 to B-4: Lots 1 to 12, Block 4, West Lawn Gardens.",
  "Section 2. That the following is changed f.torn R--0 t.o I-1: Lots 5 to 8, Block 56, Evanston, 2nd Filing.",
  "Section 3. That the following is changed .troa R-1 to R-3: Lots 9 to 12, Block 9, Cole.")
ORD4 <- c("ORDINANCE NO. 90 SERIES OF 1947. BE IT ENACTED BY THE COUNCIL:",
  "Section 1. That the zone map be amended as to the property described in Exhibit A attached hereto (illegible).",
  "Section 2. This ordinance shall take effect upon publication. PASSED March 1947.",
  "PUBLISHER'S AFFIDAVIT. State of Colorado, County of Denver. The undersigned, being first duly sworn, says that the following notice was published in The Daily Journal:",
  "Ordinance No. 90: the following property is changed from Residence \"A\" District to Industrial \"B\" District: Beginning at the intersection of 47th Avenue and Milwaukee Street, thence east.")
ORD5 <- c("ORDINANCE NO. 3 SERIES OF 1931. BE IT ENACTED BY THE COUNCIL: Section 1. That the salary of the zoning inspector be fixed at $200 a month. PETITION of the owners for a sidewalk.")
wtxt <- function(lines, name) { f <- file.path(tempdir(), name); writeLines(lines, f); f }
F1 <- wtxt(ORD1, "1930_012.txt"); F2 <- wtxt(ORD2, "1938_044.txt"); F3 <- wtxt(ORD3, "1955_007.txt"); F4 <- wtxt(ORD4, "1947_090.txt"); F5 <- wtxt(ORD5, "1931_003.txt")

test_that("parse_doc(): reads the enacted change and ignores the Board of Adjustment's letter after the ordinance", {
  d <- E$parse_doc(F1)
  expect_equal(nrow(d), 1)
  expect_equal(d$from_type, "residence"); expect_equal(d$from_letter, "B"); expect_equal(d$to_type, "business"); expect_equal(d$to_letter, "C")
  expect_false(d$annexation); expect_equal(d$ordinance, "1930_012")
  expect_match(d$desc, "^Residence .B. District to Business .C. District: Beginning at")
  expect_false(grepl("Highland Park", d$desc))
})

test_that("parse_doc(): OCR forms of 'changed from' and 't.o', and a quoted 'e' read as C", {
  d <- E$parse_doc(F2)
  expect_equal(nrow(d), 2)
  expect_equal(d$from_type, c("residence", "residence")); expect_equal(d$from_letter, c("A", "C"))
  expect_equal(d$to_type, c("industrial", "business")); expect_equal(d$to_letter, c("A", "B"))
  expect_match(d$desc[2], "Block 2, Ivanhoe")
})

test_that("parse_doc(): 1955 code changes read R-2 / B-4, OCR 'R--0' and 'changed .troa'", {
  d <- E$parse_doc(F3)
  expect_equal(nrow(d), 3)
  expect_equal(d$from_code, c("R-2", "R-0", "R-1")); expect_equal(d$to_code, c("B-4", "I-1", "R-3"))
  expect_true(all(is.na(d$from_type)))
  expect_match(d$desc[1], "West Lawn Gardens"); expect_false(grepl("Evanston", d$desc[1]))   # the description stops at the next change
})

test_that("parse_doc(): falls back to the newspaper reprint when the ordinance body yields no readable change", {
  d <- E$parse_doc(F4)
  expect_equal(nrow(d), 1); expect_equal(d$from_letter, "A"); expect_equal(d$to_type, "industrial"); expect_equal(d$to_letter, "B")
})

test_that("parse_doc(): an ordinance with no change phrase returns NULL", { expect_null(E$parse_doc(F5)) })

test_that("fuzzy_zone(): two wrong letters allowed, the letter read after the word, e -> C, no E districts", {
  expect_equal(E$fuzzy_zone('Reshlence "A" District'), c("residence", "A"))
  expect_equal(E$fuzzy_zone('Cormnercial "B" District'), c("commercial", "B"))
  expect_equal(E$fuzzy_zone('Residence "e" District'), c("residence", "C"))
  expect_equal(E$fuzzy_zone('Residence "E" District'), c("residence", NA))
  expect_equal(E$fuzzy_zone('Residence 11 B" District'), c("residence", "B"))   # OCR reads the opening quote as 11
  expect_equal(E$fuzzy_zone("the alley"), c(NA, NA))
})

test_that("new_code(): R-2, OCR R--0, R~2 and letters O/I/l read as digits", {
  expect_equal(E$new_code("changed to R-2 District"), "R-2"); expect_equal(E$new_code("R--0"), "R-0"); expect_equal(E$new_code("B ~ 4"), "B-4")
  expect_equal(E$new_code("I-l District"), "I-1"); expect_equal(E$new_code("R-O"), "R-0"); expect_true(is.na(E$new_code("Residence B")))
})

test_that("group_of(): codes and types map to the four groups", {
  expect_equal(unname(E$group_of(c(NA, NA, NA, NA, "residence", "commercial"), c("R-2", "B-4", "I-1", "P-1", NA, NA))),
               c("Residential", "Business or commercial", "Industrial", "Parking", "Residential", "Business or commercial"))
})

# ---------------------------------------------------------------- dedupe
mk_ch <- function(...) { d <- rbindlist(list(...), fill = TRUE); if (!"ux" %in% names(d)) d[, ux := NA_real_]; if (!"uy" %in% names(d)) d[, uy := NA_real_]; d[, placed_by := "x"]; d }
r <- function(ord, from, to, desc, ux = NA_real_, uy = NA_real_) data.table(ordinance = ord, from = from, to = to, desc = desc, ux = ux, uy = uy)

test_that("dedupe_changes(): a repeat without its own boundary within 300 m (or unplaced) is dropped; separate areas are kept", {
  d <- mk_ch(r("o1", "Residence B", "Business C", "Residence B District to Business C District: Beginning at Tejon Street thence east", 100, 100),
             r("o1", "Residence B", "Business C", "Residence B District to Business C District as recommended", 250, 100),      # repeat, no boundary, 150 m away
             r("o1", "Residence B", "Business C", "Residence B to Business C: Beginning at Zuni Street thence north", 5000, 5000),  # another area, own boundary
             r("o2", "Residence B", "Business C", "Residence B to Business C District, as above"))                               # a different ordinance
  out <- E$dedupe_changes(d)
  expect_equal(nrow(out), 3); expect_false(any(grepl("as recommended", out$desc)))
  expect_false(any(c("beg", "row0", "dup", "has_beg") %in% names(out)))
  expect_equal(E$DUP_M, 300)
})

test_that("dedupe_changes(): a repeat without a boundary more than 300 m away is kept unless another copy has a boundary", {
  d <- mk_ch(r("o1", "Residence B", "Business C", "Residence B to Business C District, the whole tract", 100, 100),
             r("o1", "Residence B", "Business C", "Residence B to Business C District, the whole area", 900, 100))
  expect_equal(nrow(E$dedupe_changes(d)), 2)
  d2 <- mk_ch(r("o1", "Residence B", "Business C", "Residence B to Business C District: Beginning at Tejon Street", 100, 100),
              r("o1", "Residence B", "Business C", "A portion of this area will be changed from Residence B to Business C District", 9000, 9000))
  expect_equal(nrow(E$dedupe_changes(d2)), 1)   # the passing mention goes, however far away it was placed
})

test_that("dedupe_changes(): same() lets a '?' letter match any letter; the same boundary text is one change", {
  expect_true(E$same("Residence ?", "Residence B")); expect_true(E$same("Residence B", "Residence ?")); expect_false(E$same("Residence B", "Residence C")); expect_false(E$same("Residence ?", "Business B"))
  d <- mk_ch(r("o1", "Residence ?", "Business C", "Beginning at Tejon Street thence east 100 feet", 100, 100),
             r("o1", "Residence B", "Business C", "Beginning at Tejon Street thence east 100 feet", 2000, 2000))   # same boundary, placed differently
  expect_equal(nrow(E$dedupe_changes(d)), 1)
})

# ---------------------------------------------------------------- street and subdivision names
test_that("st_base(): ordinals, types and directions are stripped", {
  expect_equal(E$st_base(c("Thirty-Eighth Street", "38th Ave", "W. 38th Avenue", "Larimer St", "East Colfax Avenue", NA)), c("38", "38", "38", "LARIMER", "COLFAX", ""))
  expect_equal(E$sfx(c(1, 2, 3, 11, 12, 21, 38)), c("1ST", "2ND", "3RD", "11TH", "12TH", "21ST", "38TH"))
})

test_that("legal_name(): keeps directional words next to a name, drops generic words, lot/block codes and the tail after EXC/COM/BEG", {
  expect_equal(E$legal_name("L1 TO 4 BLK 2 E CAPITOL HILL ADD"), "E CAPITOL HILL")
  expect_equal(E$legal_name("L5 B3 BELLEVUE W"), "BELLEVUE W")
  expect_equal(E$legal_name("N 1/2 OF LOT 3 BLK 2 SMITHS ADD"), "SMITHS")
  expect_equal(E$legal_name("L 7 BLK 56 EVANSTON 2ND FLG EXC REAR 10 FT"), "EVANSTON 2ND")
  expect_equal(E$legal_name("BURNS-MONTCLAIR SUB L12 B4"), "BURNS MONTCLAIR")
  expect_equal(E$legal_name(""), "")
})

RO_df <- function() { RO <- sf::st_sf(dkey = c("W 48", "E 48", "MILWAUKEE", "TEJON"), base = c("48", "48", "MILWAUKEE", "TEJON"),   # keys as st_base() writes them
  geometry = sf::st_sfc(line_xy(0, 100, 1000, 100), line_xy(1000, 100, 2000, 100), line_xy(500, 0, 500, 1000), line_xy(900, 0, 900, 1000), crs = UTM)); RO }

test_that("street_names(): '48th Avenue' and 'West 48th Avenue' are one street, not a crossing", {
  E$RO <- RO_df(); E$CX <- new.env()
  expect_setequal(E$street_names("the center line of 48th Avenue and West 48th Avenue and Milwaukee Street"), c("W 48", "MILWAUKEE"))
  expect_setequal(E$street_names("West 48th Avenue, Milwaukee Street and Tejon Street"), c("W 48", "MILWAUKEE", "TEJON"))
  expect_equal(E$street_names("Elm Street and Oak Avenue"), character(0))   # streets not in today's network
})

test_that("place_streets(): the crossings of the named streets, pairs on one street excluded", {
  E$RO <- RO_df(); E$CX <- new.env()
  p <- E$place_streets("West 48th Avenue thence to Milwaukee Street thence to Tejon Street")
  expect_equal(p$n, 2); expect_equal(p$x, 700); expect_equal(p$y, 100); expect_equal(p$names, 3)
  p2 <- E$place_streets("48th Avenue and West 48th Avenue and Milwaukee Street")
  expect_equal(p2$n, 1); expect_equal(c(p2$x, p2$y), c(500, 100))
  expect_null(E$place_streets("West 48th Avenue only"))
})

test_that("place_subdiv(): the whole name or at least two words of it; one word of a longer name is not enough", {
  E$SUBX <- data.table(skey = c("BURNS MONTCLAIR", "BURNS MONTCLAIR", "BURNS", "EVANSTON", "EVANSTON"), blk = c("4", "5", "4", "56", "57"), ux = c(100, 200, 5000, 9000, 9100), uy = c(100, 200, 5000, 9000, 9100), parcels = c(10, 10, 10, 10, 10))
  E$SUBS <- data.table(skey = c("BURNS MONTCLAIR", "BURNS", "EVANSTON"), n = 20)
  a <- E$place_subdiv("Lots 1 to 12, Block 4, Burns Montclair"); expect_true(a$with_block); expect_equal(c(a$x, a$y), c(100, 100))
  b <- E$place_subdiv("Block 4, Burns Montclair Heights"); expect_equal(c(b$x, b$y), c(100, 100))              # two words of the name match
  expect_null(E$place_subdiv("Block 4, Burns Park"))                                                          # "Burns" alone is not "Burns Park"
  c1 <- E$place_subdiv("Lots 5 to 8, Block 56, Evanston, 2nd Filing"); expect_equal(c(c1$x, c1$y), c(9000, 9000))   # a filing suffix is fine
  d <- E$place_subdiv("Block 9, Burns Montclair"); expect_false(d$with_block); expect_equal(d$n, 2)              # no such block: the subdivision's parcels
  expect_null(E$place_subdiv("thence east along the center line of 47th Avenue"))
})

test_that("blocks_in(): block lists and ranges", {
  expect_equal(E$blocks_in("BLOCKS 4 TO 7 AND BLOCK 12"), c(4, 5, 6, 7, 12)); expect_equal(E$blocks_in("BLOCK 56"), 56)
})

test_that("sure_changes(): subdivision-and-block placements, or street crossings that a subdivision confirmed", {
  d <- data.table(annexation = c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE), holc = c("D", "C", "A", "B", "D", NA),
                  placed_by = c("subdivision and block", "subdivision and block (streets agree)", "street crossings", "street crossings", "subdivision and block", "subdivision and block"),
                  m_between_methods = c(NA, 120, 80, NA, NA, NA))
  expect_equal(which(d[, seq_len(.N)] %in% E$sure_changes(copy(d)[, i := .I])$i), c(1, 2, 3))
})
