test_that("every R script parses", {
  files <- list.files(file.path(ROOT, "R"), "\\.R$", full.names = TRUE)
  expect_gt(length(files), 40)
  for (f in files) expect_no_error(parse(f, keep.source = FALSE), message = basename(f))
})

test_that("app/app.R parses", {
  expect_no_error(parse(file.path(ROOT, "app", "app.R"), keep.source = FALSE))
})

test_that("the analysis scripts expose the functions the tests rely on", {
  need <- list(fetch_census.R = c("interp", "grouped_median", "num", "gj"), grf_eds.R = "ipums_ed", holc_covenants.R = c("fill_hisp_1940", "change_periods", "drop_small_classes", "change_model"),
               rezoning_denver.R = c("parse_doc", "fuzzy_zone", "new_code", "dedupe_changes", "same", "legal_name", "street_names", "place_streets", "place_subdiv", "sure_changes", "st_base"),
               ownership_denver.R = c("parcel_type", "is_condo_master", "unit_differs", "other_door", "addr_key"), housing_conditions_denver.R = c("addr_parts", "akey_of", "compat", "order_building_parcels", "nonres_addresses"),
               site_fate.R = c("pick", "addr_parts", "broad"), highways_denver.R = c("carriageway_weights", "route_of"), zoning_2023.R = c("cat_of", "locate"),
               zoning_over_time.R = c("nza_cat", "city_cat"), loc_sanborn_1903.R = c("st_base", "streets_label", "dmin", "exposure_of"), mlp_residential_history.R = c("pct_within_500", "kern", "pctl"),
               benchmarks.R = c("gisjoin_county", "has_edition"), statewide.R = c("county_region", "REG"), corridors.R = c("eg", "queen_listw"), health_models.R = c("z", "queen_listw"), ej_panel.R = "add_shares")
  for (f in names(need)) { e <- script_env(f); for (fn in need[[f]]) expect_true(is.function(e[[fn]]), label = paste(f, fn)) }
})
