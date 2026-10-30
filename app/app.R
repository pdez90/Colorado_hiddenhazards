# Denver Hidden Hazards — historical hazardous manufacturing in Denver (Directory of Colorado Manufacturers, 1965–1992 complete editions,
# and hazardous trades in the Colorado State Business Directory, 1871–1956), the 1880–2020 censuses, the 1925 zoning ordinance, the 1938 HOLC map,
# current EPA TRI facilities, cleanup sites, schools and health facilities, and CDPHE EnviroScreen. Every map, table and chart covers Denver
# (the City and County of Denver and the 147 study tracts within 10 km of downtown); Colorado-wide results are on the 'Colorado trends' tab.
# Run from the repository root:  shiny::runApp("app")

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(leaflet); library(sf); library(dplyr)
  library(ggplot2); library(plotly); library(DT); library(tidyr)
})
sf_use_s2(FALSE)

# ---------------------------------------------------------------- data
dd <- function(f) file.path("data", f)
sites   <- read.csv(dd("sites.csv"), colClasses = c(GEOID = "character", zip = "character"))
site_yr <- read.csv(dd("site_years.csv"))
tri     <- read.csv(dd("tri_facilities.csv"), colClasses = c(GEOID = "character"))
cleanup <- read.csv(dd("cleanup_sites.csv"))
schools <- read.csv(dd("schools.csv"), colClasses = c(GEOID = "character"))
health  <- read.csv(dd("health_facilities.csv"), colClasses = c(GEOID = "character"))
hist    <- if (file.exists(dd("historical_sites.csv"))) read.csv(dd("historical_sites.csv"), colClasses = c(GEOID = "character")) else NULL
if (!is.null(hist)) hist <- hist |> mutate(persists_to_1961plus = as.logical(persists_to_1961plus) %in% TRUE, fe_hazard = as.logical(fe_hazard) %in% TRUE,
                                           across(c(street, dcm_name, dcm_years, link), ~ coalesce(as.character(.x), "")))
precur  <- if (file.exists(dd("site_precursors.csv"))) read.csv(dd("site_precursors.csv")) else data.frame(site_id = character(), hist_first_year = integer(), hist_names = character())
# firms at each site (one row per firm linked across editions): what the directory says it made, years, size
firms   <- if (file.exists(dd("site_firms.csv"))) read.csv(dd("site_firms.csv"), colClasses = c(sic = "character", employees = "character")) else NULL
firm_html <- if (is.null(firms)) setNames(character(), character()) else local({
  f <- firms |> mutate(hazardous = as.logical(hazardous) %in% TRUE, makes = coalesce(makes, ""), employees = coalesce(employees, ""),
                       yrs = ifelse(first_year == last_year, as.character(first_year), paste0(first_year, "–", last_year)),
                       row = sprintf("<tr%s><td>%s%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
                                     ifelse(hazardous, " style='background:#fbe9e2'", ""), htmltools::htmlEscape(name),
                                     ifelse(hazardous, " <span title='hazardous sector'>&#9888;</span>", ""), yrs,
                                     htmltools::htmlEscape(makes), ifelse(is.na(established), "", established), htmltools::htmlEscape(employees)))
  h <- f |> group_by(site_id) |> summarise(html = paste0(
    "<div style='max-height:200px;overflow-y:auto;font-size:11px'><table class='table table-sm' style='margin:0'>",
    "<tr><th>Firm</th><th>Listed</th><th>What it made (directory)</th><th>Est.</th><th>Employees</th></tr>",
    paste(row, collapse = ""), "</table></div>"), .groups = "drop")
  setNames(h$html, h$site_id) })
mix     <- if (file.exists(dd("industry_mix.csv"))) read.csv(dd("industry_mix.csv")) else NULL
radium  <- if (file.exists(dd("radium_firms.csv"))) read.csv(dd("radium_firms.csv")) else NULL
longev  <- if (file.exists(dd("firm_longevity.csv"))) read.csv(dd("firm_longevity.csv")) else NULL
tracts  <- st_read(dd("enviroscreen_tracts.geojson"), quiet = TRUE) |> mutate(GEOID = as.character(GEOID))
by_year_dir <- if (dir.exists(dd("by_year"))) dd("by_year") else file.path("..", "data", "by_year")
pre60 <- if (file.exists(dd("pre1960_listings.csv"))) read.csv(dd("pre1960_listings.csv")) else NULL      # business-directory hazardous trades by edition (pipeline/historical/)
validation  <- local({ f <- c(dd("geocoding_validation_frs.csv"), "../data/results/geocoding_validation_frs.csv"); f <- f[file.exists(f)]
                       if (length(f)) read.csv(f[1]) else NULL })
# historical census (NHGIS 1940-2020 on 2010 tracts; IPUMS full count 1880-1940; Brown 1880 HGIS) and corridor layers: R/app_census_layers.R
rd_opt <- function(f, ...) if (file.exists(dd(f))) read.csv(dd(f), ...) else NULL
den_tr   <- if (file.exists(dd("co_tracts_2010.geojson"))) st_read(dd("co_tracts_2010.geojson"), quiet = TRUE) |> mutate(GEOID = as.character(GEOID), core = as.logical(core) %in% TRUE) else NULL
den_pan  <- rd_opt("tract_panel.csv", colClasses = c(GEOID = "character")); if (!is.null(den_pan)) { den_pan$core <- as.logical(den_pan$core) %in% TRUE; for (k in c("p_owner", "mval_2020", "mrent_2020", "hmda_denial", "hmda_denial_hisp", "hmda_denial_black", "hmda_pct_hisp_apps", "hmda_apps")) if (!k %in% names(den_pan)) den_pan[[k]] <- NA_real_ }
hmda_g <- rd_opt("hmda_by_grade.csv"); hmda_m <- rd_opt("hmda_grade_model.csv")
ej_mod   <- rd_opt("ej_panel_models.csv"); ej_rev <- rd_opt("ej_panel_reverse.csv"); ej_dec <- rd_opt("ej_panel_by_decade.csv"); ej_late <- rd_opt("ej_panel_legacy_sites.csv")
cells    <- rd_opt("corridor_cells.csv"); eg <- rd_opt("corridor_eg.csv"); trans <- rd_opt("corridor_transitions.csv")
ed80     <- rd_opt("denver_1880_eds.csv"); ed80_poly <- if (file.exists(dd("denver_1880_eds.geojson"))) st_read(dd("denver_1880_eds.geojson"), quiet = TRUE) |> mutate(ED = as.integer(ED)) else NULL; f80 <- rd_opt("denver_1880_firms.csv"); d80 <- rd_opt("denver_1880_distance.csv"); m80 <- rd_opt("denver_1880_models.csv"); g80 <- rd_opt("denver_1880_ed_groups.csv")
city1880 <- rd_opt("denver_city_1880_1940.csv"); dis_fixed <- rd_opt("ed_dissimilarity_fixed_grid.csv")
co_cnty  <- if (file.exists(dd("co_counties_1880_1940.geojson"))) st_read(dd("co_counties_1880_1940.geojson"), quiet = TRUE) else NULL   # R/county_panel_1880_1940.R
eds      <- if (file.exists(dd("denver_eds.geojson"))) st_read(dd("denver_eds.geojson"), quiet = TRUE) else NULL                       # R/denver_eds_analysis.R
trd      <- if (file.exists(dd("denver_tracts.geojson"))) st_read(dd("denver_tracts.geojson"), quiet = TRUE) else NULL; trd_m <- rd_opt("denver_tracts_models.csv"); trd_s <- rd_opt("denver_tracts_shares.csv"); trd_g <- rd_opt("denver_tracts_groups.csv")   # R/denver_tracts_1950_2020.R
TR_VARS  <- c("White (%, race)" = "p_white", "Black (%)" = "p_black", "Hispanic (%)" = "p_hisp", "Foreign born (%)" = "p_fb", "Below poverty (%)" = "p_pov", "Owner-occupied (%)" = "p_owner", "Median home value (2020 $)" = "mval_2020", "Median rent (2020 $)" = "mrent_2020", "Hazardous firms in the decade" = "firms", "Distance to nearest firm (m)" = "dist_m")
eds_f    <- rd_opt("denver_eds_firms.csv"); eds_g <- rd_opt("ed_year_groups.csv"); eds_m <- rd_opt("ed_distance_models.csv")
ED_LABELS <- c(pct_black = "Black (%)", pct_white = "White (%)", pct_fb = "Foreign born (%)", pct_fb_mexico = "Mexican-born (%)", pct_fb_europe = "European-born (%)", pct_fb_asia = "Asian-born (%)", pct_hisp = "Hispanic (%)",
               pct_foreign_parentage = "Foreign or mixed parentage (%)", pct_recent_immig = "Immigrated in the last 10 years (%)", pct_naturalized = "Naturalized citizens (% of foreign born)", pct_noncitizen = "Non-citizens (% of foreign born)",
               pct_laborers = "Laborers (% of population)", pct_haz_industry = "Employed in hazardous industries (%)", pct_manufacturing = "Employed in manufacturing (%)", pct_railroad = "Employed on railroads (%)", pct_unemployed = "Unemployed (% of labour force)",
               mean_sei = "Mean socioeconomic index (SEI)", mean_occscore = "Mean occupational income score", median_wage = "Median wage income (1940 $)",
               pct_illiterate = "Illiterate (% aged 10+)", pct_in_school = "In school (% of children)", pct_hs_grad = "High-school graduates (% aged 25+)",
               pct_owner_hh = "Owner-occupied households (%)", pct_mortgaged = "Mortgaged (% of owner households)", median_value = "Median home value ($)", median_rent = "Median monthly rent ($)", pct_radio = "Households with a radio (%)",
               pct_boarders = "Non-relatives of the household head: boarders, lodgers, employees (% of population)", pct_group_quarters = "In group quarters (%)", pct_movers = "Moved since 1935 (%)", pct_movers_other_state = "Moved from another state since 1935 (%)",
               pct_veterans = "Veterans (% of adults)", children_per_mother = "Children ever born per mother", firms = "Hazardous firms in the decade", dist_m = "Distance to nearest firm (m)")
ED_VARS  <- c("Black (%)" = "pct_black", "Foreign born (%)" = "pct_fb", "Mexican-born (%)" = "pct_fb_mexico", "Hispanic (%)" = "pct_hisp", "Laborers (% of population)" = "pct_laborers",
              "Foreign or mixed parentage (%)" = "pct_foreign_parentage", "Hazardous firms in the decade" = "firms", "Distance to nearest firm (m)" = "dist_m")   # replaced by whatever the district file provides
if (!is.null(eds)) { have <- names(ED_LABELS)[names(ED_LABELS) %in% names(eds)]; have <- have[sapply(have, function(k) any(!is.na(eds[[k]])))]; if (length(have)) ED_VARS <- setNames(have, ED_LABELS[have]) }
holc     <- if (file.exists(dd("holc_denver.geojson"))) st_read(dd("holc_denver.geojson"), quiet = TRUE) else NULL      # R/holc_covenants.R
coven    <- rd_opt("covenants_denver.csv"); holc_bd <- rd_opt("holc_boundary.csv"); holc_gap <- rd_opt("holc_gaps.csv"); holc_ind <- rd_opt("holc_industry_periods.csv"); bm_state <- rd_opt("cbp_vs_directory_state.csv"); bm_cty <- rd_opt("cbp_vs_directory_county.csv"); bm_nh <- rd_opt("nhgis_mfg_vs_directory.csv"); bm_at <- rd_opt("atack_colorado_by_sector.csv"); edcov <- rd_opt("edition_coverage.csv"); holc_g <- rd_opt("holc_by_grade.csv"); holc_tr <- rd_opt("trajectories_by_grade.csv"); holc_pre <- rd_opt("trajectories_pre_by_grade.csv"); holc_m <- rd_opt("holc_tract_models.csv"); holc_sh <- rd_opt("holc_facility_shares.csv"); ed_sh <- rd_opt("ed_firm_shares.csv"); ed_cls <- rd_opt("ed_holc_classes.csv")
# every layer, table and trend in the app is built from the 13 complete directory editions; the benchmark files are the one input that also
# carries the partial editions (so the coverage check can be run), and they are filtered here to the complete editions before display
COMPLETE_ED <- if (!is.null(edcov)) as.integer(edcov$year[edcov$complete %in% c(TRUE, "TRUE") & edcov$year >= 1960]) else c(1965:1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992)
if (!is.null(bm_state)) bm_state <- bm_state[bm_state$year %in% COMPLETE_ED, ]; if (!is.null(bm_cty)) bm_cty <- bm_cty[bm_cty$year %in% COMPLETE_ED, ]
# 1925 zoning ordinance as mapped in 1929 (R/zoning_1925.R) and what became of the Denver sites (R/site_fate.R)
zon      <- if (file.exists(dd("zoning_1929.geojson"))) st_read(dd("zoning_1929.geojson"), quiet = TRUE) else NULL; zcity <- if (file.exists(dd("zoning_today_categories.geojson"))) st_read(dd("zoning_today_categories.geojson"), quiet = TRUE) else NULL; z23c <- if (file.exists(dd("zoning_2023_categories.geojson"))) st_read(dd("zoning_2023_categories.geojson"), quiet = TRUE) else NULL; zot_land <- rd_opt("zoning_land_by_year.csv"); zot_grade <- rd_opt("zoning_by_holc_grade_years.csv"); zot_fate <- rd_opt("zoning_1929_industrial_fate.csv"); zot_sites <- rd_opt("zoning_sites_by_year.csv"); zot_paths <- rd_opt("zoning_tract_paths.csv"); zot_note <- if (file.exists(dd("zoning_over_time_notes.txt"))) readLines(dd("zoning_over_time_notes.txt")) else character(); LU_YEARS <- c(1937, 1957, 1977, 1997); LU_GRP <- c("Industrial", "Waste and extraction", "Transportation", "Commercial", "Residential, single family", "Residential, multifamily", "Institutional", "Open land")
LU_COL <- c("#b2182b", "#5e3c99", "#4d4d4d", "#e6ab02", "#fee8c8", "#fdbb84", "#9ecae1", "#d9f0d3")
lu_r <- if (requireNamespace("terra", quietly = TRUE) && all(file.exists(dd(sprintf("landuse_%d_20m.tif", LU_YEARS))))) setNames(lapply(LU_YEARS, function(y) terra::project(terra::rast(dd(sprintf("landuse_%d_20m.tif", y))), "EPSG:3857", method = "near")), LU_YEARS) else NULL   # projected once at start-up
hwy <- if (file.exists(dd("highways_denver.geojson"))) st_read(dd("highways_denver.geojson"), quiet = TRUE) else NULL
hw_dec <- rd_opt("highways_km_by_decade.csv"); hw_holc <- rd_opt("highways_by_holc_grade.csv"); hw_zon <- rd_opt("highways_by_zoning_1929.csv"); hw_tr <- rd_opt("highways_tracts.csv"); hw_nb <- rd_opt("highways_nber_check.csv"); hw_ev <- rd_opt("highways_event_study.csv")
cs_mod <- rd_opt("censoc_models.csv", check.names = FALSE); cs_grp <- rd_opt("censoc_groups.csv", check.names = FALSE); cs_lnk <- rd_opt("censoc_linkage.csv", check.names = FALSE)
# contamination, emissions, urban renewal, lead and health (R/context_layers.R; public sources)
ctx_site <- rd_opt("site_context.csv"); pet <- rd_opt("petroleum_releases_study.csv"); tri_fy <- rd_opt("tri_facility_years_study.csv")
tri_year <- rd_opt("tri_by_year.csv"); tri_holc_y <- rd_opt("tri_by_year_holc.csv"); aqs <- rd_opt("aqs_denver_by_year.csv"); aqs_mon <- rd_opt("aqs_monitors_denver.csv")
ur_tab <- rd_opt("urban_renewal_denver.csv"); hl_hist <- rd_opt("health_by_history.csv", check.names = FALSE); pet_status <- rd_opt("petroleum_by_status.csv"); pet_use <- rd_opt("petroleum_by_use_now.csv")
ctx_sum <- rd_opt("site_context_summary.csv"); hl_tr <- rd_opt("health_tracts_study.csv", colClasses = c(GEOID = "character"))
CX_VARS <- c("Life expectancy at birth, 2010\u201315 (years)" = "life_expectancy", "Current asthma (% adults)" = "casthma", "COPD (% adults)" = "copd", "Coronary heart disease (% adults)" = "chd",
               "Diabetes (% adults)" = "diabetes", "High blood pressure (% adults)" = "bphigh", "Depression (% adults)" = "depression", "Cancer, non-skin (% adults)" = "cancer",
               "Current smoking (% adults)" = "csmoking", "Childhood lead-risk decile (CDPHE model)" = "lead_risk_decile")
ur_poly <- if (file.exists(dd("urban_renewal_denver.geojson"))) st_read(dd("urban_renewal_denver.geojson"), quiet = TRUE) else NULL
ou_poly <- if (file.exists(dd("superfund_ou_study.geojson"))) st_read(dd("superfund_ou_study.geojson"), quiet = TRUE) else NULL
sb03 <- if (file.exists(dd("sanborn_1903_sheets.geojson"))) st_read(dd("sanborn_1903_sheets.geojson"), quiet = TRUE) else NULL
bl03 <- if (file.exists(dd("sanborn_1903_blocks.geojson"))) st_read(dd("sanborn_1903_blocks.geojson"), quiet = TRUE) else NULL
rz <- if (file.exists(dd("rezoning_1925_1956.geojson"))) st_read(dd("rezoning_1925_1956.geojson"), quiet = TRUE) else NULL
rz_holc <- rd_opt("rezoning_by_holc.csv"); rz_holc_sure <- rd_opt("rezoning_by_holc_sure.csv"); rz_test <- rd_opt("rezoning_test.csv"); rz_dir <- rd_opt("rezoning_by_dir.csv", check.names = FALSE); rz_placed <- rd_opt("rezoning_placed.csv")
pl03 <- if (file.exists(dd("sanborn_1903_plants.geojson"))) st_read(dd("sanborn_1903_plants.geojson"), quiet = TRUE) else NULL
# The 1903-04 sheet images laid on the map: each scan is drawn with its fitted rotation and scale (three corners), loaded only when
# the layer is switched on. Library of Congress IIIF images (public domain).
SB03_JS <- "function(el, x, d) { var map = this; if (!d || !d.url) return;
  var add = function() { if (!map.layerManager) { setTimeout(add, 250); return; }   // a hidden map has no layer manager yet: wait, rather than throw and abort Shiny's start-up messages
  if (!L.ImageOverlay.Rot) L.ImageOverlay.Rot = L.ImageOverlay.extend({
    initialize: function (url, tl, tr, bl, o) { this._c = [L.latLng(tl), L.latLng(tr), L.latLng(bl)]; L.ImageOverlay.prototype.initialize.call(this, url, L.latLngBounds(this._c), o); },
    onAdd: function (m) { L.ImageOverlay.prototype.onAdd.call(this, m); var me = this; this._image.style.transformOrigin = '0 0'; this._image.style.width = 'auto'; this._image.style.height = 'auto';
      if (this._image.complete) this._reset(); else this._image.addEventListener('load', function () { me._reset(); }); },
    _animateZoom: function () { if (this._image) this._image.style.visibility = 'hidden'; },
    _reset: function () { var im = this._image; if (!im || !this._map || !im.naturalWidth) return; var m = this._map, c = this._c;
      var p0 = m.latLngToLayerPoint(c[0]), p1 = m.latLngToLayerPoint(c[1]), p2 = m.latLngToLayerPoint(c[2]), w = im.naturalWidth, h = im.naturalHeight;
      im.style.width = w + 'px'; im.style.height = h + 'px'; im.style.left = '0px'; im.style.top = '0px'; im.style.visibility = 'visible';
      im.style.transform = 'matrix(' + [(p1.x - p0.x) / w, (p1.y - p0.y) / w, (p2.x - p0.x) / h, (p2.y - p0.y) / h, p0.x, p0.y].join(',') + ')'; } });
  for (var i = 0; i < d.url.length; i++) {
    var lyr = new L.ImageOverlay.Rot(d.url[i], [d.tl_lat[i], d.tl_lon[i]], [d.tr_lat[i], d.tr_lon[i]], [d.bl_lat[i], d.bl_lon[i]], { opacity: 0.85, pane: 'sbimg', interactive: false });
    map.layerManager.addLayer(lyr, 'image', 'sb03img' + i, d.group); } }; add(); }"
sb03_images <- function(m) { if (is.null(sb03) || !all(c("tl_lat", "overlay") %in% names(sb03))) return(m)
  d <- st_drop_geometry(sb03); htmlwidgets::onRender(m, SB03_JS, data = list(url = d$overlay, tl_lat = d$tl_lat, tl_lon = d$tl_lon, tr_lat = d$tr_lat, tr_lon = d$tr_lon,
                                                                         bl_lat = d$bl_lat, bl_lon = d$bl_lon, group = "Sanborn 1903\u201304 sheet images")) }
s03_area <- rd_opt("sanborn1903_expo_area.csv"); s03_cov <- rd_opt("sanborn1903_cover.csv"); s03_zexp <- rd_opt("sanborn1903_zexp.csv"); s03_who <- rd_opt("sanborn1903_who.csv"); s03_pers <- rd_opt("sanborn1903_persist.csv"); s03_trades <- rd_opt("sanborn1903_trades.csv"); s03_out <- rd_opt("sanborn1903_outside.csv")
sb_poly <- if (file.exists(dd("sanborn_volumes.geojson"))) st_read(dd("sanborn_volumes.geojson"), quiet = TRUE) else NULL
vb_nb <- if (file.exists(dd("vbi70_neighborhoods.geojson"))) st_read(dd("vbi70_neighborhoods.geojson"), quiet = TRUE) else NULL
hed <- rd_opt("hedonic_models.csv"); own_size <- rd_opt("ownership_owner_size.csv"); own_conc <- rd_opt("ownership_concentration.csv"); own_types <- rd_opt("ownership_owner_types.csv"); own_site <- rd_opt("ownership_by_site_proximity.csv"); own_holc <- rd_opt("ownership_by_holc.csv"); own_assoc <- rd_opt("ownership_tract_associations.csv"); own_tr <- rd_opt("ownership_by_tract.csv", colClasses = c(GEOID = "character")); own_ladder <- rd_opt("ownership_linking_stages.csv"); own_loc <- rd_opt("ownership_owner_location.csv"); cond_rates <- rd_opt("conditions_rates.csv"); cond_models <- rd_opt("conditions_models.csv"); ev_s <- rd_opt("conditions_evictions_by_large_owner_share.csv"); ev_m <- rd_opt("conditions_evictions_models.csv"); ev_c <- rd_opt("conditions_evictions_denver_county.csv"); rod <- rd_opt("vbi70_rod2003_soils.csv"); ur_comp <- rd_opt("urban_renewal_composition.csv"); ur_sites <- rd_opt("urban_renewal_sites.csv")
OW_VARS <- c("Rental units held by owners of 20+ units (%)" = "pct_rental_owner_20plus", "Rental units held by owners of 100+ units (%)" = "pct_rental_owner_100plus",
             "Rental units held by companies (LLC, corporation, partnership) (%)" = "pct_rental_company", "Rental units with an owner outside Colorado (%)" = "pct_rental_out_of_state",
             "Units not occupied by their owner (%)" = "pct_rental", "Rental units owned by public agencies (%)" = "pct_rental_public")
SB_EDS <- c("1887", "1890\u20131893", "1903\u20131904", "1929\u20131930", "1950\u20131951"); SB_COL <- c("#8c510a", "#bf812d", "#dfc27d", "#35978f", "#01665e")
AERIAL_1933 <- "https://tiles.arcgis.com/tiles/44C95LOqZjbh8Row/arcgis/rest/services/Denver_1933_Aerial/MapServer/tile/{z}/{y}/{x}"
AERIAL_ATTR <- "1933 aerial survey (Jasper King): Denver Public Library; georeferenced by the City and County of Denver"
ctx_html <- function(ids) { if (is.null(ctx_site)) return(rep("", length(ids))); d <- ctx_site[match(ids, ctx_site$id), ]
  out <- character(length(ids)); ok <- !is.na(d$id)
  out[ok] <- paste0("<hr style='margin:4px 0'><b>Later records at this address</b> <small>(within 50 m; TRI within 100 m)</small>:<br>",
    ifelse(d$petroleum_releases_50m[ok] > 0, sprintf("Petroleum release%s reported %s (%s still open)", ifelse(d$petroleum_releases_50m[ok] > 1, "s", ""),
           ifelse(is.na(d$first_release_year[ok]), "", paste("from", d$first_release_year[ok])), d$open_releases_50m[ok]), "No petroleum release on record"),
    ifelse(d$tank_facility_50m[ok] %in% 1, " · regulated storage-tank facility", ""), ifelse(d$tri_facility_100m[ok] %in% TRUE, " · TRI reporter nearby", ""),
    ifelse(is.na(d$urban_renewal_project[ok]), "", sprintf("<br>Inside the <b>%s</b> urban-renewal project", tools::toTitleCase(d$urban_renewal_project[ok]))),
    ifelse(is.na(d$superfund_unit[ok]), "", sprintf("<br>Inside Superfund unit: %s", esc(tools::toTitleCase(tolower(d$superfund_unit[ok]))))),
    ifelse(is.na(d$sanborn[ok]) | d$sanborn[ok] == "", "", paste0("<br><small>", d$sanborn[ok], "</small>")))
  out }
enl_mod <- rd_opt("enlistment_models.csv", check.names = FALSE); enl_sh <- rd_opt("enlistment_shares.csv", check.names = FALSE)
CS_CHK <- c("By age in 1940" = "censoc_ext_childhood.csv", "Own job and household head's job" = "censoc_ext_work_home.csv", "Groups" = "censoc_ext_groups.csv",
            "Who stayed in the Denver area" = "censoc_ext_stayers.csv", "Who links to a death record" = "censoc_ext_linkage_shares.csv",
            "Survival model (Gompertz) check" = "censoc_ext_gompertz.csv", "Freeways and cleared land" = "censoc_ext_displacement.csv",
            "Who lived in a later freeway's path" = "censoc_ext_displacement_who.csv", "Earlier addresses, 1910\u20131930" = "mlp_models.csv",
            "Earlier addresses: who stayed put" = "mlp_persistence.csv")
cs_chk <- lapply(CS_CHK, function(f) rd_opt(f, check.names = FALSE))
CS_FILE <- c("Men, deaths 1975\u20132020" = "DMF", "Men and women, deaths at 65+ in 1988\u20132005" = "Numident")
cs_pick <- function(d, k) if (is.null(d)) NULL else d[startsWith(d$file, k), ]
hw_open <- function(y) { if (is.null(hwy)) return(NULL); h <- hwy[!is.na(hwy$start_year) & hwy$start_year <= y & (is.na(hwy$end_year) | hwy$end_year > y), ]; h }
lu_year <- rd_opt("landuse_by_year.csv"); lu_holc <- rd_opt("landuse_by_holc_grade.csv"); lu_zone <- rd_opt("landuse_vs_zoning.csv"); lu_sites <- rd_opt("landuse_sites.csv"); lu_trans <- rd_opt("landuse_site_transitions.csv"); lu_paths <- rd_opt("landuse_tract_paths.csv")
add_landuse <- function(m, y, group, opacity = 0.75, legend = TRUE, layerId = NULL) { if (is.null(lu_r)) return(m)
  pal <- colorFactor(LU_COL, domain = 1:8, na.color = "transparent")
  m <- m |> addRasterImage(lu_r[[as.character(y)]], colors = pal, opacity = opacity, group = group, project = FALSE, maxBytes = 16 * 1024^2)
  if (legend) m <- m |> addLegend("bottomright", colors = LU_COL, labels = LU_GRP, opacity = opacity, group = group, layerId = layerId, title = paste0("Land use ", y, "<br><small>USGS, from aerial photographs</small>"))
  m }
zon44 <- if (file.exists(dd("zoning_1944.geojson"))) st_read(dd("zoning_1944.geojson"), quiet = TRUE) else NULL; zon55 <- if (file.exists(dd("zoning_1955.geojson"))) st_read(dd("zoning_1955.geojson"), quiet = TRUE) else NULL; zch <- if (file.exists(dd("zoning_1929_1944_change.geojson"))) st_read(dd("zoning_1929_1944_change.geojson"), quiet = TRUE) else NULL; zch_t <- rd_opt("zoning_changes_1944.csv"); zg44 <- rd_opt("zoning_change_by_holc_grade.csv"); zt44 <- rd_opt("zoning_1929_vs_1944.csv"); zon_g <- rd_opt("holc_zoning_by_grade.csv")
ZON_COL  <- c("Industrial A" = "#b2182b", "Industrial B" = "#762a83", "Commercial" = "#e6ab02")
ZT_COL   <- c("Industrial" = "#b2182b", "Industrial mixed use" = "#e7298a", "Commercial or mixed use" = "#e6ab02", "Commercial (housing not allowed)" = "#a6761d", "Residential" = "#fdd0a2", "PUD (custom district)" = "#bdbdbd", "Open space, civic, other" = "#a1d99b")
ZYEARS   <- c("1929 (1925 ordinance as amended)" = "1929", "1944" = "1944", "1955 (industrial districts only)" = "1955", "2023 (National Zoning Atlas)" = "2023", "Today (city zoning map)" = "today")
if (is.null(zon55)) ZYEARS <- ZYEARS[ZYEARS != "1955"]
if (is.null(z23c)) ZYEARS <- ZYEARS[ZYEARS != "2023"]       # the 2023 atlas layer is shared on request, not in the repository
zoning_layer <- function(y) { if (y == "1955") { if (is.null(zon55)) return(NULL); z <- zon55; z$cat <- "Industrial"; z$lab <- sprintf("1955 zoning: %s district", z$district); return(z) }
  if (y %in% c("1929", "1944")) { z <- if (y == "1929") zon else zon44; if (is.null(z)) return(NULL)
    z$cat <- ifelse(grepl("Industrial", z$zone), "Industrial", "Commercial or mixed use"); z$lab <- sprintf("%s zoning: %s district", y, z$zone); z }
  else { z <- if (y == "2023") z23c else zcity; if (is.null(z)) return(NULL); z$lab <- sprintf("%s zoning: %s", ifelse(y == "today", "Today's", "2023"), z$cat); z } }
add_zoning <- function(m, y, group, pane, opacity = 0.5, legend_pos = "topleft", layerId = NULL) { z <- zoning_layer(y); if (is.null(z)) return(m)
  hist <- y %in% c("1929", "1944"); keep <- if (hist) c("Industrial", "Commercial or mixed use") else if (y == "1955") "Industrial" else intersect(names(ZT_COL), unique(z$cat))
  m <- m |> addPolygons(data = z, fillColor = unname(ZT_COL[z$cat]), fillOpacity = opacity, color = unname(ZT_COL[z$cat]), weight = 0.6, group = group, options = pathOptions(pane = pane), label = z$lab)
  m |> addLegend(legend_pos, colors = unname(ZT_COL[keep]), labels = if (hist) c("Industrial A or B", "Commercial") else if (y == "1955") "Industrial (I-1 or I-2)" else keep, opacity = 0.7, group = group, layerId = layerId,
                 title = paste0("Zoning ", names(ZYEARS)[ZYEARS == y], if (hist) "<br><small>residence and business districts not shown</small>" else if (y == "1955") "<br><small>Zone map, 1 July 1955: History Colorado-Denver, Colorado</small>" else if (y == "2023") "<br><small>C. Makarewicz, CU Denver; <a href='https://storymaps.arcgis.com/stories/adb86c7ab2624e95a84566fecb8a6f6d' target='_blank'>request the data</a></small>" else "")) }
sf_sum   <- rd_opt("site_fate_summary.csv"); sf_zone <- rd_opt("site_fate_zoning.csv"); z23_29 <- rd_opt("zoning_1929_to_2023.csv", check.names = FALSE); z23_s <- rd_opt("sites_by_zoning_2023.csv", check.names = FALSE); z23_d <- rd_opt("sites_by_zoning_2023_last_listed.csv", check.names = FALSE); z23_t <- rd_opt("tract_composition_by_zoning_2023.csv", check.names = FALSE)
sf_den <- rd_opt("site_fate_denver.csv"); sf_pre <- rd_opt("site_fate_denver_pre1960.csv")
USE_COL  <- c("Industrial / utility" = "#636363", "Commercial / office" = "#e6ab02", "Residential" = "#d7301f", "Vacant" = "#bdbdbd", "Civic / school / health" = "#1f78b4", "Park / open space" = "#33a02c", "Other" = "#f0f0f0", "No parcel match" = "#ffffff")
eds_holc <- if (file.exists(dd("eds_holc_1930.geojson"))) st_read(dd("eds_holc_1930.geojson"), quiet = TRUE) else NULL
HOLC_COL6 <- c(A = "#76a865", B = "#7cb5bd", C = "#ffff00", D = "#d9838d", Industrial = "#8c8c8c", Commercial = "#c8a2c8", ungraded = "#eeeeee")
HOLC_COL <- c(A = "#76a865", B = "#7cb5bd", C = "#ffff00", D = "#d9838d")
PAN_YEARS <- seq(1940, 2020, 10)   # tracts only; the 1880-1940 Colorado counties are on the Colorado trends tab
PAN_VARS <- c("Black (%)" = "p_black", "White (%, race)" = "p_white", "Hispanic (%)" = "p_hisp", "Foreign born (%)" = "p_fb", "Below poverty line (%)" = "p_pov",
              "Owner-occupied households (%)" = "p_owner", "Median home value (2020 $)" = "mval_2020", "Median rent (2020 $)" = "mrent_2020",
              "Mortgage denial rate 2018-21 (%, HMDA; 2020 only)" = "hmda_denial", "Mortgage denial rate, Hispanic applicants (%)" = "hmda_denial_hisp", "Mortgage denial rate, Black applicants (%)" = "hmda_denial_black", "Hispanic share of mortgage applications (%)" = "hmda_pct_hisp_apps",
              "Population" = "pop", "Hazardous firms active in the decade" = "firms_haz", "Legacy hazardous firms (earlier, no longer listed)" = "legacy_haz")
CELL_CLASSES <- c("persistent", "persistent, sector turnover", "intermittent", "former (gone by 1980s)", "emerging")
CELL_COL <- c("#000000", "#7a0177", "#f768a1", "#fcc5c0", "#9ecae1"); names(CELL_COL) <- CELL_CLASSES

STATUS <- c("Not on any list", "Cleanup / contamination list", "TRI reporter", "RCRA hazardous-waste handler",
            "Solid waste facility", "Other EPA permit only")
STATUS_LAB <- c("Not on any list" = "No match in searched inventories", "Cleanup / contamination list" = "Cleanup / contamination list", "TRI reporter" = "TRI reporter", "RCRA hazardous-waste handler" = "RCRA hazardous-waste handler", "Solid waste facility" = "Solid waste facility", "Other EPA permit only" = "Other EPA permit only")
STATUS_COL <- c("Not on any list" = "#d1491f", "Cleanup / contamination list" = "#24589e", "TRI reporter" = "#7a4aa8",
                "RCRA hazardous-waste handler" = "#4f8a8b", "Solid waste facility" = "#9a9a9a", "Other EPA permit only" = "#b5b5b5")
SECTORS <- c("Chemicals", "Petroleum refining", "Rubber & plastics", "Primary metals", "Fabricated metals",
             "Industrial machinery", "Transportation equipment", "Extended sectors")
EDITIONS <- sort(unique(site_yr$year))
VARS <- c("EnviroScreen score (percentile)" = "enviroscreen_pctl",
          "Pollution & climate burden (percentile)" = "pollution_climate_pctl",
          "Health & social factors (percentile)" = "health_social_pctl",
          "Demographics (percentile)" = "demographics_pctl",
          "Low income (%)" = "low_income", "People of color (%)" = "people_of_color",
          "Less than high school education (%)" = "less_than_hs", "Linguistic isolation (%)" = "linguistic_isolation",
          "Housing cost burdened (%)" = "housing_burden", "Disability (%)" = "disability",
          "Life expectancy (years)" = "life_expectancy", "Asthma hospitalization rate" = "asthma_rate",
          "Lead exposure risk (%)" = "lead_risk",
          "Proximity to hazardous waste facilities (pctl)" = "prox_hazwaste_pctl",
          "Proximity to Superfund/NPL sites (pctl)" = "prox_npl_pctl")
# ---------------------------------------------------------------- Denver focus
# The study area of the paper: the City and County of Denver plus the 2010 tracts whose centroid lies within 10 km of downtown (any county).
# Every layer below is cut to it; the statewide results are read separately for the 'Colorado trends' tab.
DEN_AREA <- local({ a <- den_tr[substr(den_tr$GEOID, 1, 5) == "08031" | den_tr$core, ]; st_union(st_make_valid(st_transform(a, 4326))) })
in_den <- function(d) { if (is.null(d) || !nrow(d)) return(d); ok <- !is.na(d$lat) & !is.na(d$lon); d <- d[ok, , drop = FALSE]
  p <- st_as_sf(d, coords = c("lon", "lat"), crs = 4326, remove = FALSE); d[lengths(st_intersects(p, DEN_AREA)) > 0, , drop = FALSE] }
sites <- in_den(sites); site_yr <- site_yr[site_yr$site_id %in% sites$site_id, ]
tri <- in_den(tri); cleanup <- in_den(cleanup); schools <- in_den(schools); health <- in_den(health)
if (!is.null(hist)) hist <- in_den(hist); if (!is.null(radium)) radium <- in_den(radium); if (!is.null(cells)) cells <- in_den(cells)
tracts <- tracts[lengths(st_intersects(st_point_on_surface(st_make_valid(tracts)), DEN_AREA)) > 0, ]
# Colorado-wide results (R/statewide.R, R/corridors.R)
co_reg <- rd_opt("county_regions_1880_1940.csv"); co_cor <- rd_opt("county_correlations_1880_1940.csv"); co_share <- rd_opt("regional_shares_1965_1992.csv", check.names = FALSE)
co_assoc <- rd_opt("tract_associations_1980_2020.csv"); co_gcd <- rd_opt("graded_cities_firm_density.csv"); co_gcl <- rd_opt("graded_cities_tract_lq_1970_2020.csv"); co_leg <- rd_opt("legacy_tract_models.csv")
tract_df <- st_drop_geometry(tracts)
# persistence: editions in which the site hosted a hazardous-sector firm, and span from first to last such edition
pers <- site_yr |> group_by(site_id) |> summarise(n_editions = n_distinct(year), haz_first = min(year), haz_last = max(year), .groups = "drop") |>
  mutate(span_years = haz_last - haz_first)
# a firm or address traced back to the pre-1960 business directories extends the site's span
sites <- sites |> left_join(pers, by = "site_id") |> left_join(precur, by = "site_id") |>
  mutate(n_editions = coalesce(n_editions, 1L), haz_first = pmin(haz_first, hist_first_year, na.rm = TRUE),
         span_years = coalesce(haz_last - haz_first, 0L))
SPAN_BREAKS <- c(-1, 0, 9, 19, 29, 49, 200)
SPAN_LABELS <- c("One edition", "1–9 years", "10–19 years", "20–29 years", "30–49 years", "50+ years (traced to pre-1960 directories)")
SPAN_COL <- c("#c6dbef", "#9ecae1", "#4292c6", "#2166ac", "#08306b", "#000000")
HIST_COL <- "#8c510a"
CLEAN_LAYERS <- c("Brownfields", "Voluntary cleanup (VCUP)", "Superfund (SEMS)", "RCRA corrective action",
                  "Environmental covenants / land-use controls")
CLEAN_COL <- c("#1b7837", "#5aae61", "#253494", "#41b6c4", "#8c6bb1"); names(CLEAN_COL) <- CLEAN_LAYERS
esc <- function(x) htmltools::htmlEscape(ifelse(is.na(x), "", as.character(x)))
gradeleg <- function(p) { seen <- character(); for (i in seq_along(p$x$data)) { nm <- p$x$data[[i]]$name; if (is.null(nm)) next; g <- sub("^\\((.)\\,.*$", "\\1", nm); if (nchar(g) == 1) { p$x$data[[i]]$name <- g; p$x$data[[i]]$legendgroup <- g; p$x$data[[i]]$showlegend <- !(g %in% seen); seen <- c(seen, g) } }; p }   # one legend entry per grade when colour and linetype are both mapped
unit_note <- function(x) tags$div(class = "small mb-2", style = "color:#2c5d8f", tags$b("Spatial unit: "), x)
hleg <- function(p) plotly::layout(p, legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left"), margin = list(t = 10))   # horizontal legend clear of the axis title

# ---------------------------------------------------------------- UI
filters <- list(
  sliderInput("yrs", "Listed in a directory between", min = 1871, max = 1992, value = c(1871, 1992), sep = "", step = 1, ticks = FALSE),
  uiOutput("yrs_note"),
  helpText("1871–1956: hazardous trades in the Colorado State Business Directory (brown). 1965–1992: Directory of Colorado Manufacturers, the 13 editions whose scans are complete (the 12 partial editions are set aside until CU Boulder supplies the missing pages; see Data & downloads)."),
  checkboxGroupInput("sec", "Sector (Frickel & Elliott)", SECTORS, selected = SECTORS[1:7]),
  tags$details(tags$summary(tags$small("What these sectors are")),
    tags$small(class = "text-muted", "The seven manufacturing industries that Scott Frickel and James Elliott (", tags$i("Sites Unseen"), ", 2018) identify as the most likely to leave ",
      "contaminated ground when they close, by their input materials and waste streams: SIC 28 chemicals and allied products, 29 petroleum refining, 30 rubber and plastics, ",
      "33 primary metals (smelters, foundries, mills), 34 fabricated metals (plating, coating, machine shops), 35 industrial machinery, 37 transportation equipment (NAICS 325, 324, 326, 331, 332, 333, 336). ",
      "Each manufacturers'-directory listing carries its own SIC/NAICS code, so a site is in a sector if any firm listed at the address had that code. ",
      tags$b("Extended sectors"), " adds smaller trades with similar legacies that fall outside those codes: wood preserving (SIC 2491), leather tanning (3111), electronic tubes, circuit boards, semiconductors and components (3671–3679), ",
      "storage and primary batteries (3691–3692), photographic equipment and chemicals (3861), asphalt paving mixtures (2951), blast furnaces and coke (3312) and metal mining or ore milling (SIC 10). ",
      "Pre-1960 business-directory trades (smelters, sampling works, foundries, tanneries, gas works and so on) are mapped onto the same sectors by keyword.")),
  checkboxInput("radium", "Radium, uranium & vanadium firms (☢, both directories)", TRUE),
  checkboxGroupInput("st", "Current regulatory status", setNames(STATUS, STATUS_LAB[STATUS]), selected = STATUS),
  radioButtons("colby", "Colour sites by", c("Regulatory status" = "status", "Persistence (years listed)" = "span"), inline = FALSE),
  sliderInput("minspan", "Years between first and last observed listing (at least)", 0, 125, 0, step = 1, ticks = FALSE),
  checkboxInput("htown", "Show pre-1960 listings placed only at the town centre (map and county summaries only; never used in tract, district or proximity analyses)", TRUE),
  checkboxGroupInput("cf", "Confidence (location + industry)", c("High" = "high", "Medium" = "medium", "Low" = "low"),
                     selected = c("high", "medium", "low"), inline = TRUE),
  helpText("High = a street-address geocode (interpolated along the street's address range, typically within tens of metres; see Data & downloads) and an industry code printed in the directory; medium = one of the two (an address printed without its N/S/E/W direction counts as approximate). ",
           "'No match in searched inventories' (stored as 'Not on any list' in the downloads) = not on the searched EPA and CDPHE HMWMD lists (FRS, TRI, SEMS/Superfund, RCRA, CDPHE cleanup, VCUP, brownfields, covenants) by location (40\u201375 m), address or name; state petroleum-tank and release registers are shown separately on the Contamination & health tab. Geocoding error of tens of metres can move a site across those thresholds, so it is a lead, not a finding.")
)

ui <- page_navbar(id = "nav",
  title = "Denver Hidden Hazards", fillable = "Map",   # other tabs scroll so their plots keep full height
  theme = bs_theme(version = 5, bootswatch = "flatly", primary = "#24589e", base_font = font_google("Public Sans", local = FALSE)),
  header = tags$style(HTML(".navbar { position: relative; z-index: 3000; } .navbar .dropdown-menu { z-index: 3001; background-color: #ffffff; opacity: 1; box-shadow: 0 6px 18px rgba(0,0,0,.25); } .navbar .dropdown-menu .dropdown-item { color: #1f2937; } .navbar .dropdown-menu .dropdown-item:hover, .navbar .dropdown-menu .dropdown-item.active { background-color: #e8eef7; color: #0b3d91; } .leaflet .info.legend { font-size: 11px; line-height: 1.25; max-width: 260px; } .leaflet-control-layers { font-size: 11.5px; } .leaflet-top.leaflet-left .info.legend { margin-top: 6px; } @media (max-width: 900px) { .leaflet-control-layers-expanded { display: none; } .leaflet .info.legend { font-size: 9.5px; max-width: 170px; max-height: 140px; overflow-y: auto; padding: 4px 6px; opacity: 0.88; } .leaflet .info.legend i { width: 12px; height: 12px; } }")),
  sidebar = sidebar(width = 300,
    conditionalPanel("['Map','Trends','Neighborhoods','Nearby schools & health care','Data & downloads'].includes(input.nav)", do.call(tagList, filters)),
    conditionalPanel("!['Map','Trends','Neighborhoods','Nearby schools & health care','Data & downloads'].includes(input.nav)",
      tags$small(class = "text-muted", "The site filters apply to the Map, Trends, Neighborhoods, Nearby schools and Data tabs. This tab uses its own controls."))),
  nav_panel("Map",
    layout_columns(col_widths = c(9, 3),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map", height = "72vh"))),
      card(card_header("EnviroScreen layer"), unit_note("sites and facilities as points; EnviroScreen 2020 census tracts; 500 m corridor cells; district and parcel layers as drawn"),
           selectInput("esvar", "Shade census tracts by", VARS, selected = "enviroscreen_pctl"),
           sliderInput("esop", "Opacity", 0, 1, 0.45, step = 0.05),
           hr(),
           tags$b("Sites shown"), textOutput("nsites"),
           tags$small(class = "text-muted",
             "Use the layer control (top right of the map) to add TRI facilities, schools, hospitals, clinics, ",
             "residential care, brownfields and other cleanup sites. Click any point for details."),
           tags$details(tags$summary(tags$small("What the map layers are")), tags$small(class = "text-muted", tags$dl(class = "mb-0",
             tags$dt("Historical hazardous sites"), tags$dd("Addresses of manufacturers in Frickel & Elliott's hazardous sectors from the 13 complete editions (1965–1992) of the Directory of Colorado Manufacturers, filtered by the sidebar."),
             tags$dt("Pre-1960 hazardous trades"), tags$dd("Smelters, foundries, refineries, tanneries, gas works and similar trades in the 1871–1956 Colorado State Business Directory; street-level in Denver from 1891, otherwise one marker per town."),
             tags$dt("Industrial corridors"), tags$dd("500 m cells with any manufacturer in the complete editions 1965–1992, classed by persistence (definition on the Data & downloads tab)."),
             tags$dt("EnviroScreen tracts"), tags$dd("Colorado EnviroScreen 2.0 (CDPHE) tract scores: cumulative environmental burden and social vulnerability, as percentiles."),
             tags$dt("EPA TRI facilities"), tags$dd("Facilities currently reporting toxic releases to EPA's Toxics Release Inventory."),
             tags$dt("Brownfields"), tags$dd("Properties in CDPHE's and EPA's brownfields programmes: land whose reuse is complicated by known or suspected contamination, usually under assessment or redevelopment."),
             tags$dt("Voluntary cleanup (VCUP)"), tags$dd("Sites cleaned up under Colorado's Voluntary Cleanup and Redevelopment Act, where an owner remediates to agreed standards and receives a no-action determination."),
             tags$dt("Superfund (SEMS)"), tags$dd("Sites in EPA's Superfund Enterprise Management System, from assessed sites to the National Priorities List."),
             tags$dt("RCRA corrective action"), tags$dd("Hazardous-waste handlers required by EPA/CDPHE to investigate and clean up releases at their own facilities under the Resource Conservation and Recovery Act."),
             tags$dt("Environmental covenants / land-use controls"), tags$dd("Deed restrictions recorded because contamination was left in place after a cleanup: they may forbid residential use or drinking-water wells, require vapour barriers, or bar digging below a given depth. ",
               "CDPHE's Institutional Controls layer (environmental covenants, use restrictions and notices of environmental use restrictions). The clearest public record that a parcel still holds managed contamination."),
             tags$dt("Schools, hospitals, clinics, residential care"), tags$dd("Colorado Department of Education school locations and CDPHE licensed health facilities (geodata.colorado.gov), used on the Nearby schools & health care tab."))))))),
  nav_panel("Trends",
    card(card_header("Hazardous-trade firms and sites listed, 1871\u20131992: both directory series on one timeline"), unit_note("pre-1960 firms (street address, or the town centre when the sidebar includes town-placed listings) and 1965\u201392 sites (street addresses) in the Denver study area (City and County of Denver plus the 147 2010 census tracts within 10 km of downtown), counted per directory edition"),
         plotlyOutput("p_timeline", height = 320),
         tags$small(class = "text-muted", "Brown: hazardous trades found in the Colorado State Business Directory (34 editions, every trade, OCR'd scans; counts depend on each edition's coverage and scan quality). Orange: hazardous-sector sites in the Directory of Colorado Manufacturers (25 editions, manufacturers only). The two series are not on the same footing \u2014 the business directories list far more small trades \u2014 but together they trace the whole span. Twelve of the 25 manufacturers' directory editions reached us as partial scans - typically the scan stops at Denver or Colorado Springs and the counties after them are missing - and are drawn hollow or dropped (complete: 1965-68, 1970, 1973-74, 1977, 1980, 1983, 1988, 1990, 1992); the Data & downloads tab lists what each edition contains. Both respond to the sidebar filters.")),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Hazardous-sector sites listed per directory edition, by sector"), unit_note("sites (street addresses) in the Denver study area (City and County of Denver plus the 147 2010 census tracts within 10 km of downtown), counted per edition"), plotlyOutput("p_sector", height = 420)),
      card(card_header("…by current regulatory status"), unit_note("sites (street addresses) in the Denver study area (City and County of Denver plus the 147 2010 census tracts within 10 km of downtown), counted per edition"), plotlyOutput("p_status", height = 420))),
    card(card_header("Share of listed sites on no current inventory"), unit_note("sites (street addresses) in the Denver study area (City and County of Denver plus the 147 2010 census tracts within 10 km of downtown), per edition"), plotlyOutput("p_share", height = 300)),
    tags$small(class = "text-muted", "Editions are irregular (25 between 1961 and 2002); only the 13 complete editions (1965\u201368, 1970, 1973\u201374, 1977, 1980, 1983, 1988, 1990, 1992) enter the site inventory."),
    card(card_header("Before 1960: Denver hazardous-trade firms listed per Colorado State Business Directory edition"), unit_note("firms (street or town) in the Denver study area (City and County of Denver plus the 147 2010 census tracts within 10 km of downtown), counted per edition"), plotlyOutput("p_hist", height = 360),
         tags$small(class = "text-muted", "Counts come from searchable text of the scanned directories and are not comparable to the manufacturers' directory: ",
                    "the business directories list every trade and their OCR quality varies by edition. 1891 and 1910–1939 include large Denver sections.")),
    card(card_header("Do hazardous sectors cluster more than manufacturing in general? Ellison–Glaeser index by edition, Denver metro (25 km of downtown)"), unit_note("1 km grid cells within 25 km of downtown Denver"), plotlyOutput("p_eg", height = 380),
         tags$small(class = "text-muted", "γ > 0: the sector is more concentrated across 1 km cells than all located manufacturers of that edition; filled points are significant at p < 0.05 (permutation test, 500 draws). ",
                    "The index needs every manufacturer of an edition as the baseline, so it uses the 13 complete manufacturers' directory editions (1965–1992). The statewide index, the industry mix and sector succession are on the Colorado trends tab.")),
    ),
  nav_menu("Historical change",
  nav_panel("Denver 1880–2020",
    layout_columns(col_widths = c(3, 6, 3),
      card(card_header("Denver by enumeration district (1880–1940) and census tract (1950–2020)"), unit_note("enumeration districts 1880–1940 (reconstructed), 2010 census tracts 1950–2020"),
           radioButtons("ed_year", "Census", choices = c(if (is.null(eds)) 1880 else sort(unique(eds$year)), if (is.null(trd)) NULL else sort(unique(trd$census))), selected = 1880, inline = TRUE),
           uiOutput("ed_unit"),
           selectInput("ed_var", "Districts or tracts shaded by", ED_VARS, selected = "pct_fb"),
           checkboxInput("ed_firms", "Show hazardous-trade firms of the decade", TRUE),
           tags$small(class = "text-muted",
             "District boundaries are this project's reconstruction (see About the data): every household address in Brown University's Geographic Reference Files for Denver (1900–1940) ",
             "was geocoded with the project's offline TIGER geocoder and the districts drawn as the dissolved Voronoi cells of their addresses; 1880 uses Brown's geocoded buildings the same way. ",
             "Composition is the IPUMS full count aggregated by district. Firms: the hazardous trades of the business directories listed in the preceding decade, at their street address (1878–1885 firms on the 1880 grid for 1880). ",
             tags$b("From 1950 the unit changes to the census tract"), " (the 147 2010 tracts within 10 km of downtown; earlier censuses interpolated onto them; see About the data), because census microdata are sealed for 72 years and the address files that let us draw districts stop at 1940. ",
             "The same analyses are run on tracts with the tract tables' measures (race, Hispanic origin, nativity, poverty, tenure, value, rent); firms of the decade are the manufacturers' directory sites from 1970 (2000, 2010 and 2020 use the last complete directory decade, 1983–1992)."),
           ),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map_1880", height = "70vh"))),
      card(card_header("Composition vs. distance to the nearest firm"), unit_note("enumeration districts 1880–1940, 2010 census tracts 1950–2020 (follows the census selector); distance from each unit's centroid"), tableOutput("t_edm"),
           tags$small(class = "text-muted", "Percentage points per log-metre from the district or tract centroid to the nearest hazardous firm (population-weighted, robust SE; negative = higher near industry). 'pooled' = all censuses with census effects (1880–1940 districts and 1950–2020 tracts pooled separately). Value and rent enter as logs. ",
             "SEI = Duncan socioeconomic index (IPUMS): each occupation scored 0-96 from the income and education of its holders in 1950, the only income proxy available for every census. ",
             "'In hazardous industries' = share of a district's employed residents working in chemical, metal, petroleum and similar industries (IPUMS IND1950): if the people next to the plants were mainly their own workers this coefficient would be negative; on its own it is not distinguishable from zero in any census, but once distance to downtown is held constant (Distance models download) it turns negative, significantly so in 1910, 1940 and all censuses pooled, so some of the residents nearest the plants did work in these industries; it cannot establish where individual residents worked."),
           card_header("Dissimilarity across districts, 1880–1940"), unit_note("enumeration districts, and a fixed 500 m grid (all censuses; not affected by the selector)"), plotlyOutput("p_city", height = 260),
           tags$small(class = "text-muted", "0 = evenly spread, 1 = complete separation (IPUMS full count). The number of districts rises from 17 to 325, and smaller units mechanically raise the index, so only the fixed-grid lines (district counts area-weighted onto one 500 m grid over the area mapped in every census compared) show change over time."))),
    card(card_header(textOutput("edg_title")), unit_note("enumeration districts 1880–1940, 2010 census tracts 1950–2020 (follows the census selector)"), tableOutput("t_edg"),
         tags$small(class = "text-muted", "Population-weighted means: enumeration districts 1880\u20131940 (IPUMS full count) or census tracts 1950\u20132020 (NHGIS tables on 2010 boundaries). The last row is the dissimilarity index of the group against the rest of the population across that census's units (0\u20131). It depends on how many units there are and how big they are (17 districts in 1880, 330 in 1940, 97 tracts in 1950 and 144–147 from 1960), so it cannot be compared across years or between districts and tracts; the chart above adds the index on one fixed grid.")),
    card(card_header("Where the firms were: share of each decade's hazardous firms in the districts (1880–1940) or tracts (1950–2020) housing the top population quartile on each measure"), unit_note("enumeration districts 1880–1940, 2010 census tracts 1950–2020 (all censuses; not affected by the selector)"), plotlyOutput("p_ed_sh", height = 340),
         tags$small(class = "text-muted", "Districts or tracts are ranked on the measure and the top 25% of the population taken; if firms were spread like people, 25% (dashed line) would fall there. Hover for the share in the bottom quartile. The grey line marks the change of unit.")),
    layout_columns(col_widths = c(6, 6),
      card(card_header("1880 at the building level (Brown University Urban Transition HGIS)"), unit_note("buildings and enumeration districts, 1880 only (the only census geocoded to buildings; not affected by the census selector)"),
           tags$small(class = "text-muted", "The 1880 census geocoded to buildings against the hazardous trades of the 1878–1885 directories placed on the 1880 street grid: 34,386 residents, 69 firms placed (30 at the building itself, 30 at the nearest house number on the same street, 9 on the street only). Only aggregates and model results are shown; Brown's building-level data are not redistributed."),
           hr(), tags$b("Residents by distance to the nearest hazardous firm"), tableOutput("t_d80"),
           tags$b("Enumeration districts with vs. without a hazardous firm (Brown's ED composition)"), tableOutput("t_g80")),
      card(card_header("Person-level odds of living farther from a hazardous firm (1880)"), unit_note("individuals, by distance from their building to the nearest firm; 1880 only (not affected by the census selector)"), tableOutput("t_m80"),
           tags$small(class = "text-muted", "Odds ratio per log-metre of distance (> 1 = more common farther away), building-clustered SE. Foreign-born (German, Canadian, other), Black and Chinese residents lived closer; native-born whites, British- and Scandinavian-born lived farther; employed adults' SEI fell with distance (about one point per log-metre), and unskilled laborers (SEI 8) were, on average, farther out."))),
    layout_columns(col_widths = c(6, 6),
      card(card_header(textOutput("pan_title")), unit_note("the 147 2010 census tracts within 10 km of downtown, 1940–2020 (all censuses; not affected by the selector)"), selectInput("pan_var", "Measure", PAN_VARS[PAN_VARS %in% c("p_black", "p_white", "p_hisp", "p_fb", "p_pov", "p_owner", "mval_2020", "mrent_2020")], selected = "p_hisp"), plotlyOutput("p_pan", height = 380),
           checkboxInput("pan_bal", "Same tracts throughout: only tracts with a value in every census the measure exists", TRUE),
           uiOutput("pan_note"),
           tags$small(class = "text-muted", "Population-weighted means. Points resting on fewer than 15 tracts are not drawn (they swing on one or two neighbourhoods). Fewer of the study tracts were tracted and populated before 1960; with 'same tracts throughout' every point uses one fixed set of tracts. 'Legacy only' = tracts whose hazardous firms had all left by that decade. 2000, 2010 and 2020 all use the 1983–1992 listings (no complete directory after 1992), so the groups are identical in those three censuses and the lines show how the same places changed."), downloadButton("dl_panel", "Download tract panel CSV (study area)", class = "btn-sm")),
      card(card_header("Panel models (Denver core): does industry predict who moves in, or do residents predict where industry goes?"), unit_note("the 147 2010 census tracts within 10 km of downtown, 1970–2020"), uiOutput("ej_models"),
           tags$small(class = "text-muted", "Hybrid (within/between) models after Marlow, Frickel & Elliott (2020), the 147 2010 tracts whose centroid lies within 10 km of downtown (any county). The within/between panel uses the censuses that have a complete directory edition in the same year (1970, 1980, 1990), hazardous-sector establishments, tract-clustered SE. 2000–2020 have no contemporaneous directory and are modelled census by census on 1983–1992 listings (legacy-site exposure). Reproduce with Rscript R/ej_panel.R.")))
    ),
  nav_panel("What became of the sites",
    layout_columns(col_widths = c(3, 6, 3),
      card(card_header("Denver's historical hazardous sites on today's parcels"), unit_note("sites matched to today's assessor parcels, City and County of Denver"),
           radioButtons("sf_series", "Sites", c("Manufacturers' directory sites, complete editions 1965\u20131992" = "S", "Business-directory hazardous trades 1891\u20131956 (street level)" = "H")),
           checkboxGroupInput("sf_use", "Current parcel use", choices = names(USE_COL)[1:6], selected = names(USE_COL)[1:6]),
           checkboxInput("sf_sens", "Only residential, school, park or health parcels with no matching cleanup record", FALSE),
           radioButtons("sf_zyear", "Zoning drawn under the sites", c("None" = "none", ZYEARS), selected = "today"),
           tags$small(class = "text-muted", "Each geocoded site is matched to the nearest City and County of Denver assessor parcel within 40 m (1,112 of 1,112 manufacturers'-directory sites and 320 of 321 pre-1960 trades; median distance about 10 m) through Denver's open-data parcel service, which gives the assessor's property class, the current zone district, dwelling units and the year the present building was built (R/site_fate.R). ",
             "A geocoded street address can land on a neighbouring lot where parcels have been consolidated or split, so individual matches should be checked against the Sanborn sheets and reverse directories before being cited. ",
             "'No matching cleanup record' means the site matched no record in the inventories this project searched (EPA FRS/SEMS/RCRA, CDPHE VCUP, environmental covenants); it does not establish that a site was never assessed or remediated.")),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map_sf", height = "62vh"))),
      card(card_header("Current use of the former sites"), unit_note("sites matched to today's assessor parcels, City and County of Denver"), plotlyOutput("p_sf_use", height = 300), tableOutput("t_sf_zone"),
           tags$small(class = "text-muted", "Share of each series' sites by the assessor's current property class. 'Rebuilt' = the present building is newer than the site's last directory listing (a redevelopment indicator, not a closure date); 'zoned industrial' = I-A, I-B or I-MX districts of the 2010 code."))),
    card(card_header("Current use by the decade a site was last listed"), unit_note("sites matched to today's assessor parcels, City and County of Denver"), tableOutput("t_sf_dec"),
         tags$small(class = "text-muted", "Sites that left the directory earlier have had longer to be converted, so the rows are not a conversion rate; they show what stands today on the sites of each cohort. The 1990s row is the sites still listed in 1990 or 1992, the last complete editions.")),
    h5(class = "mt-3 mb-2", "Zoning, 1929 to today"),
    tags$p(class = "small text-muted", "Every Denver zoning map available in digital form: the 1925 ordinance as amended to January 1929 and to April 1944 (Denver Public Library scans, classified for this project), the zone map of 1 July 1955 drawn for the comprehensive ordinance that replaced the 1925 one (History Colorado scan, credit: History Colorado-Denver, Colorado; only its industrial districts were classified), the National Zoning Atlas layer of October 2023 (C. Makarewicz, CU Denver), and the city's official zoning map today, which records the year of the ordinance that last zoned each district. Later citywide maps before 2010 have not been digitised (the library holds them in print), so there is a gap between 1955 and 2023."),
    layout_columns(col_widths = c(6, 6),
      card(card_header("How much land was zoned for industry?"), unit_note("the part of the City and County of Denver covered by both the 1929 and 1944 map sheets (202 km²; half the county, the city as built by 1944)"), plotlyOutput("p_zland", height = 360),
           tags$small(class = "text-muted", "1929 and 1944 distinguish only industrial and commercial districts; the rest is residence or business. For 1955 only the industrial districts (I-1, I-2) were classified; the rest is shown as other districts. Industrial = housing not allowed; industrial mixed use = Denver's I-MX districts, which allow housing (2010 onward).")),
      card(card_header("Zoned industrial, by 1938 HOLC grade"), unit_note("HOLC areas within the part of the City and County of Denver covered by both the 1929 and 1944 map sheets (202 km²; half the county, the city as built by 1944)"), tableOutput("t_zgrade"),
           tags$small(class = "text-muted", "% of each grade's land in industrial districts (housing not allowed); in brackets, including I-MX industrial mixed use."))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("What became of the land zoned industrial in 1929, and when was it last rezoned?"), unit_note("land in the 1929 Industrial A and B districts within Denver County, under today's city zoning map"), tableOutput("t_zfate"),
           tags$small(class = "text-muted", "The year is that of the ordinance that last zoned the land (the city layer's ORD_YEAR), so earlier rezonings are hidden: land shown under 2010, when the whole city was remapped to the new code, may have left industrial zoning at any time after 1944.")),
      card(card_header("Hazardous sites standing in an industrial district, each year"), unit_note("street-located sites within the part of the City and County of Denver covered by both the 1929 and 1944 map sheets (202 km²; half the county, the city as built by 1944)"), tableOutput("t_zsites"),
           tags$small(class = "text-muted", "The 1929 and 1944 columns ask whether the land was zoned industrial before the 1965–92 firms were listed; housing allowed = residential, mixed-use or I-MX districts."))),
    card(card_header("Tracts zoned for industry in 1929 and today: who lived there, 1970–2020"), unit_note("2010 census tracts within 10 km of downtown that lie at least half within the 1929 and 1944 map sheets and Denver County; 'industrial' = 20% or more of the tract's land in industrial districts"), tableOutput("t_zpaths"),
         tags$small(class = "text-muted", "Population-weighted means of tracts with 200+ residents. Between 1990 and 2020 the tracts whose industrial zoning has since been removed lost much of their Hispanic and Black population and their poverty fell by more than half, while tracts still zoned industrial changed less: they stayed largely Hispanic (49% in 1990, 44% in 2020), though their Black share (22% to 14%) and poverty rate (36% to 21%) also fell. Only one tract became industrial after 1929. A description, not an estimate of what rezoning caused.")),
    h5(class = "mt-3 mb-2", "The whole study area in 2023 (National Zoning Atlas)"),
    tags$p(class = "small text-muted", "The 2023 layer was compiled by Carrie Makarewicz (University of Colorado Denver) for the National Zoning Atlas and is shown here with her permission. It is not available for download from this site; to request it, use the form on the ", tags$a(href = "https://storymaps.arcgis.com/stories/adb86c7ab2624e95a84566fecb8a6f6d", target = "_blank", "Denver-metro zoning StoryMap"), "."),
    layout_columns(col_widths = c(7, 5),
      card(card_header("The 1929 zoning districts under 2023 zoning"), unit_note("land area (km²) of the 1929 zoning districts"), div(style = "overflow-x:auto; font-size:0.9em", tableOutput("t_z29")),
           tags$small(class = "text-muted", "Share of the land in each 1925 district (as revised to January 1929; see Redlining & covenants) by its zoning on 3 October 2023. ",
             "Industrial = housing not allowed; 'Industrial mixed use' = Denver's I-MX districts, which allow housing (the parcel-based count above treats them as industrial); Other = open space, civic and other. ",
             "2023 zoning: Denver-metro layer compiled by Carrie Makarewicz (University of Colorado Denver) for the National Zoning Atlas; harmonised categories across 51 jurisdictions.")),
      card(card_header("Hazardous sites by their 2023 zoning"), unit_note("sites (street addresses) in the Denver study area (City and County of Denver plus the 147 2010 census tracts within 10 km of downtown)"), plotlyOutput("p_zsites", height = 420),
           tags$small(class = "text-muted", "Street-located sites in the study area (City and County of Denver plus the 147 tracts within 10 km of downtown) by the 2023 zoning of the land they stand on. ",
             "The suburban rows are the study tracts outside Denver County, which the city's parcel data do not cover. Sites last listed earlier have had longer to be rezoned."))),
    card(card_header("Who lives in the tracts zoned for industry today? 2020 census, by the tract's 2023 share of land zoned industrial (housing not allowed)"), unit_note("the 147 2010 census tracts within 10 km of downtown"), tableOutput("t_ztr"),
         tags$small(class = "text-muted", "The 147 study tracts with 200+ residents in 2020; population-weighted means. A description of where people live today, not a model.")),
    ),
  nav_panel("Before zoning: 1903",
    card(card_header("Housing and industry before zoning: the 1903\u201304 Sanborn maps"),
      tags$p("Denver zoned in 1925. Twenty years earlier, the Sanborn Map Company drew every building in the city for fire insurers. We read 152 sheets of the 1903\u201304 atlas held by the Library of Congress (public domain): the north side from Lower Downtown and the Platte valley to Five Points, Cole, Elyria and Swansea, and Auraria, West Denver and the South Platte corridor. For each block we counted dwellings and recorded every factory, shop and yard with its trade and equipment, then placed each sheet on today's map. On the main Map tab, the layers 'Sanborn 1903\u201304 sheet images' and '1903 blocks: housing & industry' lay the sheet images themselves on today's streets and colour each block by what was on it and next to it (dark red: same block as a hazardous trade; red: across the street from one; pink: same block as, or facing, other industry; pale pink: within 150 m of a hazardous trade; blue: none within 150 m; dashed outlines: plants drawn on unplatted ground); click a sheet for its notes and a link to the full-resolution scan. The 'Sanborn coverage' layers only outline what each edition covers."),
      unit_note("city blocks on the 152 sheets read (1903\u201304); 1910 enumeration districts; 1929 zoning districts")),
    layout_columns(col_widths = c(6, 6),
      card(card_header("How many homes shared a block with industry?"), unit_note("dwellings (D-marked buildings, flats and shanties) on the sheets read"),
           tableOutput("t_s03_area"), tags$small(class = "text-muted", textOutput("s03_cov_txt", inline = TRUE)), tags$br(),
           tags$small(class = "text-muted", "Hazardous trades: foundries, smelters, metal and machine works, chemical and gas works, oil, paint and tar, tanneries, packing houses and stockyards, breweries, brick and pottery kilns, rail shops and power plants. Heavy trades exclude metal and machine shops and breweries. 'Facing' counts dwellings directly across a street from a plant, as drawn. Distances run edge to edge: each block's outline comes from the crossings of the streets that bound it (a 50 m circle where its corners could not be found), and 'across the street' means the next block over a street, not diagonally across a crossing. For about two blocks in five no outline could be built, and the 50 m circle used instead can miss a neighbour across the street along a long side or treat two overlapping circles as touching, so the across-the-street share is approximate. Plants on unplatted ground count as neighbours.")),
      card(card_header("What the 1929 zoning did with them"), unit_note("1903 blocks by the 1929 zoning district they fall in"),
           tableOutput("t_s03_zone"),
           tags$small(class = "text-muted", "The 1929 zoning layer distinguishes Industrial A, Industrial B and Commercial districts; everything else is residence or business districts."))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Who lived there"), unit_note("1910 enumeration districts, weighted by each block's dwellings (full-count census)"),
           tableOutput("t_s03_who")),
      card(card_header("What was there"), unit_note("blocks; establishments as labelled on the sheets"),
           tableOutput("t_s03_trades"), tableOutput("t_s03_out"), tableOutput("t_s03_pers"))),
    card(card_header("After zoning: changes to the zone map, 1925\u20131956"), unit_note("each change to a district boundary in an ordinance amending the 1925 zone map, placed at the blocks or street crossings it names"),
      tags$p("Denver's first zoning ordinance (No. 14, Series of 1925) was amended block by block until the 1956 code. We read every ordinance of 1923\u20131956 in the City's scanned archive that mentions zoning and found each change of district. Where it fell is read from the lots and blocks it names (matched to today's parcel legal descriptions) or the streets its boundary follows. On the main Map, the layer 'Zone changes 1925\u20131956' shows them (red: residential land rezoned for business or industry; blue: land rezoned residential, or moved between residence districts; green: newly annexed land given its first zoning; grey: other changes; faded: the two ways of placing it disagree)."),
      layout_columns(col_widths = c(6, 6), tableOutput("t_rz_holc"), tableOutput("t_rz_dir")),
      tags$small(class = "text-muted", textOutput("rz_note", inline = TRUE)))),
  nav_panel("Land use & freeways",
    layout_columns(col_widths = c(3, 9),
      card(card_header("What was on the ground"), unit_note("20 m cells of the USGS land-use maps on this map (the tables below use the 10 m grid), Denver study area"),
           radioButtons("lu_year", "Year (aerial photographs)", LU_YEARS, selected = 1937, inline = TRUE),
           sliderInput("lu_op", "Opacity", 0, 1, 0.7, 0.05),
           checkboxInput("lu_sites", "Show hazardous sites of the period", TRUE),
           checkboxInput("lu_holc", "Outline the 1938 HOLC D areas", FALSE),
           checkboxInput("lu_zon", "Outline the 1929 industrial zoning", FALSE),
           checkboxInput("lu_hwy", "Show freeways and major roads open that year (OpenHistoricalMap)", TRUE),
           tags$small(class = "text-muted", "Land use interpreted by hand from aerial photographs and historical maps by the U.S. Geological Survey (Drummond, Stier & Diffendorfer 2019, ",
             tags$a(href = "https://doi.org/10.5066/P995RGC9", target = "_blank", "data release"), "; public domain), at 1 m with a minimum mapping unit of about 1 hectare, grouped here into eight categories. ",
             "Unlike zoning, which shows what was allowed, and the directories, which show where firms were listed, this shows what the land was used for. The maps end at latitude 39.62, so a sliver of far-south Denver is blank. ",
             "Sites drawn: 1937 and 1957 = hazardous trades listed in the preceding decade (business directories, street level); 1977 and 1997 = manufacturers' directory sites listed 1968\u20131977 and 1983\u20131992.")),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map_lu", height = "68vh")))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("How the study area was used"), unit_note("mapped land in the Denver study area"), plotlyOutput("p_lu_year", height = 380)),
      card(card_header("Industrial land use by 1938 HOLC grade"), unit_note("HOLC area polygons"), tableOutput("t_lu_holc"),
           tags$small(class = "text-muted", "% of each grade's mapped land in industrial use (light, heavy, refinery). Compare Ibsen et al. (2025, PLoS ONE 20: e0317988), Table 1."))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Zoning and use: how much of the 1929 industrial district was actually industrial?"), unit_note("land in Denver County on the 1929 zoning map, by its 1929 zoning"), tableOutput("t_lu_zone"),
           tags$small(class = "text-muted", "'Share of all industrial use' = the part of the city's industrial land that lay in each kind of district.")),
      card(card_header("Do the directory sites fall on industrial land?"), unit_note("street-located sites in the study area; a site counts if industrial land lies within 30 m"), tableOutput("t_lu_sites"),
           tags$small(class = "text-muted", "An independent check on the inventory: the land-use maps were drawn from aerial photographs without reference to the directories. Sites on no current inventory are the project's 'hidden' sites."))),
    layout_columns(col_widths = c(5, 7),
      card(card_header("What replaced the 1965\u201392 sites' industrial land, 1977 to 1997"), unit_note("land under each site point"), tableOutput("t_lu_trans")),
      card(card_header("Tracts that lost their industrial land: who lived there"), unit_note("2010 census tracts within 10 km of downtown, at least 90% mapped; industrial = 10% or more of the tract's land in industrial use"), tableOutput("t_lu_paths"),
           tags$small(class = "text-muted", "Population-weighted means of tracts with 200+ residents; 1957 land use is set against the 1960 census, 1997 against 2000. A description, not an estimate of what the change in land use caused."))),
    h5(class = "mt-3 mb-2", "Freeways"),
    tags$p(class = "small text-muted", "Dated alignments of Denver's freeways and major roads from OpenHistoricalMap (volunteer-mapped; opening and removal years from its contributors' sources, often CDOT), checked against the NBER/FHWA interstate opening dates for Denver County. OpenHistoricalMap dates the Valley Highway (I-25) from its first sections in the early 1950s; NBER dates interstate segments from when they opened to interstate standard (I-25 1958\u20131965, I-70 1965\u20131968). Choose a year above to see the network open then."),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Freeways through the 1938 HOLC grades"), unit_note("HOLC area polygons; freeways opened 1950\u20131979"), tableOutput("t_hw_holc"),
           tags$small(class = "text-muted", "km of freeway per km\u00b2 of each grade, and the share of each grade's land within 250 m of a freeway built 1950\u20131979. Lengths are km of road: a divided freeway, mapped as two one-way carriageways, is counted once.")),
      card(card_header("Freeway opened, removed and in service, by decade (study area)"), unit_note("freeway centre-lines within the Denver study area"), tableOutput("t_hw_dec"), tableOutput("t_hw_nb"))),
    layout_columns(col_widths = c(5, 7),
      card(card_header("Through industrial or residential land? Freeways of 1950\u20131979 by 1929 zoning"), unit_note("freeway km on the 1929 zoning map"), tableOutput("t_hw_zon")),
      card(card_header("Tracts the freeways cut through: who lived there, 1950\u20131990"), unit_note("2010 census tracts within 10 km of downtown with data in every census 1950\u20131990"), tableOutput("t_hw_tr"),
           tags$small(class = "text-muted", "Population-weighted means; population indexed to 1950 = 100. The census had no Hispanic measure before 1960. A description, not an estimate of what the freeways caused."))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Before and after the freeway opened: gap from comparison tracts"), unit_note("2010 census tracts within 10 km of downtown; each freeway tract lined up on the year a freeway opened within 250 m of it"),
           selectInput("hw_ev_cmp", NULL, choices = if (is.null(hw_ev)) NULL else unique(hw_ev$comparison), selected = if (is.null(hw_ev)) NULL else tail(unique(hw_ev$comparison), 1), width = "100%"), plotlyOutput("p_hw_ev", height = 360),
           tags$small(class = "text-muted", "Each line is the population-weighted gap, in percentage points, between tracts a freeway opened beside (1950\u20131979) and tracts with no freeway within 1 km, by decades since the opening. 0 = the last census before it opened. Hispanic origin is first counted in 1960 and poverty in 1970, so those lines start later.")),
      card(card_header("The same comparison as a table"), unit_note("2010 census tracts within 10 km of downtown"), div(style = "overflow-x:auto", tableOutput("t_hw_ev")),
           tags$small(class = "text-muted", "Population is indexed to 100 at the last census before opening. A comparison of trends, not a causal estimate: the freeways were routed through places already changing."))),
    card(card_header("Urban renewal in Denver: case studies"), unit_note("federal urban-renewal project areas (Renewing Inequality, University of Richmond); census composition estimated from 2010 tracts weighted by the share of each tract's area inside the project"),
      layout_columns(col_widths = c(5, 7),
        div(selectInput("ur_case", NULL, choices = c("Avondale" = "avondale neighborhood", "Blake Street" = "blake st", "Whittier School" = "whittier school", "Jerome Park" = "jerome park",
                                                      "Mitchell" = "mitchell neighborhood", "Skyline (downtown)" = "skyline", "Auraria" = "auraria"), width = "100%"), uiOutput("ur_case_text")),
        div(plotlyOutput("p_ur_case", height = 300), tableOutput("t_ur_case"),
            tags$small(class = "text-muted", "Area weighting assumes residents were spread evenly within each tract, so small projects inherit their surrounding tracts' composition. Hispanic origin is first counted in 1960 and poverty in 1970."))))),
  nav_panel("Lifespan of 1940 residents",
    card(card_header("Where Denver's residents lived in 1940, and how long they lived"),
      tags$p("CenSoc (UC Berkeley) links people counted in the 1940 census to Social Security death records. Every linked Denver resident of 1940 was placed at the street address where the census found them, and features of that address were measured: the 1929 zoning district, industrial land nearby in 1937 (USGS aerial-photograph maps), hazardous trades listed in the city directories up to 1940, the 1938 HOLC grade, and the 1965\u201392 hazardous sites. Age at death is compared among people born in the same year."),
      uiOutput("cs_counts"),
      unit_note("person, at their 1940 street address (Denver residents of 1940 linked to a death record; people in institutions excluded). Only group averages and model estimates are shown; no individual records.")),
    layout_columns(col_widths = c(5, 7),
      card(card_header("Average age at death, by the 1940 address"), unit_note("linked Denver residents of 1940, grouped by their 1940 address; groups of 20 or more people"),
           selectInput("cs_file", "People", names(CS_FILE), width = "100%"),
           radioButtons("cs_meas", "Group by", c("1929 zoning district", "1938 HOLC grade", "Industrial land 1937", "Hazardous trades to 1940"), inline = TRUE),
           plotlyOutput("p_cs_grp", height = 320),
           tags$small(class = "text-muted", "Mean age at death adjusted for birth year (and sex), with CenSoc's population weights. These are raw comparisons: they do not account for who lived where.")),
      card(card_header("Years of life associated with each feature of the 1940 address"), unit_note("linked Denver residents of 1940; one model per feature"),
           checkboxGroupInput("cs_models", NULL, c("Birth year only" = "M1", "+ 1940 person and household traits" = "M2", "+ same 1940 enumeration district" = "M3"), selected = c("M1", "M2"), inline = TRUE),
           plotlyOutput("p_cs_coef", height = 420),
           tags$small(class = "text-muted", "Difference in age at death (years) with 95% interval, for the people chosen on the left. Below zero = shorter lives. Traits: race, Hispanic origin, foreign birth, born in Colorado, moved in 1935\u201340, renting or owning, rent or home value, the household head's schooling and occupational standing. The district version compares neighbours within the same 1940 enumeration district; it is not run for the zoning and HOLC features, which barely vary within a district."))),
    card(card_header("All estimates"), unit_note("linked Denver residents of 1940"), div(style = "overflow-x:auto", tableOutput("t_cs_mod"))),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Young men at WWII Army enlistment, by their 1940 address"), unit_note("Denver men of 1940 born 1905\u20131927, linked to their WWII Army enlistment record (CenSoc); one model per feature"),
           layout_columns(col_widths = c(6, 6), selectInput("enl_sample", "Men", c("Men born 1905\u20131927", "Boys aged 13\u201317 in 1940"), width = "100%"),
                          selectInput("enl_out", "Measured at enlistment", c("Height (inches)", "Weight (pounds)", "Body-mass index", "Years of schooling at enlistment", "Enlisted (percentage points)"), width = "100%")),
           plotlyOutput("p_enl", height = 380),
           tags$small(class = "text-muted", "Difference at enlistment with 95% interval, after the same 1940 person and household traits, comparing men born in the same year who enlisted in the same year. Height and weight were recorded only for enlistments before March 1943, so they rest on few men (about 1,400 men, 350 of them boys aged 13–17 in 1940, the youngest the 1905–1927 birth years allow). Men rejected on health grounds never appear in these records.")),
      card(card_header("At enlistment, by 1940 address (averages)"), unit_note("Denver men of 1940 born 1905\u20131927"), tableOutput("t_enl_sh"),
           tags$small(class = "text-muted", "Raw averages among men who enlisted from civilian life; share enlisted among all men of these ages in 1940 who could be linked."))),
    card(card_header("Further checks"), unit_note("linked Denver residents of 1940 (and, for the last two, Denver residents of 1940 traced to their 1910\u20131930 census records through the IPUMS Multigenerational Longitudinal Panel)"),
         selectInput("cs_chk", NULL, names(CS_CHK), width = "100%"), uiOutput("cs_chk_note"), div(style = "overflow-x:auto", tableOutput("t_cs_chk"))),
    card(card_header("What this shows, and what it doesn't"),
      tags$ul(
        tags$li("Men who lived in 1940 in a 1929 industrial district died about 1.6 years younger than other Denver men born the same year, and about a year younger once their own and their household's 1940 circumstances are taken into account. More industrial land within 250 m of the home went with shorter lives (about 0.2 years per 10 percentage points)."),
        tags$li("Commercial land nearby, a check for simply living somewhere busy and central, shows nothing."),
        tags$li("The HOLC D gap shrinks to a third of a year once household circumstances are accounted for: the grade mostly reflects who lived there. Hazardous trades counted as firms, and the 1965\u201392 hidden sites, show little once circumstances are accounted for."),
        tags$li("Within a single 1940 enumeration district the industrial-land difference disappears, so it lies between neighbourhoods and could reflect something else about them. Men and women dying at 65+ in 1988\u20132005 show the same direction, much weaker."),
        tags$li("The gap for men is concentrated among those aged 15\u201329 in 1940 (about 1.6 years in an industrial district). It holds when each man's own 1940 job, or his household head's, is taken into account: hazardous-industry jobs themselves show nothing. Residents of industrial addresses were no less likely to link to a death record, or to die in the Denver area."),
        tags$li("The survival-model check (Gompertz, deaths 1975\u20132005) points the same way for the industrial district (hazard ratio 1.10, not statistically clear) and the D grade (1.16, 1.01\u20131.34, about a year less life at 65), and shows nothing for industrial land: treat the size of the industrial-land gradient with caution."),
        tags$li("At WWII enlistment, men from industrial addresses had about half a year less schooling, and were somewhat shorter and lighter (height and weight rest on few men). Living in 1940 where a freeway was later built, or on land later cleared, shows no difference in lifespan; addresses in a later freeway's path were far more Hispanic (15%) than the rest of Denver (4%), though addresses on later-cleared land were not (2%)."),
        tags$li("People moved after 1940, only some of the population links to a death record (CenSoc's weights adjust for part of this), and the death windows are truncated. These are associations, not causal estimates.")),
      tags$small("Data: CenSoc-DMF v4 and CenSoc-Numident v3 (Breen, Osborne & Goldstein 2023, ", tags$a(href = "https://censoc.berkeley.edu", target = "_blank", "censoc.berkeley.edu"),
                 "); IPUMS USA 1940 complete count; 1940 addresses from Brown University's Urban Transition project. None of the person-level data is redistributed here."))),
  nav_panel("Redlining & covenants",
    layout_columns(col_widths = c(3, 6, 3),
      card(card_header("HOLC 1938 map and racial covenants 1931\u201335"), unit_note("HOLC area polygons (1938), deed points (covenants) and firm points"),
           checkboxGroupInput("rl_layers", NULL, c("HOLC security grades (1938)" = "holc", "Zoning districts (choose the year below)" = "zon", "Freeways built 1950\u20131979" = "hwy", "Racial covenants 1931-35 (deeds)" = "cov", "Hazardous-trade firms" = "firms", "1930 enumeration districts" = "ed30"),
                              selected = c("holc", "cov", "firms")),
           conditionalPanel("input.rl_layers.includes('zon')", radioButtons("rl_zyear", "Zoning year", ZYEARS, inline = FALSE), tags$small(class = "text-muted", "1944: districts changed since 1929 are outlined (dashed). 1955: the industrial districts (I-1, I-2) of the zone map of 1 July 1955 (History Colorado-Denver, Colorado). Today: the city's official zoning map; 2023: the National Zoning Atlas layer (C. Makarewicz, CU Denver; to obtain it, use the request form on the ", tags$a(href = "https://storymaps.arcgis.com/stories/adb86c7ab2624e95a84566fecb8a6f6d", target = "_blank", "StoryMap"), "). ", "Denver's first zoning ordinance (February 1925) as shown on the official Building Zone Map revised to January 1929 (Denver Public Library, CG4314 .D4 G44 1929), georeferenced from 13 street intersections (RMSE 25 m) and classified by hatch pattern: Industrial A, Industrial B and Commercial districts; everything else was Residence A–E or Business. Residence E (apartments) shares a hatch with Industrial A and is told apart only by lot lines, so a few platted blocks are uncertain (R/zoning_1925.R).")),
           conditionalPanel("input.rl_layers.includes('ed30')", selectInput("rl_edvar", "Shade 1930 districts by", c("Black (%)" = "pct_black", "Hispanic (%)" = "pct_hisp", "Foreign born (%)" = "pct_fb", "Laborers (%)" = "pct_laborers",
                                                                                 "Racial covenants recorded 1931-35" = "covenants", "HOLC class of the district (1938)" = "grade", "Hazardous firms before the map (to 1937)" = "firms_pre1938", "Hazardous firms after the map (1938-56)" = "firms_1938_1956", "Hazardous-sector sites 1965-1992" = "firms_1961_2002"))),
           conditionalPanel("input.rl_layers.includes('firms')", radioButtons("rl_firms", "Hazardous-trade firms listed (orange-red dots)", c("Before the map: 1871-1937 (street level)" = "pre", "1921-1937 only" = "mid", "After the map: 1938-1956" = "post"), selected = "pre")),
           tags$small(class = "text-muted",
             "The Home Owners' Loan Corporation graded Denver's neighbourhoods A (\u2018best\u2019) to D (\u2018hazardous\u2019) in 1938; its appraisers' forms record what they saw as detrimental influences, the share of foreign-born and Black families and any \u2018infiltration\u2019. ",
             "Click an area for its description. Racial covenants are deeds recorded 1931\u201335 that barred non-white occupants (Denver Public Library's Mapping Prejudice pilot); some also barred manufacturing. ",
             "Xu (2022) showed for Chicago that HOLC's maps were post-hoc appraisals while the FHA's map drove lending; we have not located a surviving Denver FHA mortgage-risk map, so the question here is what the HOLC grades ratified: the 1900\u20131940 districts show who already lived next to industry before the map was drawn, and the 1940\u20132020 panel what followed."),
           ),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map_rl", height = "62vh"))),
      card(card_header("After the map: 2010 tracts by dominant HOLC grade, 1940\u20132020"), unit_note("2010 census tracts grouped by dominant HOLC grade (1940–2020); dashed 1900–1940: reconstructed enumeration districts area-weighted into the HOLC areas"),
           selectInput("rl_var", NULL, c("Hispanic (%)" = "p_hisp", "Black (%)" = "p_black", "Foreign born (%)" = "p_fb", "Below poverty (%)" = "p_pov", "Owner-occupied (%)" = "p_owner", "Median home value (2020 $)" = "mval_2020", "Median rent (2020 $)" = "mrent_2020", "Hazardous firms in decade" = "firms_haz"), selected = "p_hisp"),
           plotlyOutput("p_holc_tr", height = 300),
           tags$small(class = "text-muted", "Dashed, 1900-1940: the reconstructed enumeration districts of each census area-weighted into the HOLC polygons themselves (fixed boundaries, so no harmonisation; the only approximation is the area weighting). ",
             "Solid, 1940-2020: population-weighted means of 2010 tracts at least 40% inside graded areas (about 4 A, 6 B, 37\u201341 C and 19 D tracts, depending on the census), with earlier censuses interpolated to 2010 tracts. The two 1940 points show how much the change of unit matters. Vertical line: the 1938 map. ",
             "Gaps: no census tract table measures Hispanic origin before 1960 (the 1900-1940 values are the full count's HISPAN; the 1940 tract point is filled from the districts), poverty starts in 1970, and 'hazardous firms in decade' counts street-level directory firms active in the ten years to each census."),
           )),
    card(card_header("1930 enumeration districts by HOLC class and covenants: who lived there, and industry before and after the map"), unit_note("1930 enumeration districts (reconstructed)"), tableOutput("t_edcls"),
         tags$small(class = "text-muted", "Each 1930 district takes its largest HOLC class when at least 30% of its area is graded ('ungraded' otherwise); 'covenants' = at least one 1931-35 racial covenant deed inside it. Firms per 10,000 residents of 1930. HOLC's Industrial and Commercial zones carried no residential grade but held most of the pre-map industry.")),
    layout_columns(col_widths = c(7, 5, 5, 7),
      card(card_header("HOLC areas by grade: industry, the appraisers' remarks, covenants, and who lived there (1930 and 1940 full count, reconstructed districts)"), unit_note("HOLC area polygons; 1930 and 1940 composition from reconstructed districts, area-weighted"), tableOutput("t_holc_g"),
           tags$small(class = "text-muted", "Population-weighted; 'remarks cite industry' = the area's detrimental influences or remarks mention industry, factories, smelters, railroads, smoke or odors. Firms are the street-level hazardous trades of the business directories; 'before the map' = any listing 1871-1937.")),
      card(card_header("Where the facilities are: share by HOLC grade, then and now"), unit_note("facilities (points), by the HOLC grade of the land they stand on"), plotlyOutput("p_holc_sh", height = 360),
           tags$small(class = "text-muted", "Share of each layer's facilities that fall inside HOLC's A-D residential grades and its ungraded Industrial and Commercial zones (facilities outside all HOLC areas excluded), against the classes' shares of land and of 1940 population. Hazardous trades: street-level business-directory listings; 1965-1992: this project's geocoded hazardous-sector sites; today: EPA TRI and the cleanup inventories.")),
      card(card_header("Mortgage lending today by HOLC grade: HMDA 2018-21 home-purchase applications"), unit_note("2010 census tracts grouped by dominant HOLC grade"), tableOutput("t_hmda"), uiOutput("hmda_note"),
           tags$small(class = "text-muted", "2010 tracts by dominant HOLC grade; denial rate = denied / (originated + denied), so withdrawn and incomplete applications are excluded. Context for the 1938 map, not evidence that its classifications were implemented: who gets credit in the graded areas today. Source: CFPB HMDA data browser (R/fetch_hmda.R).")),
      card(card_header("Change in tract outcomes by grade, A = reference"), unit_note("2010 census tracts grouped by dominant HOLC grade"), selectInput("rl_mvar", "Outcome", c("Black %" = "p_black", "Hispanic %" = "p_hisp", "Poverty %" = "p_pov", "Owner-occupied %" = "p_owner", "log median home value (2020 $)" = "lmval")), tableOutput("t_holc_m"),
           tags$small(class = "text-muted", "Percentage points over the period relative to tracts dominated by A areas; the period's starting value of the outcome, 1940 % Black and 1931-40 firms controlled (poverty and the Hispanic share are measured consistently only from 1970, so their periods start in 1970); 'net of 1925 zoning' adds the tract's share zoned industrial in 1929; HC1 SE, with classical and spatially robust Conley SEs (2 km cutoff) in the downloadable table. ** p<0.01, * p<0.05 on the HC1 errors; only the D estimates for the Hispanic share and home value hold under all three. Each tract takes the class (A-D, or HOLC's ungraded Industrial or Commercial zones) covering most of it; a class with fewer than five tracts in a period is left out, since one or two tracts cannot carry an estimate, and the A reference class has only four. Compare Xu (2022), Table 3, for Chicago."))),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Did the map create or reinforce? The D–C gap census by census, 1900–2020"), unit_note("areas either side of HOLC C–D boundaries: reconstructed enumeration districts 1900–1940, 2010 census tracts 1940–2020"),
           layout_columns(col_widths = c(4, 3, 5), selectInput("rl_bvar", "Outcome", c("Black (%)" = "p_black", "Hispanic (%)" = "p_hisp", "Foreign born (%)" = "p_fb", "Owner-occupied (%)" = "p_owner", "Below poverty (%)" = "p_pov", "Laborers (%)" = "p_laborers")),
                          selectInput("rl_pair", "Grades", c("D minus C" = "D-C", "D minus B" = "D-B", "D minus A" = "D-A", "C minus B" = "C-B", "C minus A" = "C-A", "B minus A" = "B-A")),
                          radioButtons("rl_bdes", "Comparison", c("Boundary band: units within 400 m (districts) / 800 m (tracts) of both grades, lying in one of them" = "band", "All areas of each grade" = "all"))),
           uiOutput("holc_bd_note"),
           plotlyOutput("p_holc_bd", height = 340), tableOutput("t_holc_bd"),
           tags$small(class = "text-muted", "Design after Aaronson, Hartley & Mazumder (2021): the D-side minus C-side difference (population-weighted, HC1 SE) is tracked before and after the 1938 map (grey line). Before 1940 the units are the reconstructed enumeration districts, ",
             "whose centroid falls in a C or D area; from 1940 they are 2010 tracts with earlier censuses interpolated. A gap already widening before 1938 means the map ratified an existing divergence; one that opens only afterwards points to the map (or to the FHA practices and covenants of the same years — Fishback, Rose, Snowden & Storrs 2024 find FHA, not HOLC, drove lending). ",
             "Green crosses and the 'net of rail + 1925 zoning' column add the share of each unit zoned industrial on the 1929 building-zone map as a second control (the ordinance that the appraisers were themselves reading). Blue crosses and the 'net of rail' column: the same gap with each unit's distance to the nearest rail line (TIGER/Line; today's network, in Denver essentially the pre-1900 trunk lines and yards) added to the regression, since a boundary that follows a railway can differ for reasons other than the grade. For 1920 the 1929 zoning share stands in for land already in industrial use, since the ordinance came in 1925. Stars are HC1; with spatially robust (Conley, 2 km) errors the district Black gaps of 1930 and 1940 are not significant (paper SI). ",
             "Error bars are 95% intervals of the difference in population-weighted means across the units in the band: they are wide after 1940 because only ~15 tracts lie on each side and tract-level shares are far more dispersed than district-level ones (a few Five Points tracts were 60-80% Black while most were near 0), and for pairs involving A or B because those areas are few.")),
      card(card_header("Industry by HOLC grade before and after the map: hazardous firms per km²"), unit_note("HOLC area polygons (firms per km² of each grade)"), tableOutput("t_holc_ind"),
           tags$small(class = "text-muted", "Street-level hazardous trades in the business directory (1891–1956) and hazardous-sector manufacturers in the complete editions of the Directory of Colorado Manufacturers (1965–1992), active in each period, per km² of each grade's area. ",
             "Read the D/C ratio within one source: the business directory (to 1956) and the manufacturers' directory (from 1965) list different things, and periods hold different numbers of editions, so the step between 1938\u201356 and 1965\u201380 is mostly the change of source. Per edition, D/C is about the same just before the map (1921\u201337) and just after it (1938\u201356); the downloadable table gives firms per km\u00b2 per edition and the D/C ratio within each period."),
           tags$hr(), tags$b("The 1925 zoning ordinance by HOLC grade"), tableOutput("t_holc_zon"),
           tags$hr(), tags$b("Did the districts change around the map? 1929 and 1944 compared"), tableOutput("t_zon44"), tableOutput("t_zch"),
           tags$small(class = "text-muted", "The April 1944 revision of the same map, registered to the 1929 sheet and classified the same way; every difference of a block or more was checked by eye on both scans and only visibly redrawn districts kept (8 areas; 118 candidates reviewed). ",
             "No industrial district was added between 1929 and 1944; about 0.5 km² of Industrial A (2%) was redrawn as commercial, business or residence districts, and the share of D land zoned industrial went from 16.2% to 15.9%. Changes smaller than a block, and later hand-coloured amendments on the 1944 copy, are not included."),
           tags$details(tags$summary(tags$small("See the 1929 Building Zone Map and how it was classified")),
             layout_columns(col_widths = c(6, 6),
               tags$figure(tags$a(href = "zoning_1929_scan.jpg", target = "_blank", tags$img(src = "zoning_1929_scan.jpg", style = "width:100%; border:1px solid #ddd")),
                           tags$figcaption(tags$small("Building Zone Map, City and County of Denver, adopted February 1925, revised to January 1, 1929. Denver Public Library Western History Collection, CG4314 .D4 G44 1929. Click to open full size."))),
               tags$figure(tags$a(href = "zoning_1929_classified.jpg", target = "_blank", tags$img(src = "zoning_1929_classified.jpg", style = "width:100%; border:1px solid #ddd")),
                           tags$figcaption(tags$small("The same scan with the texture classification drawn over it: red = Industrial A, blue = Industrial B, yellow = Commercial. Residential (hatched blocks with lot lines) and Business (solid black) districts are left unclassified. Georeferenced in R/zoning_1925.R and shown as a map layer above."))))),
           tags$small(class = "text-muted", "Share of each grade's land that the city had zoned Industrial (A or B) or Commercial by January 1929, nine years before the HOLC map (the ordinance itself dates from 1925) (R/zoning_1925.R; see the map layer). The ordinance and the appraisers drew the same line: the industrial corridor of the Platte and the rail yards is D land or left ungraded as 'Industrial'.")))
    ),
  ),
  nav_panel("Colorado trends",
    card(card_header("Denver in Colorado"),
      tags$p(class = "mb-1", "The rest of this site is about Denver. This tab places it in the state, using the same rules: Frickel & Elliott's hazardous sectors, the 13 complete manufacturers' directory editions, street-located sites, a 200-resident minimum and fixed sets of tracts. ",
        "In short: before 1940 the hazardous trades moved from the mining districts to Denver and went with immigrant, not Hispanic, Colorado; after 1965 manufacturing left Denver for its suburbs and the northern Front Range; ",
        "and since 1990 the Hispanic share is higher beside hazardous industry across the Front Range cities but not in rural Colorado, while poverty and renting are higher beside it everywhere. The associations are between places at one date, not estimates of what caused what.")),
    layout_columns(col_widths = c(7, 5),
      card(card_header("1880–1940: where the state's hazardous trades were, by region"), unit_note("Colorado counties (each census's boundaries) grouped into regions"), plotlyOutput("p_co_reg", height = 380),
           tags$small(class = "text-muted", "Solid: share of the state's listed hazardous trades (business directory, trades of the ten years ending at the census, town or street level). Dashed: share of the state's population (IPUMS full count). ",
             "The number of surviving directory editions differs between censuses (none survives for 1893–1909), so read direction, not exact levels. Mining counties: Lake, Gilpin, Clear Creek, San Juan, Ouray, Teller, Summit, Hinsdale, Park, Chaffee, San Miguel, Mineral; ",
             "southern Hispano counties: Conejos, Costilla, Huerfano, Las Animas, Rio Grande, Saguache, Alamosa.")),
      card(card_header("Across counties: trades per resident and who lived there"), unit_note("Colorado counties with 1,000+ residents, on each census's boundaries"), tableOutput("t_co_cor"),
           tags$small(class = "text-muted", "Correlation across counties (1,000+ residents, each census's own boundaries) of log hazardous trades per 1,000 residents with each share. ",
             "More trades went with more immigrants in every census and with fewer Hispanic residents in five of six: the Hispano south was farming and coal country with few listed trades."))),
    layout_columns(col_widths = c(5, 7),
      card(card_header("1880–1940 counties"), unit_note("Colorado counties on each census's boundaries"), selectInput("co_year", "Census", c(1880, 1900, 1910, 1920, 1930, 1940), selected = 1920),
           selectInput("co_var", "Shade counties by", c("Hazardous trades per 1,000 residents" = "rate", "Hispanic (%)" = "pct_hisp", "Foreign born (%)" = "pct_fb", "Black (%)" = "pct_black", "Laborers (%)" = "pct_laborers")),
           tags$small(class = "text-muted", "IPUMS full-count census aggregated by county on that census's boundaries (NHGIS); hazardous trades of the decade from the business directory.")),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map_co", height = "52vh")))),
    layout_columns(col_widths = c(7, 5),
      card(card_header("1965–1992: where the hazardous-sector manufacturers were, by region"), unit_note("sites (street addresses) statewide, grouped into regions by county"), plotlyOutput("p_co_share", height = 380),
           tags$small(class = "text-muted", "Share of the state's located hazardous-sector manufacturers in each complete edition. The 1965 edition places 73% in Denver, an outlier against every later edition. ",
             "Denver suburbs: Adams, Arapahoe, Broomfield, Douglas and Jefferson counties.")),
      card(card_header("Share of the 1990 population"), unit_note("regions (groups of counties)"), tableOutput("t_co_pop"))),
    layout_columns(col_widths = c(8, 4),
      card(card_header("1990–2020: who lives beside hazardous industry, by region"), unit_note("Colorado 2010 census tracts with 200+ residents"), plotlyOutput("p_co_assoc", height = 420),
           tags$small(class = "text-muted", "Every Colorado tract with 200+ residents in each census from 1990 (1,158). Percentage points per log unit of hazardous firms of the decade per km², with log population density and county fixed effects; bars are 95% intervals (HC1). ",
             "2000–2020 use the 1983–1992 sites, so those years describe who lives around historically listed industrial land, not new siting. In Denver the Hispanic association fades by 2020 while it grows in the suburbs and the northern Front Range.")),
      card(card_header("Outcome"), radioButtons("co_out", NULL, c("% Hispanic", "% below poverty", "% owner-occupied", "% foreign born", "% Black", "% White")),
           tags$small(class = "text-muted", "Regions: Denver (City and County); Denver suburbs; Boulder, Larimer and Weld; Colorado Springs (El Paso); Pueblo; Grand Junction (Mesa, too few tracts for this chart); rest of Colorado."))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Today: historical industry and present burdens, Colorado tracts"), unit_note("Colorado 2010 census tracts"), tableOutput("t_co_leg"),
           tags$small(class = "text-muted", "1,428 Colorado tracts (2020) with 500+ residents; spatial-error models with log population density. Per log unit of the predictor. Associations at one date. ",
             "Firm-years = establishment-editions in the complete editions 1965–1992; sites on no list = hazardous sites with no match in the searched inventories. Outcomes are CDPHE EnviroScreen indicators.")),
      card(card_header("The other graded cities"), unit_note("appraisal-map areas and 2010 census tracts in each graded city"),
           tags$p(tags$small("Mapping Inequality holds Pueblo's 1938 HOLC map (A–D) and local appraisal maps of Colorado Springs, Greeley, Fort Collins, Grand Junction, Boulder, Longmont and Fort Morgan. ",
             "They cannot carry the Denver analysis: outside Denver the pre-1960 directory places trades only at the town, the full count has not been rebuilt into districts, and the graded areas cover 1–12 tracts. ",
             "The table puts every map's grades on one scale (best / middle / worst) and gives hazardous-sector manufacturers per km² per edition; with so few areas it is descriptive only.")),
           tableOutput("t_co_gc"))),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Phases of Colorado manufacturing: share of listed firms by industry, 1965–1992 (all manufacturers, complete editions)"), unit_note("firms statewide, per edition"), plotlyOutput("p_mix", height = 420),
           tags$small(class = "text-muted", "* = Frickel & Elliott hazardous sector. Shares of firms with an industry code in each edition; the directories' coverage changes between editions.")),
      card(card_header("How long did firms stay listed?"), unit_note("firms statewide"), plotlyOutput("p_longev", height = 420),
           tags$small(class = "text-muted", "Years between a firm's first and last listing (firms linked across editions). Firms still listed in 1992 or first listed in 1965 are cut off by the directory's own span."))),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Do hazardous sectors cluster more than manufacturing in general? Ellison–Glaeser index by edition, statewide"), unit_note("1 km grid cells, all of Colorado"), plotlyOutput("p_eg_co", height = 380),
           tags$small(class = "text-muted", "As on the Trends tab, for all of Colorado (1 km cells).")),
      card(card_header("Succession: what replaced what in 500 m cells (dominant sector, one edition to the next), statewide"), unit_note("500 m grid cells, all of Colorado"), plotlyOutput("p_trans", height = 380),
           tags$small(class = "text-muted", "The 15 most common changes of a cell's dominant sector between consecutive complete editions, 1965–1992."))),
    tags$small(class = "text-muted", "Code: R/county_panel_1880_1940.R, R/statewide.R, R/corridors.R.")),
  nav_menu("Explore more",
  nav_panel("Contamination & health",
    card(card_header("After the factories: contamination, emissions, renewal and health"),
      tags$p("Public records that pick up where the directories leave off: petroleum releases from storage tanks (1986\u2013), toxic releases reported to EPA (1987\u2013), measured air quality (1980\u2013), federal urban-renewal projects, Superfund units, modelled childhood lead risk, and health today by census tract. A record near a former site is not proof of contamination from that site, and no record is not proof of none."),
      unit_note("varies by layer: points (releases, facilities, monitors), project and Superfund polygons, 2010 census tracts within 10 km of downtown plus the City and County of Denver")),
    layout_columns(col_widths = c(3, 9),
      card(card_header("Map"), unit_note("2010 census tracts (shading); points and polygons as listed"),
           selectInput("cx_var", "Shade tracts by", choices = if (is.null(hl_tr)) NULL else CX_VARS[CX_VARS %in% names(hl_tr)], width = "100%"), sliderInput("cx_op", "Shading opacity", 0, 1, 0.6, 0.05),
           sliderInput("cx_tri_year", "TRI year (circle size = air releases)", if (is.null(tri_fy)) 1987 else min(tri_fy$year), if (is.null(tri_fy)) 2024 else max(tri_fy$year), if (is.null(tri_fy)) 1990 else min(tri_fy$year), step = 1, sep = "", ticks = FALSE, width = "100%"),
           checkboxInput("cx_aerial", "1933 aerial photograph", FALSE),
           tags$small(class = "text-muted", "Toggle layers with the control on the map. Tract health figures are model-based estimates (CDC PLACES 2024 release; life expectancy 2010\u201315, NCHS USALEEP; lead risk: CDPHE 2018 model).")),
      card(full_screen = TRUE, leafletOutput("map_cx", height = 620))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Former sites with a later petroleum release or storage-tank facility"), unit_note("historical sites in the study area; releases and tank facilities within 50 m of the geocoded address"),
           tableOutput("t_cx_pet"), tags$small(class = "text-muted", "Petroleum releases reported to the Colorado Division of Oil & Public Safety since 1986. 50 m matches the precision of directory street addresses; a nearby release may come from a neighbouring property."),
           tableOutput("t_cx_pet_use")),
      card(card_header("Toxic releases reported to EPA, 1987 onward"), unit_note("TRI facility-years in the study area, by the 1938 HOLC grade of the facility's location"),
           radioButtons("cx_tri_measure", NULL, c("Air releases (lb)" = "air", "Reporting facilities" = "fac"), inline = TRUE), plotlyOutput("p_cx_tri", height = 330),
           tags$small(class = "text-muted", "TRI covers only facilities and chemicals above reporting thresholds; the list of chemicals and industries has grown over time, so trends mix real change and reporting rules."))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Measured air quality, Denver-metro monitors"), unit_note("EPA AQS monitors in Adams, Arapahoe, Broomfield, Denver, Douglas and Jefferson counties; annual means"),
           selectInput("cx_pol", NULL, choices = if (is.null(aqs)) NULL else sort(unique(aqs$pollutant)), selected = if (!is.null(aqs) && "Lead (TSP)" %in% aqs$pollutant) "Lead (TSP)" else NULL, width = "100%"), plotlyOutput("p_cx_aqs", height = 300),
           tags$small(class = "text-muted", "Average of the annual means of the monitors operating that year; the network changed over time, so the number of monitors is shown on hover.")),
      card(card_header("Urban renewal projects in Denver"), unit_note("federal urban-renewal projects (Renewing Inequality, University of Richmond)"),
           div(style = "overflow-x:auto", tableOutput("t_cx_ur")),
           tags$small(class = "text-muted", "Families and dwellings are the latest figures in the federal Urban Renewal Project Characteristics reports, which give race only for 1955\u20131966: later projects such as Skyline and Auraria have no family counts here. Dashed outlines on the map are approximate boundaries."))),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Health today, by the industrial history of the tract"), unit_note("2010 census tracts within 10 km of downtown plus the City and County of Denver; population-weighted means"),
           div(style = "overflow-x:auto", tableOutput("t_cx_health")),
           tags$small(class = "text-muted", "Tracts grouped by the historical sites inside them (1965\u201392 hazardous-sector manufacturers on a current inventory = known, on none = hidden; street-level hazardous trades before 1960). PLACES values are % of adults; these are descriptive comparisons that do not adjust for income, age or smoking.")),
      card(card_header("Superfund and lead in north Denver"), unit_note("EPA Superfund operable units; CDPHE modelled lead-risk decile by tract"),
           tags$p(class = "small", "The Vasquez Boulevard/I-70 Superfund site covers about 4.5 square miles of Globeville, Elyria-Swansea, Cole, Clayton and Curtis Park, contaminated with lead and arsenic from the Omaha & Grant and Argo smelters (1870s to early 1900s). EPA sampled about 99% of some 4,500 residential properties and replaced the soil at about 800; the residential unit was deleted from the National Priorities List in 2019 (CDPHE)."),
           tableOutput("t_cx_rod"),
           tags$small(class = "text-muted", "Residential yards sampled 1998\u20132003, by neighbourhood: 95th percentile and maximum of the average of three soil composites per yard (ppm). EPA Record of Decision, 25 September 2003, Table 3. Property-level results are not public."),
           tags$p(class = "small", "Measured childhood blood-lead results are published only by county; the map's lead layer is CDPHE's modelled risk decile (housing age, poverty and related factors), not test results."),
           tags$small(tags$a(href = "https://cdphe.colorado.gov/hm/vb-l70-superfund-site", target = "_blank", "CDPHE: Vasquez Boulevard/I-70 site")))),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Home prices near historical sites"), unit_note("arm's-length residential sales in the City and County of Denver, 2015 onward (Denver Assessor); each sale located at its parcel"),
           radioButtons("hd_model", NULL, c("Same neighbourhood and year, with present-day hazards" = "M2 + present-day hazards", "Same neighbourhood and year" = "M1 base: neighbourhood x year FE",
                                             "Same census tract and year" = "M3 tract x year FE"), inline = TRUE),
           plotlyOutput("p_hedonic", height = 330),
           tags$small(class = "text-muted", "Percentage difference in sale price compared with otherwise similar homes in the same market neighbourhood and year that sold more than 800 m from any site of that kind (95% confidence interval). Controls: floor area, basement, bedrooms, baths, stories, lot size, age, property type and month; errors clustered by tract. Present-day hazards: a petroleum release within 100 m, a TRI facility within 500 m, a Superfund operable unit, a freeway within 250 m and industrial zoning.")),
      card(card_header("Known versus hidden: within 400 m"), unit_note("same sales; one indicator per kind of site within 400 m"),
           tableOutput("t_hedonic"),
           tags$p(class = "small", "If buyers respond to what they can look up, homes near sites on a current environmental inventory should sell at a discount while homes near hidden sites, which leave no record, should not. The last row tests whether the two differ."),
           tags$small(class = "text-muted", "Only model results are shown; no individual sales or owners.")))),
  nav_panel("Who owns rental housing",
    card(card_header("Who owns Denver's rental housing?"),
      tags$p("Every residential parcel in the City and County of Denver, from the Assessor's public records. A unit counts as rental when its owner's mailing address is somewhere else, so second homes and vacant units are included. Parcels are grouped into owners by name, and more broadly into owner families when several names (often LLCs) share one mailing address. Only totals and shares are shown; no owner is named."),
      unit_note("parcels and units in the City and County of Denver; map: 2010 census tracts with 50+ rental units")),
    layout_columns(col_widths = c(3, 9),
      card(card_header("Map"), unit_note("2010 census tracts, City and County of Denver"),
           selectInput("ow_var", "Shade tracts by", OW_VARS, width = "100%"),
           tags$small(class = "text-muted", "Owner size counts the owner family's rental units across all of Denver. Tracts with fewer than 50 rental units are left blank.")),
      card(full_screen = TRUE, leafletOutput("map_own", height = 520))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("How big are Denver's landlords?"), unit_note("owners of at least one rental unit; units not occupied by their owner"),
           radioButtons("ow_group", NULL, c("Owner families (names linked by mailing address)" = "by owner family (shared mailing address)", "Owner names" = "by owner name"), inline = TRUE),
           plotlyOutput("p_own_size", height = 330),
           tags$small(class = "text-muted", "Bars: share of all rental units held by owners of each size; hover for the number of owners. Grouping by name alone misses landlords who hold property through many differently named LLCs; grouping by mailing address can join unrelated owners who use the same agent, so the two bracket the true concentration.")),
      card(card_header("Concentration"), unit_note("privately owned rental units (public agencies excluded)"),
           tableOutput("t_own_conc"),
           tableOutput("t_own_types"))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Near historical sites and by 1938 HOLC grade"), unit_note("parcels within 400 m of a historical site, and parcels inside each 1938 HOLC area"),
           tableOutput("t_own_place")),
      card(card_header("Where large landlords own"), unit_note("2010 tracts with 50+ rental units; regression weighted by rental units"),
           tableOutput("t_own_assoc"),
           tags$small(class = "text-muted", "Differences in percentage points per point of each tract characteristic (2020), or for tracts that contain a historical site, holding the others constant. Associations, not causes."))),
    layout_columns(col_widths = c(5, 7),
      card(card_header("How much does linking owners reveal?"), unit_note("privately owned rental units; owners linked in stages"),
           tableOutput("t_own_ladder"),
           tags$small(class = "text-muted", "Each stage joins more records into one owner: exact names and addresses; cleaned spellings; near-identical names; names sharing a mailing address; and, where available, companies sharing a principal address or a named registered agent in the Colorado business registry. The gain at each stage shows how much ownership is spread across differently named entities (after Hangen & O'Brien 2025).")),
      card(card_header("Where owners are"), unit_note("privately owned rental units, by the owner's mailing ZIP code"),
           selectInput("ow_loc_group", NULL, c("Owner family size", "Owner type", "1938 HOLC grade", "Historical sites"), width = "60%"),
           tableOutput("t_own_loc"),
           tags$small(class = "text-muted", "From the owner's mailing address, which can be a manager's or tax agent's office rather than where the owner lives. Income and white share are those of the owner's and the property's ZIP code areas (ACS 2018-22), weighted by rental units (after Preis 2024 and Hochstenbach 2022)."))),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Housing complaints by landlord"), unit_note("rental buildings (parcels sharing a street address); 311 requests linked to buildings"),
           selectInput("cond_group", NULL, c("Owner family size (rental units in Denver)", "Owner type", "Owner location", "Building type", "1938 HOLC grade", "Historical sites"), width = "60%"),
           tableOutput("t_cond_rates"), tableOutput("t_cond_models"),
           tags$small(class = "text-muted", "311 requests to Public Health & Environment about conditions inside homes (mold, no heat or water, pests, water damage) and to Community Planning & Development about the outside of a property (trash, weeds, storage, neglect, graffiti on private property). Ratios: Poisson models with tract fixed effects, controlling for the building's units, type, age, owner type and out-of-state owner (after An et al. 2024). A request is a report, not a confirmed violation, and tenants' willingness to call varies.")),
      card(card_header("Eviction filings"), unit_note("City and County of Denver by year; 2010 census tracts where tract data are available (Eviction Lab)"),
           tableOutput("t_ev_county"), tableOutput("t_ev"), tableOutput("t_ev_m"), tags$small(class = "text-muted", textOutput("ev_note", inline = TRUE)),
           tags$small(class = "text-muted", "Eviction Lab (Princeton) counts of eviction cases filed and of judgments for the landlord, from court records bought from data vendors, for the years the Lab judged complete for Denver County (tract counts come from the Lab's full tract file, limited to those years). Filing rate: filings per 100 renter households. Tract comparisons set filings against the share of rental units held by large owners today, so the two are years apart; weighted by renter households, with controls for race, ethnicity, poverty and historical sites.")))),
  nav_panel("Neighborhoods",
    layout_columns(col_widths = c(3, 9),
      card(card_header("Compare census tracts"), unit_note("2010 census tracts"),
           radioButtons("cmp", NULL, c(
             "Tracts with historical hazardous sites vs. tracts without" = "any",
             "Tracts with potentially unknown sites vs. all other tracts" = "unknown",
             "Tracts with potentially unknown sites vs. tracts with only known sites" = "unk_known",
             "Tracts with TRI facilities vs. tracts without" = "tri")),
           selectInput("nvar", "Indicator", VARS, selected = "low_income"),
           radioButtons("ptype", "Plot", c("Distribution (density)" = "dens", "Box plot" = "box"), inline = TRUE),
           checkboxInput("popw", "Weight by tract population", FALSE),
           tags$small(class = "text-muted",
             textOutput("nb_nsel", inline = TRUE), " A tract 'has' a site if the site's geocode falls inside it. ",
             "Tract-level comparisons describe places, not the people living next to a given site (ecological fallacy).")),
      card(card_header(textOutput("cmp_title")), plotlyOutput("p_cmp", height = 380),
           card_header("All indicators: medians, means and Wilcoxon rank-sum test"), unit_note("2010 census tracts"), DTOutput("t_cmp")))),
  nav_panel("Nearby schools & health care",
    layout_columns(col_widths = c(3, 9),
      card(card_header("Sensitive places near potentially unknown sites"), unit_note("schools and health facilities (points) within the chosen distance of sites"),
           sliderInput("buf", "Distance (m)", 100, 2000, 500, step = 100),
           checkboxGroupInput("recv", "Include", c("Public school", "Non-public school", "Hospital", "Clinic", "Residential & long-term care"),
                              selected = c("Public school", "Non-public school", "Hospital", "Clinic", "Residential & long-term care")),
           tags$small(class = "text-muted", textOutput("rv_nsel", inline = TRUE)),
           hr(), tableOutput("recv_sum")),
      card(DTOutput("t_recv")))),
  ),
  nav_menu("Methods & downloads",
  nav_panel("Benchmarks",
    layout_columns(col_widths = c(3, 9),
      card(card_header("The directories against the national series"),
           tags$small("No public national dataset locates individual factories: the Census Bureau's Longitudinal Business Database (1976+) does, but only inside a Federal Statistical Research Data Center, and County Business Patterns, the Census of Manufactures and the NHGIS tables publish totals for counties or states. ",
             "This tab checks the directories' coverage against those totals, county by county, and shows what the 1870–1880 establishment samples add. The sidebar filters do not apply here."),
           hr(), selectInput("bm_year", "County comparison: edition", if (is.null(bm_cty)) NULL else sort(unique(bm_cty$year), decreasing = TRUE), selected = if (!is.null(bm_cty) && 1990 %in% bm_cty$year) 1990 else NULL), checkboxInput("bm_haz", "Hazardous sectors only", FALSE),
           tags$small(class = "text-muted", "CBP: Eckert, Fort, Schott & Yang (2021) raw county files (1975–85 National Archives, 1986+ Census Bureau). NHGIS: county manufacturing tables 1880–1940 (IPUMS NHGIS). Atack–Bateman–Weiss: Census of Manufactures samples 1870, 1880 (Vanderbilt / ICPSR). Rscript R/benchmarks.R reproduces this tab.")),
      div(
        layout_columns(col_widths = c(6, 6),
          card(card_header("1977–1992: manufacturing establishments in Colorado — County Business Patterns vs the complete editions of the Directory of Colorado Manufacturers"), unit_note("Colorado counties (state totals)"), plotlyOutput("p_bm_state", height = 360),
               tags$small(class = "text-muted", "CBP counts every establishment with a payroll (SIC 20–39 to 1997, NAICS 31–33 from 1998), from administrative records; the directory lists firms that answered the publisher's questionnaire. The ratio is the directory's coverage rate; it varies by edition mainly with how much of each volume was scanned (see the table), which is why edition-to-edition changes in site counts on the Trends tab should be read against this chart.")),
          card(card_header("County agreement"), unit_note("Colorado counties"), tableOutput("t_bm_fit"), uiOutput("bm_fit_note"))),
        layout_columns(col_widths = c(7, 5),
          card(card_header("Counties in the chosen edition: directory vs CBP"), unit_note("Colorado counties"), plotlyOutput("p_bm_cty", height = 380), tableOutput("t_bm_cty")),
          card(card_header("1880–1940: census manufacturing establishments by county vs the business directory's hazardous trades"), unit_note("Colorado counties on each census's boundaries"), uiOutput("bm_nh"),
               tags$b("1880 Census of Manufactures sample (Atack–Bateman–Weiss): Colorado establishments by industry (* = Frickel & Elliott sector)"), tableOutput("t_bm_at"),
               tags$small(class = "text-muted", "The business directory lists only the hazardous trades, so its count is a floor on coverage of all manufacturing. NHGIS county tables derive from the Census of Manufactures as tabulated with each decennial census (variables differ by year). ",
                 "The Atack–Bateman–Weiss samples (1870, 1880) give establishment records (county, industry, capital, workers, output) from surviving schedules, without street addresses; if Colorado rows were found they are in data/results/benchmarks/atack_colorado.csv."))))
    )),
  nav_panel("About the data",
    layout_columns(col_widths = c(6, 6),
      card(card_header("Historical layers (built for this project)"),
        tags$dl(
          tags$dt("Inventory scope (October 2026)"),
          tags$dd(tags$b("The 1961\u20132002 directory series is used through its 13 complete editions only: 1965, 1966, 1967, 1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990 and 1992. "),
                  "Twelve editions (1961, 1962, 1971, 1976, 1979, 1982, 1984, 1985, 1986, 1993, 1999, 2002) reached the project as partial scans that stop part-way through the geographic section, so they are set aside until CU Boulder Libraries supplies the missing pages: ",
                  "sites, firm histories, corridors, the census panels, the redlining comparisons, the site-fate parcel matches and the health models are all built from the complete editions (config/editions.json; the full-inventory files are kept in data/full_inventory/). ",
                  "Where an analysis needs 'firms of the decade' for 2000, 2010 or 2020 it uses the last complete decade, 1983\u20131992. The Data & downloads tab lists what every edition contains."),
          tags$dt("Historical hazardous sites, 1965\u20131992 (complete editions)"),
          tags$dd("Every manufacturer listed in the Colorado Directory of Manufacturers (25 editions, CU Boulder Libraries scans, OCR'd with Tesseract) ",
                  "whose industry code falls in Frickel & Elliott's hazardous sectors: SIC 28 chemicals, 29 petroleum, 30 rubber & plastics, 33 primary metals, ",
                  "34 fabricated metals, 35 industrial machinery, 37 transportation equipment. Addresses are geocoded offline on US Census TIGER/Line 2023 address ranges; ",
                  "listings within 30 m form one site. 'Extended sectors' adds wood preserving, tanning, electronics & circuit boards, batteries, photographic chemicals and ore milling."),
          tags$dt("Current regulatory status"),
          tags$dd("Each site is compared with EPA's Facility Registry Service (all programs: RCRA, air, water, Superfund, brownfields, TRI\u2026), EPA TRI, and the CDPHE layers below. ",
                  "A site is 'known' when a record lies within 75 m (cleanup programs), 100 m (TRI) or 40 m (RCRA handlers, other permits), shares the firm's name within 250 m, ",
                  "has the same address, or lies inside a cleanup-site boundary. 'Not on any list' means not on the searched EPA and CDPHE HMWMD lists (FRS, TRI, SEMS/Superfund, RCRA, CDPHE cleanup, VCUP, brownfields, covenants); ",
                  "state petroleum-tank and release registers are shown separately on the Contamination & health tab. It is a lead for records review or soil testing, not evidence of contamination. ",
                  "The match_basis column of the site downloads says what a match rests on: the same entity (the hazardous firm's name or the site's address on an inventory record), a point inside a cleanup boundary, or a nearby record only (a differently named record within the radius, which may belong to another occupant of the block)."),
          tags$dt("Pre-1960 hazardous trades, 1871\u20131956"),
          tags$dd("Smelters, foundries, iron works, machine and boiler shops, tinners, chemical, paint, soap, powder and fertilizer works, refineries, rubber works, carriage and wagon shops, ",
                  "assay offices, ore mills, gas works, tanneries, tie-treating plants and coke ovens found in the text of 34 editions of the Colorado State Business Directory ",
                  "(CU Boulder Libraries). Placed at a street address only where today's numbering applies (Denver from 1891, larger cities from 1910); otherwise at the town centre."),
          tags$dt("Radium & uranium firms"),
          tags$dd("Firms in either directory whose name or products mention radium, uranium, vanadium or carnotite, or carry SIC 1094: Colorado's radium refiners and 'radium water' spas of the 1910s\u201320s, ",
                  "and later uranium and vanadium mills. Detection-instrument makers are excluded. Most are placed at the town only."),
          tags$dt("Firms at this address (popups)"),
          tags$dd("All manufacturers the directories list at the site, linked across editions: what the directory says they made, year established and employment class, as printed (uncorrected OCR)."),
          tags$dt("Industrial corridors (500 m cells)"),
          tags$dd("Every 500 m grid cell (UTM 13N) with a street-level-geocoded manufacturer in the complete editions 1965\u20131992, classed by how long industry stayed: persistent (first listed by 1968, still listed in 1990 or later, with a firm in at least 60% of the editions in between), ",
                  "persistent with sector turnover (dominant 2-digit SIC sector changed, three or more sectors led the cell), emerging (first listed 1980 or later), former (last listed 1980 or earlier) and intermittent (the rest). Popups give first and last edition, peak number of firms, ",
                  "first and last dominant sector and any street-level pre-1960 hazardous trade in the cell. Clustering (Ellison\u2013Glaeser) and succession statistics are on the Trends tab; Rscript R/corridors.R reproduces them."),
          tags$dt("Census tracts 1940\u20132020 (Denver 1880\u20132020 tab)"),
          tags$dd("Decennial census tract tables from IPUMS NHGIS (Manson et al., University of Minnesota), fetched through the NHGIS API (Rscript R/fetch_census.R): total population, Black (the 1940 tract table reports nonwhite, which is used as the 1940 value and labelled so in the downloads), ",
                  "Hispanic (Spanish surname 1960, Spanish American 1970, Spanish origin 1980, Hispanic 1990+), foreign born and persons below the poverty line (1970+). ",
                  "Values are NHGIS census tables on 2010 tract boundaries: population, race and Hispanic origin for 1990\u20132020 from NHGIS's standardised time series; everything else (all 1940\u20131980 tables; 1990\u20132020 nativity, poverty and housing) area-weighted from each census's own tracts. Shares are computed after interpolation, foreign born and poverty over the universe of their own table; tract-years with fewer than 200 residents are left blank. ",
                  "Firm counts per tract come from this project's geocoded directories. The 147 study tracts (2010 boundaries, centroid within 10 km of downtown) are shown; the panel models use the 147 tracts whose centroid lies within 10 km of downtown."),
          tags$dt("Denver enumeration districts 1880\u20131940 (reconstructed; Denver 1880\u20132020 tab)"),
          tags$dd("No public source has boundaries for the enumeration districts (EDs) of 1900\u20131940 (Brown's Urban Transition project drew 1880's, and 1880 is rebuilt here from its geocoded buildings so that all six censuses are constructed the same way); IPUMS gives every person's ED number but no addresses. Brown University's Geographic Reference Files (GRF) ",
                  "for Denver list every person of the 1900\u20131940 censuses with the household's street, house number and ED (no coordinates). The districts here are reconstructed from them: ",
                  "(1) every distinct address is geocoded with this project's offline TIGER/Line geocoder (Denver's modern numbering dates from 1887; a few renamed streets such as Holladay \u2192 Market are translated), ",
                  "keeping street-level results only; (2) stray geocodes are dropped \u2014 farther from the district's person-weighted median centre than max(400 m, 2.5\u00d7 the median) or with fewer than 30% of their ten nearest neighbours in the same district; ",
                  "(3) a Voronoi tessellation of the remaining addresses is dissolved by district and clipped to the concave hull of all addresses, each district keeps its main body and freed ground goes to the nearest district, so the districts are space-filling like tracts; ",
                  "(4) the IPUMS full-count totals are attached by district number. 1880 is tessellated the same way from Brown's geocoded 1880 buildings. 72% of the 1900 addresses geocode at street level, and the addresses kept after the stray check hold 60% of the 1900 population; the geocoding log is in data/results/denver_eds/ed_geocoding_R.csv. ",
                  "Boundaries are therefore approximate (a block or so at the edges) and are this project's derived product; the address files stay with the project under Brown's conditions of use. ",
                  "Reproduce with Rscript R/grf_eds.R (or python pipeline/historical/grf_eds.py) and Rscript R/denver_eds_analysis.R."),
          tags$dt("How units are harmonised over time"),
          tags$dd("Three kinds of unit appear, each handled differently. (1) Census tracts 1940\u20132020 are all expressed on 2010 tract boundaries: population, race and Hispanic origin for 1990\u20132020 from NHGIS's standardised time series (counts re-allocated by block-level weights); ",
                  "everything else \u2014 all 1940\u20131980 tables, and the 1990, 2000 and 2020 nativity, poverty and housing tables \u2014 by this project's area-weighted interpolation (each old tract's counts split among the 2010 tracts it overlaps in proportion to area); the 2008\u201312 ACS is already on 2010 tracts. Shares are computed from the re-allocated counts, with foreign born and poverty divided by the universe of their own table (so numerator and denominator are interpolated the same way). Medians (value, rent) are averaged over the source tracts weighted by occupied units and overlap. The tracted area grows (Denver alone in 1940\u201350), so series that compare years are also shown on a fixed set of tracts. ",
                  "Area weighting assumes people are spread evenly within an old tract, so values are approximate where an old tract straddled very different neighbourhoods. (2) Counties 1880\u20131940 are shown on each census's own boundaries and are not harmonised ",
                  "(counties were created and split through 1913), so compare the labelled county, not the shape. (3) Enumeration districts 1880\u20131940 are each census's own districts (reconstructed as described above) and are not linked across censuses; ",
                  "where they are compared with HOLC areas or 2010 tracts, their counts are area-weighted onto those units in the same way as the tracts."),
          tags$dt("HOLC 1938 redlining map (Redlining & covenants tab)"),
          tags$dd("The Home Owners' Loan Corporation's Residential Security Map of Denver (1938) and the appraisers' area-description forms, from Mapping Inequality (Nelson, Winling et al., University of Richmond Digital Scholarship Lab; spatial data CC-BY-NC), ",
                  "with their crosswalk of HOLC areas to 2010 census tracts. HOLC graded only residential neighbourhoods, A ('best') to D ('hazardous'); areas it judged non-residential were outlined but not graded and labelled Industrial or Commercial - Denver has 16 such zones, drawn in grey and lilac on the map, holding 16% of HOLC's land area and 15% of the 1940 population but 78% of the pre-map hazardous trades (the Industrial zone alone: 12% of the land, 6% of the population). The tab reads the grades against the reconstructed 1930 and 1940 districts (area-weighted), the firms of 1921\u201340 and the 1940\u20132020 tract panel. Rscript R/holc_covenants.R."),
          tags$dt("Denver 1925 zoning ordinance (Map and Redlining tabs)"),
          tags$dd("Building Zone Map, City and County of Denver, as adopted by the City Council February 1925, revised to January 1, 1929 (Denver Public Library Western History Collection, CG4314 .D4 G44 1929; the 1944 revision is CG4314 .G44 1944). ",
                  "The scan is a monochrome hatched map; a texture classifier labelled 32-pixel cells by hatch pattern as Industrial A, Industrial B or Commercial districts (residence and business districts are not drawn), and R/zoning_1925.R georeferenced it from 13 street intersections and park corners resolved to TIGER road intersections (affine fit, RMSE 25 m). ",
                  "Residence E (apartment) districts share a hatch with Industrial A and are separated only by lot lines, so some platted blocks near the Platte and the unplatted land north-east of the 1929 city are the least certain cells. The share of each HOLC area, district and tract zoned industrial enters the Redlining tab's boundary gaps and change models as a control."),
          tags$dt("What became of the sites (City and County of Denver assessor parcels)"),
          tags$dd("Denver open-data parcel feature service (ODC_PROP_PARCELS_A): assessor property class, zone district, dwelling units and original year built, queried for the nearest parcel within 40 m of every geocoded Denver site (R/site_fate.R; downloads of October 2026). ",
                  "Built from the complete directory editions only. A match identifies the parcel at the geocoded address today, not necessarily the historical lot; absence from the cleanup inventories this project searched is not evidence that a site was never assessed or remediated."),
          tags$dt("Racial covenants 1931\u20131935"),
          tags$dd("Mapping Prejudice: Denver (Denver Public Library Special Collections, pilot project; public domain, data.colorado.gov): 764 deeds recorded 1931\u201335 with racially restrictive language, placed at the parcel (730 with a location). The deed text is searched for clauses that also bar business or manufacturing use."),
          tags$dt("Colorado counties 1880\u20131940 (Colorado trends tab)"),
          tags$dd("The IPUMS full count aggregated to counties on each census's own county boundaries (NHGIS), with the pre-1960 hazardous trades of the preceding decade assigned to counties by location (town centre where no street is known). Rscript R/county_panel_1880_1940.R."),
          tags$dt("Denver 1880 at the building level (Brown University Urban Transition HGIS)"),
          tags$dd("Brown's Spatial Structures in the Social Sciences project geocoded the complete 1880 census of 39 cities to buildings and drew the enumeration districts and 1880 street grid ",
                  "(Logan et al.; s4.ad.brown.edu/Projects/UTP2). The hazardous trades of the 1878\u20131885 Colorado State Business Directories were placed on that 1880 grid by their printed house numbers, ",
                  "and residents' distance to the nearest firm computed at the building. The app shows only enumeration-district aggregates, firm points and model results; the person- and building-level files ",
                  "stay with the project under Brown's conditions of use (no redistribution). Rscript R/denver_1880.R reproduces the analysis from Brown's downloads."),
          tags$dt("Denver 1950\u20132020 by census tract (Denver 1880\u20132020 tab)"),
          tags$dd("The district analyses carried forward on the 147 2010 tracts within 10 km of downtown (earlier censuses interpolated; see Census tracts 1940–2020 below; tract-years under 200 residents dropped; robustness on fixed sets of tracts and with distance to downtown controlled): firms of the decade from the business directory (1941-60) and the manufacturers' directory (1961-1992 complete editions; 2000, 2010 and 2020 use the last complete decade, 1983-1992, i.e. proximity to historically listed sites), ",
                  "distance from each tract centroid to the nearest one, population-weighted regressions on log distance, tracts with vs without a firm, and firm shares by population quartile. Measures are the tract tables' (race, Hispanic origin from 1960, nativity, poverty from 1970, tenure, value, rent). Rscript R/denver_tracts_1950_2020.R."),
          tags$dt("Denver 1880\u20131940 (IPUMS USA full count)"),
          tags$dd("The complete-count census microdata for 1880, 1900, 1910, 1920, 1930 and 1940 (Ruggles et al., IPUMS USA), Colorado only, aggregated to enumeration districts (Rscript R/fetch_ipums_fullcount.R): ",
                  "population, Black, foreign born by region, Hispanic (IPUMS HISPAN, which for these censuses IPUMS infers from birthplace, parents' birthplace and Spanish surname; not the self-reported measure of later tract tables) and laborers (OCC1950 970\u2013979). Questions a census did not ask (or asked only on the 1940 sample line) are missing, not zero. ",
                  "The app shows city totals and dissimilarity indices across districts; no microdata leave the project."))),
      card(card_header("Context layers (public sources, downloaded 16 October 2026)"),
        tags$dl(
          tags$dt("EPA TRI facilities"),
          tags$dd("Facilities that report releases of listed toxic chemicals under the Toxics Release Inventory (EPA Envirofacts, tri_facility table, Colorado). Active and former reporters."),
          tags$dt("Brownfields"),
          tags$dd("Properties whose reuse is complicated by known or suspected contamination: EPA's brownfield program records (via the Facility Registry Service) and CDPHE's Brownfields layer."),
          tags$dt("Voluntary cleanup (VCUP)"),
          tags$dd("Sites that entered Colorado's Voluntary Cleanup and Redevelopment Program, in which an owner cleans up contamination under a CDPHE-approved plan, usually to redevelop the property."),
          tags$dt("Superfund (SEMS)"),
          tags$dd("Sites in EPA's Superfund Enterprise Management System (National Priorities List and sites assessed for it), plus CDPHE's Superfund, federal-facility and UMTRA (uranium mill tailings) layers."),
          tags$dt("RCRA corrective action"),
          tags$dd("Hazardous-waste treatment, storage and disposal facilities required to investigate and clean up releases under the Resource Conservation and Recovery Act (CDPHE layer)."),
          tags$dt("Environmental covenants / land-use controls"),
          tags$dd(tags$b("What they are: "), "legal restrictions recorded on a property's deed because contamination was left in place after a cleanup. ",
                  "A covenant may forbid residential use, prohibit drinking-water wells, require a vapor barrier under new buildings, or bar digging below a certain depth. ",
                  "They are the clearest public record that a specific parcel still holds contamination that is being managed rather than removed. ",
                  "Source: CDPHE Hazardous Materials & Waste Management Division, Institutional Controls layer (environmental covenants, use restrictions and notices of environmental use restrictions)."),
          tags$dt("Schools, hospitals, clinics, residential care"),
          tags$dd("Colorado Department of Education school locations (public and non-public) and CDPHE licensed health facilities, both via geodata.colorado.gov."),
          tags$dt("Denver zoning today"),
          tags$dd("City and County of Denver official zoning map (open data, CCD_Zoning layer 27; downloaded with Rscript R/fetch_zoning_city.R): every zone district, the code it falls under (2010 Denver Zoning Code, or the 1956 code where land was never remapped) and the year of the ordinance that last zoned it. Analysed with the 1929, 1944, 1955 and 2023 maps in Rscript R/zoning_over_time.R."),
          tags$dt("Denver zoning, 1955"),
          tags$dd("Zone map, City and County of Denver, prepared by the Department of Zoning Administration, July 1, 1955 (History Colorado, Stephen H. Hart Research Center, rG4314 .D4G44 1955 .D4). Credit: History Colorado-Denver, Colorado. The scan is used under licence and is not distributed with this site; its industrial districts (I-1 and I-2; the map shows no I-0 land) were classified by texture (pipeline/zoning/classify_zoning_1955.py; 58 of 60 randomly checked cells correct) and placed from 23 street intersections (second-order fit, about 13 m RMSE; Rscript R/zoning_1955.R)."),
          tags$dt("Zoning today (2023)"),
          tags$dd("Denver-metro zoning layer of 3 October 2023 (51 jurisdictions), compiled by Carrie Makarewicz (University of Colorado Denver) for the National Zoning Atlas: local district codes with harmonised categories. ",
                  "It is shown on the site's maps, grouped into six categories, with the author's permission, but it is not offered for download here: to obtain the layer, use the request form on the project's StoryMap, ", tags$a(href = "https://storymaps.arcgis.com/stories/adb86c7ab2624e95a84566fecb8a6f6d", target = "_blank", "Denver-metro zoning (National Zoning Atlas)"), ". Summaries: Rscript R/zoning_2023.R."),
          tags$dt("Census tracts: EnviroScreen"),
          tags$dd("CDPHE Colorado EnviroScreen 2.0: environmental, health and social indicators for 2020 census tracts, with percentile scores. Health indicators come from CDPHE administrative data or modelled estimates (see the tool's documentation)."),
          tags$dt("Base maps and address ranges"),
          tags$dd("Esri light grey canvas, OpenStreetMap and Esri world imagery tiles; US Census Bureau TIGER/Line 2023 ADDRFEAT for geocoding. ",
                  "All the CDPHE and EPA inventories are live services that change over time; the app shows a snapshot. Code and data: github.com/pdez90/Colorado_hiddenhazards.")))
    )),
  nav_panel("Data & downloads",
    layout_columns(col_widths = c(4, 8),
      card(card_header("Geocoded directory listings by edition"), unit_note("individual listings (points), statewide"),
           selectInput("dl_year", "Edition", { dcm <- sort(as.integer(sub("CO_DCM_(\\d+)_geocoded.csv", "\\1", list.files(by_year_dir, "CO_DCM_.*csv")))); bd <- if (is.null(pre60)) integer() else sort(unique(pre60$year))
             lab <- function(v, txt) if (length(v)) setNames(as.list(v), paste(v, txt)) else list()     # empty when a set of files is not deployed
             ch <- c(lab(bd, "(State Business Directory: hazardous trades)"), lab(dcm, "(Directory of Colorado Manufacturers)")); if (!length(ch)) ch <- list(`No edition files deployed` = "")
             ch }, selected = 1965),
           downloadButton("dl_one", "Download edition CSV"),
           tags$small(class = "text-muted d-block mt-1 mb-3", "1871-1956 files hold the hazardous-trade listings extracted from that edition of the Colorado State Business Directory (volume, page, town, trade, sector, placement precision, coordinates, linked firm id). 1965-1992 files (complete editions only) hold every manufacturer listed in that edition with its codes and geocode."), br(),
           uiOutput("dl_btns"),
           downloadButton("dl_hist", "Download pre-1960 hazardous-trade firms (1871–1956)"), br(), br(),
           downloadButton("dl_cells", "Download industrial corridor cells (500 m)"),
           tags$hr(), tags$b("Zoning, redlining and site-fate files"), br(),
           tags$small(class = "text-muted d-block mt-1 mb-2", "Denver's 1925 zoning ordinance as mapped in January 1929 (industrial and commercial districts, georeferenced from the Denver Public Library scan; see Redlining & covenants), the share of every HOLC area and 2010 tract zoned industrial and commercial, the HOLC boundary gaps and change models with their rail and zoning adjustments, and what stands today on each Denver site."),
           uiOutput("dl_zoning_btns"),
           tags$small(class = "text-muted d-block mt-1 mb-3", tags$b("How corridor cells are defined. "),
             "Every geocoded manufacturer in the complete editions (1965–1992) of the Directory of Colorado Manufacturers (street-level geocodes only) is snapped to a 500 m × 500 m grid cell (UTM zone 13N), ",
             "and every cell with at least one manufacturer in any edition is kept (3,333 cells). For each cell the script counts establishments per edition, finds the dominant 2-digit SIC sector, ",
             "and computes coverage = editions with a firm ÷ editions between the cell's first and last listing. Classes: ", tags$i("persistent"), " = first listed 1968 or earlier, still listed 1990 or later, coverage ≥ 60%; ",
             tags$i("persistent, sector turnover"), " = persistent, but the dominant sector changed and three or more sectors led it over time; ", tags$i("emerging"), " = first listed 1980 or later; ",
             tags$i("former"), " = last listed 1980 or earlier; everything else ", tags$i("intermittent"), ". Each cell also records any street-level pre-1960 hazardous trade inside it. ",
             "Clustering (Ellison–Glaeser) uses 1 km cells. Code: R/corridors.R."),
           downloadButton("dl_1880", "Download Denver 1880–1940 enumeration districts (reconstructed) & firms"),
           tags$small(class = "text-muted d-block mt-1 mb-3", tags$b("How the enumeration districts were constructed. "),
             "No public source maps the census enumeration districts (EDs) of 1900–1940 (1880's exist from Brown's Urban Transition project), and the IPUMS full count gives each person's ED number but no address. ",
             "Brown University's Geographic Reference Files list every Denver resident of 1900–1940 with street, house number and ED (no coordinates). From these: ",
             "(1) every distinct address is geocoded offline against TIGER/Line address ranges (Denver's modern numbering dates from 1887; renamed streets such as Holladay → Market are translated), keeping street-level results only; ",
             "(2) stray geocodes are dropped — those farther from their district's person-weighted median centre than max(400 m, 2.5 × the median distance), or with fewer than 30% of their ten nearest neighbours in the same district; ",
             "(3) a Voronoi tessellation of the remaining addresses is dissolved by district, clipped to the concave hull of all addresses (ratio 0.25, buffered 120 m), each district keeps its main body (parts at least 25% of its largest piece) and freed ground goes to the nearest district, so districts are space-filling like tracts; ",
             "(4) IPUMS full-count totals (population, race, nativity, Hispanic origin, occupation, housing, 1935 residence) are attached by district number. ",
             "1880 is tessellated the same way from Brown's geocoded 1880 buildings. About 72% of the 1900 addresses geocode at street level, and the addresses kept hold 60% of the 1900 population (data/results/denver_eds/ed_geocoding_R.csv); boundaries are approximate by a block or so at the edges. ",
             "The address files stay with the project under Brown's conditions of use; only these derived polygons and aggregates are published. Code: R/grf_eds.R (cross-checked with pipeline/historical/grf_eds.py) and R/denver_eds_analysis.R."),
           hr(), tags$small("Each edition file lists every manufacturer with its OCR'd name and address, SIC/NAICS codes, ",
                            "sector flags, establishment and site IDs, coordinates and geocode level.")),
      card(card_header("Editions used: what each contains and how complete our copy is"),
           tags$small(class = "text-muted", tags$b("Before 1960: Colorado State Business Directory, 1871\u20131956. "), "34 editions (1871 Rocky Mountain Directory; 1875, 1877\u20131885, 1887\u201388, 1891\u201392, 1910\u20131917, 1920, 1927, 1929, 1932\u201333, 1935, 1939, 1941, 1943, 1950, 1956), ",
             "read from the full-volume scans in CU Boulder Libraries' digital collection. These are general business directories, not manufacturers' directories: every trade in every town is listed, so the pipeline keeps only the hazardous trades (smelters, reduction and sampling works, foundries, machine and boiler shops, chemical, paint, soap, powder and fertilizer works, refineries, tanneries, gas works and the like) by keyword, ",
             "places them at a street address only where modern numbering applies (Denver from 1891, larger cities from 1910) and otherwise at the town, and links firms across editions by name. The 'Download pre-1960 hazardous-trade firms' file above is that extraction. ",
             tags$b("1961\u20132002: Directory of Colorado Manufacturers "), "(Business Research Division, CU Boulder), every listed manufacturer with its industry code, from page scans of the geographic section. Twelve of the 25 editions reached us as partial scans (the scan stops part-way through the alphabetical run of counties or cities); the table gives pages, listings and what is missing, and the Trends tab can be limited to the 13 complete editions."),
           DT::dataTableOutput("t_edcov")),
      card(card_header("How reliable are the locations?"), uiOutput("geo_note"), tableOutput("valid"))))
  )
)

# ---------------------------------------------------------------- server
server <- function(input, output, session) {

  sel_sites <- reactive({
    sy <- site_yr |> filter(year >= input$yrs[1], year <= input$yrs[2])
    if (length(input$sec)) {
      pat <- paste(gsub("([&+()])", "\\\\\\1", input$sec), collapse = "|")
      sy <- sy |> filter(grepl(pat, sectors))
    } else sy <- sy[0, ]
    ids <- unique(sy$site_id)
    sites |> filter(site_id %in% ids, radar %in% input$st, confidence %in% input$cf, span_years >= input$minspan) |>
      left_join(sy |> group_by(site_id) |> summarise(years_in_range = paste(sort(unique(year)), collapse = ", ")), by = "site_id")
  })
  output$nb_nsel <- renderText(sprintf("Tract groups use the %s sites currently selected in the sidebar (years, sectors, status).", format(nrow(sel_sites()), big.mark = ",")))
  output$rv_nsel <- renderText({ s <- sel_sites(); sprintf("Uses the %s sites with status 'Not on any list' among the %s selected in the sidebar (years, sectors).", format(sum(s$radar == "Not on any list"), big.mark = ","), format(nrow(s), big.mark = ",")) })
  output$nsites <- renderText({ s <- sel_sites()
    h <- sel_hist()
    paste0(sprintf("%s sites, %s on no current inventory", format(nrow(s), big.mark = ","), format(sum(s$radar == "Not on any list"), big.mark = ",")),
           if (!is.null(h)) sprintf("; plus %s pre-1960 hazardous-trade firms (%s at a street address, %s still listed after 1960)",
                                    format(nrow(h), big.mark = ","), sum(h$precision != "town"), sum(h$persists_to_1961plus)) else "") })

  # ---- map
  pal_for <- function(v) { x <- tracts[[v]]
    colorNumeric("YlOrRd", domain = range(x, na.rm = TRUE), na.color = "#00000000") }
  output$map <- renderLeaflet({
    m <- leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", options = tileOptions(maxNativeZoom = 16),
               attribution = "Tiles &copy; Esri &mdash; Esri, HERE, Garmin, &copy; OpenStreetMap contributors", group = "Light grey") |>
      addTiles("https://tile.openstreetmap.org/{z}/{x}/{y}.png",
               attribution = "&copy; OpenStreetMap contributors", group = "OpenStreetMap") |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
               attribution = "Tiles &copy; Esri &mdash; Source: Esri, Maxar, Earthstar Geographics", group = "Satellite") |>
      setView(-104.97, 39.74, 11) |>
      addMapPane("sbimg", zIndex = 415) |> addMapPane("tr", zIndex = 380) |> addMapPane("ctx", zIndex = 430) |> addMapPane("haz", zIndex = 460)
    tri_pop <- sprintf("<b>%s</b><br>%s, %s<br>EPA TRI facility (%s)", esc(tri$name), esc(tri$address), esc(tri$city), esc(tri$status))
    m <- m |> addCircleMarkers(data = tri, ~lon, ~lat, radius = 4, color = "#5b2a86", weight = 1.5, fillColor = "#b58bd9", fillOpacity = 0.9,
                               popup = tri_pop, group = "EPA TRI facilities", options = pathOptions(pane = "ctx"))
    for (k in CLEAN_LAYERS) { d <- cleanup[cleanup$layer == k, ]
      m <- m |> addCircleMarkers(data = d, ~lon, ~lat, radius = 4, color = CLEAN_COL[[k]], weight = 1, fillOpacity = 0.75,
            popup = sprintf("<b>%s</b><br>%s %s<br>%s%s<br><i>%s</i>", esc(d$name), esc(d$address), esc(d$city), k,
                            if (k == "Environmental covenants / land-use controls") "<br><small>A deed restriction recorded because contamination was left in place after cleanup (e.g. no residential use, no wells, vapor barrier required).</small>" else "",
                            esc(d$source)),
            label = if (k == "Environmental covenants / land-use controls") "Deed restriction: contamination left in place (see About the data)" else NULL,
            group = k, options = pathOptions(pane = "ctx")) }
    for (k in c("Public school", "Non-public school")) { d <- schools[schools$type == k, ]
      m <- m |> addCircleMarkers(data = d, ~lon, ~lat, radius = 3.5, color = "#1f6f3f", weight = 1, fillColor = if (k == "Public school") "#7fd19b" else "#ffffff",
            fillOpacity = 1, popup = sprintf("<b>%s</b><br>%s<br>Grades %s · %s", esc(d$name), esc(d$address), esc(d$grades), k),
            group = "Schools", options = pathOptions(pane = "ctx")) }
    hc <- c("Hospital" = "#c51b7d", "Clinic" = "#f1b6da", "Residential & long-term care" = "#8e0152")
    for (k in names(hc)) { d <- health[health$category == k, ]
      m <- m |> addCircleMarkers(data = d, ~lon, ~lat, radius = 3.5, color = "#7a0f4d", weight = 1, fillColor = hc[[k]], fillOpacity = 1,
            popup = sprintf("<b>%s</b><br>%s<br>%s", esc(d$name), esc(d$address), esc(d$type)),
            group = if (k == "Residential & long-term care") k else paste0(k, "s"), options = pathOptions(pane = "ctx")) }
    # industrial corridors: 500 m cells with any manufacturer 1965-1992 (complete editions), classed by persistence (R/corridors.R)
    if (!is.null(cells) && nrow(cells)) {
      cc <- cells[order(match(cells$class, rev(CELL_CLASSES))), ]
      m <- m |> addCircleMarkers(data = cc, ~lon, ~lat, radius = pmin(3 + 1.5 * sqrt(cc$max_n), 14), stroke = TRUE, weight = 0.6, color = "#333333",
        fillColor = unname(CELL_COL[cc$class]), fillOpacity = 0.75,
        popup = sprintf("<b>Industrial cell: %s</b><br>Manufacturers listed %s–%s in %s editions; up to %s firms at once%s<br>Dominant sector first %s, last %s (%s sectors over time)%s",
                        esc(cc$class), cc$first, cc$last, cc$editions, cc$max_n, ifelse(cc$ever_haz %in% TRUE, " · <b>hazardous sector present</b>", ""),
                        esc(cc$first_sector), esc(cc$last_sector), cc$n_sectors,
                        ifelse(is.na(cc$pre1960_first), "", sprintf("<br>Pre-1960 hazardous trade here since %s (%s firms)", cc$pre1960_first, cc$pre1960_firms))),
        group = "Industrial corridors (500 m cells)", options = pathOptions(pane = "ctx")) |>
        addLegend("topleft", colors = unname(CELL_COL), labels = CELL_CLASSES, title = "Industrial corridors<br><small>500 m cells, 1965–1992; size = peak firms</small>",
                  opacity = 0.8, group = "Industrial corridors (500 m cells)")
    }
    m <- m |> addTiles(AERIAL_1933, attribution = AERIAL_ATTR, group = "Aerial photo 1933", options = tileOptions(maxNativeZoom = 19, opacity = 0.9))
    if (!is.null(pet)) m <- m |> addCircleMarkers(data = pet, ~lon, ~lat, radius = 3, color = "#7f2704", weight = 1, fillColor = ifelse(grepl("closed|nfa", tolower(pet$status)), "#fdae6b", "#d94801"),
        fillOpacity = 0.9, group = "Petroleum releases (1986\u2013)", options = pathOptions(pane = "ctx"),
        popup = sprintf("<b>Petroleum release %s</b><br>%s, %s<br>Reported %s · %s%s<br>Source: %s · cause: %s<br><small>Colorado Division of Oil &amp; Public Safety</small>",
                        esc(pet$release_number), esc(pet$site_name), esc(pet$address), esc(pet$release_year), esc(pet$status), ifelse(is.na(pet$closure_year), "", paste(" ", pet$closure_year)),
                        esc(pet$release_source), esc(pet$release_cause)))
    if (!is.null(ur_poly)) m <- m |> addPolygons(data = ur_poly, color = "#4a1486", weight = 2, fillColor = "#9e9ac8", fillOpacity = 0.25, dashArray = ifelse(ur_poly$boundary_confidence == "mapped boundary", NA, "4"),
        group = "Urban renewal projects", options = pathOptions(pane = "tr"),
        popup = sprintf("<b>%s</b> urban-renewal project (%s\u2013%s)<br>%s<br>Families in the project area: %s (white %s, non-white %s) · substandard dwellings: %s<br>Historical hazardous sites inside: %s pre-1960, %s 1965\u201392<br><small>Renewing Inequality, University of Richmond (federal reports, 1955\u20131966)</small>",
                        tools::toTitleCase(ur_poly$project), ur_poly$first_year, ur_poly$last_year, ur_poly$boundary_confidence, ifelse(is.na(ur_poly$total_families), "not reported", ur_poly$total_families),
                        ifelse(is.na(ur_poly$white_families), "\u2013", ur_poly$white_families), ifelse(is.na(ur_poly$nonwhite_families), "\u2013", ur_poly$nonwhite_families),
                        ifelse(is.na(ur_poly$substandard_dwellings), "\u2013", ur_poly$substandard_dwellings), ur_poly$historical_sites_inside, ur_poly$sites_1965_92_inside))
    if (!is.null(ou_poly)) m <- m |> addPolygons(data = ou_poly, color = "#b30000", weight = 2, fillColor = "#fc8d59", fillOpacity = 0.15, group = "Superfund operable units", options = pathOptions(pane = "tr"),
        popup = sprintf("<b>%s</b><br>%s<br><small>EPA Superfund operable unit</small>", esc(tools::toTitleCase(tolower(ou_poly$SITE_NAME))), esc(ou_poly$SITE_FEATURE_NAME)))
    if (!is.null(sb_poly)) for (k in seq_along(SB_EDS)) { d <- sb_poly[sb_poly$edition == SB_EDS[k], ]; if (!nrow(d)) next
      m <- m |> addPolygons(data = d, color = SB_COL[k], weight = 2, fillOpacity = 0.06, group = paste("Sanborn coverage", SB_EDS[k]), options = pathOptions(pane = "tr"),
        label = sprintf("Sanborn %s, volume %s", d$edition, d$volume),
        popup = sprintf("<b>Sanborn fire-insurance map, %s, volume %s</b> (%s)<br>%s<br><a href='%s' target='_blank'>Open</a> · <a href='https://LOC.maps.arcgis.com/apps/instant/interactivelegend/index.html?appid=5df8bc1f04d44edb8222b2ae777f3070' target='_blank'>LOC volume finder</a><br><small>Volume extents: Library of Congress, Geography &amp; Map Division</small>",
                        d$edition, d$volume, d$year, d$online, d$link)) }
    if (!is.null(sb03)) m <- m |> addPolygons(data = sb03, color = "#7f3b08", weight = 1.2, fillOpacity = 0.03, group = "Sanborn 1903\u201304 sheet images", options = pathOptions(pane = "tr"),
        label = sprintf("Sanborn 1903\u201304, vol. %s, sheet %s", sb03$volume, sb03$sheet),
        popup = sprintf("<b>Sanborn 1903\u201304, volume %s, sheet %s</b><br><a href='%s' target='_blank'><img src='%s' style='width:240px;max-width:100%%;border:1px solid #ccc'></a><br>%s dwellings \u00b7 %s industrial or workshop establishments recorded<br><small>%s</small><br><a href='%s' target='_blank'>Full-resolution sheet (Library of Congress)</a><br><small>Public domain. Sheet placed on today's map from %s.</small>",
                        sb03$volume, sb03$sheet, sb03$page, sb03$thumb, sb03$dwellings, sb03$industrial, esc(sb03$notes), sb03$page,
                        ifelse(sb03$n_inliers <= 2, "two street crossings and the atlas scale (a two-point fit, so its accuracy cannot be measured)", sprintf("%s street crossings (typical error \u00b1%s m)", sb03$n_inliers, sb03$rmse_m))))
    if (!is.null(bl03)) { e3 <- c("Same block as a hazardous trade" = "#b2182b", "Across the street from a hazardous trade" = "#d6604d", "Same block as other industry, or facing industry" = "#f4a582",
                                  "Within 150 m of a hazardous trade" = "#fddbc7", "No hazardous trade within 150 m" = "#4393c3", "No industry within 150 m" = "#4393c3")
      bpop <- sprintf("<b>1903 block</b> (sheet %s)<br>%s dwellings%s<br>%s<br>%s<br><small>1929 zoning: %s%s</small>", bl03$sheets, bl03$dwellings,
                      ifelse(bl03$n_industrial > 0, sprintf(" \u00b7 %s industrial (%s)", bl03$n_industrial, esc(bl03$trades)), ""), esc(bl03$establishments), bl03$exposure, bl03$zone_1929,
                      if ("poly_from" %in% names(bl03)) sprintf("<br>Outline: %s", bl03$poly_from) else "")
      m <- if (all(st_geometry_type(bl03) %in% c("POLYGON", "MULTIPOLYGON")))
        addPolygons(m, data = bl03, stroke = TRUE, color = "#333333", weight = 0.6, fillColor = unname(e3[bl03$exposure]), fillOpacity = ifelse(bl03$dwellings > 0, 0.7, 0.3),
                    group = "1903 blocks: housing & industry", options = pathOptions(pane = "ctx"), popup = bpop)
      else addCircleMarkers(m, data = bl03, radius = pmax(3, sqrt(bl03$dwellings) * 1.6), stroke = TRUE, color = "#333333", weight = 0.5,
                            fillColor = unname(e3[bl03$exposure]), fillOpacity = ifelse(bl03$dwellings > 0, 0.85, 0.35), group = "1903 blocks: housing & industry", options = pathOptions(pane = "ctx"), popup = bpop)
      if (!is.null(pl03)) m <- addPolygons(m, data = pl03, color = ifelse(pl03$hazardous, "#67001f", "#555555"), weight = 1.5, dashArray = "3", fillColor = ifelse(pl03$hazardous, "#67001f", "#999999"), fillOpacity = 0.35,
                                            group = "1903 blocks: housing & industry", options = pathOptions(pane = "ctx"),
                                            popup = sprintf("<b>%s</b><br>%s<br>Trade: %s<br><small>Drawn on unplatted ground (sheet %s, volume %s); outline as drawn on the sheet</small>", esc(ifelse(nzchar(pl03$name), pl03$name, pl03$label)), esc(pl03$label), esc(pl03$trade), pl03$sheet, pl03$volume)) }
    if (!is.null(rz)) { rzc <- ifelse(rz$annexation, "#1b7837", ifelse(grepl("^Residential to", rz$direction), "#b2182b", ifelse(rz$to_group %in% "Residential", "#2166ac", "#777777")))
      m <- m |> addCircleMarkers(data = rz, radius = 6, stroke = TRUE, color = "#222222", weight = 0.8, fillColor = rzc, fillOpacity = ifelse(grepl("^uncertain", rz$placed_by), 0.35, 0.85),
        group = "Zone changes 1925\u20131956", options = pathOptions(pane = "ctx"),
        popup = sprintf("<b>Ordinance %s, Series of %s</b><br>%s &rarr; %s<br><small>Placed by %s</small><br><a href='%s' target='_blank'>Ordinance text (Denver, Municode)</a>",
                        sub("^\\d{4}0*", "", rz$ordinance), rz$year, esc(rz$from), esc(rz$to), esc(rz$placed_by), rz$link)) }
    ZG <- paste("Zoning", names(ZYEARS)); for (k in seq_along(ZYEARS)) m <- add_zoning(m, ZYEARS[[k]], ZG[k], "tr", 0.45)
    LG <- paste("Land use", LU_YEARS); if (!is.null(lu_r)) for (k in seq_along(LU_YEARS)) m <- add_landuse(m, LU_YEARS[k], LG[k], 0.6)
    m |> addLayersControl(baseGroups = c("Light grey", "OpenStreetMap", "Satellite"),
          overlayGroups = c("Historical hazardous sites", "Pre-1960 hazardous trades", "Industrial corridors (500 m cells)", "Aerial photo 1933", paste("Sanborn coverage", SB_EDS), "Sanborn 1903\u201304 sheet images", "1903 blocks: housing & industry", "Zone changes 1925\u20131956", "Petroleum releases (1986\u2013)", "Urban renewal projects", "Superfund operable units", paste("Zoning", names(ZYEARS)), if (!is.null(lu_r)) paste("Land use", LU_YEARS), "EnviroScreen tracts", "EPA TRI facilities", "Schools", "Hospitals", "Clinics",
                            "Residential & long-term care", CLEAN_LAYERS),
          options = layersControlOptions(collapsed = FALSE)) |>
      hideGroup(c("Industrial corridors (500 m cells)", "Aerial photo 1933", paste("Sanborn coverage", SB_EDS), "Sanborn 1903\u201304 sheet images", "1903 blocks: housing & industry", "Zone changes 1925\u20131956", "Petroleum releases (1986\u2013)", "Urban renewal projects", "Superfund operable units", paste("Zoning", names(ZYEARS)), paste("Land use", LU_YEARS), "Schools", "Hospitals", "Clinics", "Residential & long-term care", "Environmental covenants / land-use controls",
                  "RCRA corrective action", "Voluntary cleanup (VCUP)", "Superfund (SEMS)")) |>
      sb03_images()
  })
  observe({
    v <- input$esvar; pal <- pal_for(v); lab <- names(VARS)[VARS == v]
    leafletProxy("map") |> clearGroup("EnviroScreen tracts") |> removeControl("eslegend") |>
      addPolygons(data = tracts, fillColor = pal(tracts[[v]]), fillOpacity = input$esop, color = "#ffffff", weight = 0.3,
                  group = "EnviroScreen tracts", options = pathOptions(pane = "tr"),
                  popup = sprintf("<b>Tract %s</b> (%s County)<br>%s: <b>%s</b><br>EnviroScreen percentile: %s<br>Low income: %s%%<br>People of color: %s%%<br>Population: %s",
                                  tracts$GEOID, esc(tracts$county), lab, round(tracts[[v]], 1), round(tracts$enviroscreen_pctl, 1),
                                  round(tracts$low_income, 1), round(tracts$people_of_color, 1), format(tracts$population, big.mark = ","))) |>
      addLegend("bottomright", pal = pal, values = tracts[[v]], title = lab, layerId = "eslegend", opacity = 0.8)
  })
  observe({
    s <- sel_sites()
    ft <- unname(firm_html[s$site_id]); ft <- ifelse(is.na(ft), gsub(" \\| ", "<br>", esc(s$hazard_firms)), ft)
    pop <- sprintf("<b>%s, %s</b><br><b>%s</b> · %s confidence<br>Hazardous use in %s editions, %s–%s (%s years)<br>Listed %s–%s (in range: %s)<br><b>Firms at this address</b> <small>(shaded = hazardous sector; download all in Data &amp; downloads)</small>:<br>%s<b>Sectors:</b> %s %s%s<br><b>Nearest inventory record:</b> %s<br><small>%s · %.5f, %.5f</small>",
                   esc(s$address), esc(s$city), if ("match_basis" %in% names(s)) paste0(esc(s$radar), " <small>(", esc(s$match_basis), ")</small>") else esc(s$radar), esc(s$confidence), s$n_editions, s$haz_first, s$haz_last, s$span_years,
                   s$first_year, s$last_year, esc(s$years_in_range),
                   ft, esc(s$fe_sectors), esc(s$ext_sectors),
                   ifelse(is.na(s$hist_first_year), "", sprintf("<br><b>Pre-1960 precursor (since %s):</b> %s", s$hist_first_year, esc(s$hist_names))),
                   ifelse(s$known_match == "" | is.na(s$known_match), "none", esc(s$known_match)), s$site_id, s$lat, s$lon)
    pop <- paste0(pop, ctx_html(s$site_id))
    if (input$colby == "span") {
      cls <- cut(s$span_years, SPAN_BREAKS, SPAN_LABELS)
      fill <- SPAN_COL[as.integer(cls)]; rad <- 3 + 1.2 * sqrt(s$n_editions)
      ring <- ifelse(s$radar == "Not on any list", "#d1491f", "#ffffff"); ringw <- ifelse(s$radar == "Not on any list", 1.6, 0.8)
      leg <- list(colors = SPAN_COL, labels = SPAN_LABELS, title = "Persistence of hazardous use<br><small>size = editions listed; orange ring = on no list</small>")
    } else {
      fill <- unname(STATUS_COL[s$radar]); rad <- ifelse(s$radar == "Not on any list", 5, 4); ring <- "#ffffff"; ringw <- 1
      leg <- list(colors = unname(STATUS_COL), labels = unname(STATUS_LAB[names(STATUS_COL)]), title = "Historical site status")
    }
    n <- nrow(s); rad <- rep_len(rad, n); ring <- rep_len(ring, n); ringw <- rep_len(ringw, n); fill <- rep_len(fill, n)
    o <- order(s$span_years)
    leafletProxy("map") |> clearGroup("Historical hazardous sites") |> removeControl("sitelegend") |>
      addCircleMarkers(lng = s$lon[o], lat = s$lat[o], radius = rad[o], stroke = TRUE, weight = ringw[o], color = ring[o],
                       fillColor = fill[o], fillOpacity = 0.9, popup = pop[o], group = "Historical hazardous sites",
                       popupOptions = popupOptions(maxWidth = 560, minWidth = 380),
                       options = pathOptions(pane = "haz")) |>
      addLegend("bottomleft", colors = leg$colors, labels = leg$labels, title = leg$title, opacity = 1, layerId = "sitelegend")
  })

  # ---- pre-1960 layer
  sel_hist <- reactive({
    if (is.null(hist)) return(NULL)
    h <- hist |> filter(last_year >= input$yrs[1], first_year <= input$yrs[2], (last_year - first_year) >= input$minspan)
    if (!isTRUE(input$htown)) h <- h |> filter(precision != "town")
    if (length(input$sec) && nrow(h)) h <- h[vapply(strsplit(h$app_sectors, ";"), function(x) any(x %in% input$sec), logical(1)), ] else h <- h[0, ]   # vapply: sapply returns list() on 0 rows and crashed the session
    h
  })
  # radium & uranium: Colorado's radium industry (1910s-20s), 'radium cure' waters and baths, and uranium/vanadium mills; a sidebar filter like the sectors
  observe({ req(input$map_zoom); px <- leafletProxy("map") |> clearGroup("Radium & uranium firms"); if (is.null(radium) || !isTRUE(input$radium)) return()
    rp <- radium[!is.na(radium$lat) & radium$last_year >= input$yrs[1] & radium$first_year <= input$yrs[2], ]; if (!nrow(rp)) return()
    px |> addCircleMarkers(data = rp, ~lon, ~lat, radius = ifelse(rp$precision == "street", 8, 6), color = "#000000", weight = 2.5,
        fillColor = "#ffd400", fillOpacity = ifelse(rp$precision == "street", 0.95, 0.6),
        popup = sprintf("<b>&#9762; %s</b><br>%s%s · listed %s<br>%s<br><i>Location: %s</i><br><small>Source: %s</small>",
                        esc(rp$name), ifelse(is.na(rp$street) | rp$street == "", "", paste0(esc(rp$street), ", ")), esc(rp$city), esc(rp$years),
                        esc(rp$what), ifelse(rp$precision == "street", "street address", "town only (no usable street address)"), esc(rp$source)),
        label = ~paste0("☢ ", name), group = "Radium & uranium firms", options = pathOptions(pane = "haz")) })
  observe({
    h <- sel_hist(); px <- leafletProxy("map") |> clearGroup("Pre-1960 hazardous trades") |> removeControl("histlegend")
    if (is.null(h) || !nrow(h)) return()
    pop <- function(d) sprintf("<b>%s</b><br>%s%s<br><b>%s</b> · listed %s<br><i>Location: %s</i>%s<br><small>“%s”</small>",
      esc(d$name), ifelse(d$street == "" | is.na(d$street), "", paste0(esc(d$street), ", ")), esc(d$town), esc(d$sectors), esc(d$years),
      ifelse(d$precision == "town", "town centre only (address not mapped)", d$precision),
      ifelse(d$persists_to_1961plus, sprintf("<br><b>Persisted:</b> %s in the 1965–1992 directory (%s; matched by %s)", esc(d$dcm_name), esc(d$dcm_years), esc(d$link)), ""),
      esc(d$example)) |> paste0(ctx_html(d$hfirm))
    ring <- function(d) ifelse(d$persists_to_1961plus, "#000000", "#ffffff")
    st <- h[h$precision != "town", ]; tw <- h[h$precision == "town", ]
    # firms known only to the town share one point: draw ONE marker per town whose popup lists every firm (scrollable)
    if (nrow(tw)) {
      tw <- tw[order(tw$town, tw$first_year, tw$name), ]
      row <- sprintf("<tr><td>%s%s</td><td>%s</td><td>%s</td></tr>", esc(tw$name), ifelse(tw$persists_to_1961plus, " <b>&#9679;</b>", ""),
                     esc(tw$sectors), esc(tw$years))
      tg <- data.frame(town = tw$town, lat = tw$lat, lon = tw$lon, row = row, persist = tw$persists_to_1961plus) |>
        group_by(town, lat, lon) |>
        summarise(n = n(), n_persist = sum(persist), rows = paste(row, collapse = ""), .groups = "drop")
      tpop <- sprintf("<b>%s</b>: %s pre-1960 hazardous-trade firm%s<br><i>Placed at the town centre: the directories give no usable street address.</i>%s
                       <div style='max-height:260px;overflow-y:auto;margin-top:4px'><table style='font-size:11px'><tr><th align=left>Firm</th><th align=left>Trade</th><th align=left>Listed</th></tr>%s</table></div>",
                      esc(tg$town), tg$n, ifelse(tg$n == 1, "", "s"),
                      ifelse(tg$n_persist > 0, sprintf("<br>&#9679; = still listed in the 1965–1992 directory (%s)", tg$n_persist), ""), tg$rows)
      px <- px |> addCircleMarkers(data = tg, ~lon, ~lat, radius = pmin(4 + 1.6 * sqrt(tg$n), 18), color = ifelse(tg$n_persist > 0, "#000000", "#ffffff"),
                    weight = ifelse(tg$n_persist > 0, 2, 0.8), fillColor = HIST_COL, fillOpacity = 0.5, popup = tpop,
                    popupOptions = popupOptions(maxWidth = 420), label = sprintf("%s: %s firms", tg$town, tg$n),
                    group = "Pre-1960 hazardous trades", options = pathOptions(pane = "haz"))
    }
    if (nrow(st)) px <- px |> addCircleMarkers(data = st, ~lon, ~lat, radius = 3 + 1.2 * sqrt(st$editions), color = ring(st),
                    weight = ifelse(st$persists_to_1961plus, 2, 0.8), fillColor = HIST_COL, fillOpacity = 0.95, popup = pop(st),
                    group = "Pre-1960 hazardous trades", options = pathOptions(pane = "haz"))
    px |> addLegend("topleft", colors = c(HIST_COL, HIST_COL), labels = c("Street address (Denver 1891+, larger cities 1910+)", "Town centre only (one marker per town; size = number of firms)"),
                    title = "Pre-1960 hazardous trades<br><small>black ring = firm or address still in the 1965–1992 directory</small>",
                    opacity = c(0.95, 0.55), layerId = "histlegend")
  })

  # ---- trends
  sy_sel <- reactive({
    s <- sel_sites()
    site_yr |> filter(site_id %in% s$site_id, year >= input$yrs[1], year <= input$yrs[2]) |>
      left_join(s |> select(site_id, radar), by = "site_id")
  })
  output$p_sector <- renderPlotly({
    d <- sy_sel() |> separate_rows(sectors, sep = ";") |> filter(sectors %in% input$sec) |> count(year, sectors)
    ggplotly(ggplot(d, aes(year, n, colour = sectors)) + geom_line() + geom_point(size = 1.2) +
               labs(x = "Directory edition", y = "Sites listed", colour = NULL) + theme_minimal())
  })
  output$p_timeline <- renderPlotly({
    a <- sy_sel() |> count(year, name = "n") |> mutate(series = "Manufacturers' directory sites (hazardous sectors), complete editions 1965-1992")
    h <- sel_hist(); b <- if (is.null(h) || !nrow(h)) NULL else h |> mutate(yr = strsplit(years, " ")) |> unnest(yr) |> mutate(year = as.integer(yr)) |> filter(year >= input$yrs[1], year <= input$yrs[2]) |> count(year, name = "n") |> mutate(series = "Business-directory hazardous trades, 1871-1956")
    d <- bind_rows(a, b); if (!nrow(d)) return(NULL)
    inc <- if (is.null(edcov)) integer() else edcov$year[edcov$complete %in% c(FALSE, "FALSE")]; d$complete <- !d$year %in% inc
    d <- d |> filter(complete); if (!nrow(d)) return(NULL)
    d$text <- sprintf("%s: %s (%s)%s", d$year, d$n, d$series, ifelse(d$complete, "", " - incomplete scan"))
    ggplotly(ggplot(d, aes(year, n, colour = series, group = series, text = text)) + geom_line() + geom_point(aes(shape = complete), size = 2.2, fill = "white") + scale_shape_manual(values = c(`TRUE` = 16, `FALSE` = 21), guide = "none") +
               scale_colour_manual(values = c("Business-directory hazardous trades, 1871-1956" = "#8c510a", "Manufacturers' directory sites (hazardous sectors), complete editions 1965-1992" = "#d1491f")) +
               scale_x_continuous(breaks = seq(1870, 2000, 10)) + labs(x = "Directory edition", y = "Listed", colour = NULL) + theme_minimal(), tooltip = "text") |> hleg() })
  output$p_status <- renderPlotly({
    d <- sy_sel() |> count(year, radar) |> mutate(radar = factor(STATUS_LAB[radar], unname(STATUS_LAB)))
    ggplotly(ggplot(d, aes(year, n, fill = radar)) + geom_col(width = 0.8) + scale_fill_manual(values = setNames(unname(STATUS_COL), unname(STATUS_LAB[names(STATUS_COL)]))) +
               labs(x = "Directory edition", y = "Sites listed", fill = NULL) + theme_minimal())
  })
  output$p_hist <- renderPlotly({
    h <- sel_hist(); if (is.null(h) || !nrow(h)) return(NULL)
    d <- h |> mutate(yr = strsplit(years, " ")) |> unnest(yr) |> mutate(yr = as.integer(yr)) |>
      filter(yr >= input$yrs[1], yr <= input$yrs[2]) |> separate_rows(app_sectors, sep = ";") |> filter(app_sectors %in% input$sec) |>
      count(yr, app_sectors)
    ggplotly(ggplot(d, aes(yr, n, fill = app_sectors)) + geom_col(width = 0.9) + scale_x_continuous(breaks = scales::breaks_pretty(8)) + labs(x = "Business directory edition", y = "Firms", fill = NULL) +
               theme_minimal()) |> hleg()
  })
  output$p_mix <- renderPlotly({ if (is.null(mix)) return(NULL)
    ggplotly(ggplot(mix, aes(year, share, fill = group, text = sprintf("%s, %s: %.1f%% (%s firms)", group, year, 100 * share, establishments))) +
               geom_col(position = "stack", width = 0.9) + scale_y_continuous(labels = scales::percent) +
               labs(x = "Directory edition", y = "Share of listed firms", fill = NULL) + theme_minimal(), tooltip = "text") |> hleg() })
  output$p_longev <- renderPlotly({ if (is.null(longev)) return(NULL)
    d <- longev |> mutate(span = last_year - first_year, sector = ifelse(as.logical(hazardous) %in% TRUE, "Hazardous sector", "Other manufacturing"),
                          bin = cut(span, c(-1, 0, 4, 9, 19, 29, 41), c("1 edition", "1–4", "5–9", "10–19", "20–29", "30–41"))) |>
      count(sector, bin) |> group_by(sector) |> mutate(share = n / sum(n))
    ggplotly(ggplot(d, aes(bin, share, fill = sector, text = sprintf("%s: %.0f%% (%s firms)", bin, 100 * share, n))) + geom_col(position = "dodge") +
               scale_fill_manual(values = c("Hazardous sector" = "#d1491f", "Other manufacturing" = "#9a9a9a")) +
               scale_y_continuous(labels = scales::percent) + labs(x = "Years between first and last listing", y = "Share of firms", fill = NULL) + theme_minimal(), tooltip = "text") })
  output$p_share <- renderPlotly({
    d <- sy_sel() |> group_by(year) |> summarise(share = mean(radar == "Not on any list"), n = n())
    ggplotly(ggplot(d, aes(year, share, group = 1, text = paste0(year, ": ", round(100 * share), "% of ", n, " sites"))) + geom_line(colour = "#d1491f") +
               geom_point(colour = "#d1491f") + scale_y_continuous(labels = scales::percent, limits = c(0, NA)) +
               labs(x = "Directory edition", y = NULL) + theme_minimal(), tooltip = "text")
  })

  # ---- neighborhoods
  groups <- reactive({
    s <- sel_sites()
    with_any <- unique(na.omit(s$GEOID))
    with_unk <- unique(na.omit(s$GEOID[s$radar == "Not on any list"]))
    with_tri <- unique(na.omit(tri$GEOID))
    g <- switch(input$cmp,
      any       = ifelse(tract_df$GEOID %in% with_any, "With hazardous sites", "Without hazardous sites"),
      unknown   = ifelse(tract_df$GEOID %in% with_unk, "With potentially unknown sites", "All other tracts"),
      unk_known = ifelse(tract_df$GEOID %in% with_unk, "With potentially unknown sites",
                         ifelse(tract_df$GEOID %in% with_any, "With only known sites", NA)),
      tri       = ifelse(tract_df$GEOID %in% with_tri, "With TRI facilities", "Without TRI facilities"))
    tract_df |> mutate(group = g) |> filter(!is.na(group))
  })
  output$cmp_title <- renderText(names(VARS)[VARS == input$nvar])
  output$p_cmp <- renderPlotly({
    d <- groups(); d$val <- d[[input$nvar]]; d <- d[!is.na(d$val), ]
    d$w <- if (isTRUE(input$popw)) pmax(d$population, 1) else 1
    gs <- unique(d$group); cols <- c("#d1491f", "#24589e", "#7a4aa8", "#7f8c8d")[seq_along(gs)]; names(cols) <- gs
    lab <- names(VARS)[VARS == input$nvar]
    if (input$ptype == "dens") {
      p <- ggplot(d, aes(val, fill = group, colour = group, weight = w)) + geom_density(alpha = 0.25, adjust = 0.9) +
        scale_fill_manual(values = cols) + scale_colour_manual(values = cols) + labs(x = lab, y = NULL, fill = NULL, colour = NULL) +
        theme_minimal() + theme(legend.position = "bottom")
      ggplotly(p) |> hleg()
    } else {
      # box plot from (population-weighted) quantiles, drawn directly in plotly: robust across ggplot2/plotly versions
      wq <- function(x, w, p) { o <- order(x); x <- x[o]; w <- w[o]; cw <- cumsum(w) / sum(w); sapply(p, function(q) x[which(cw >= q)[1]]) }
      pl <- plot_ly()
      for (g in gs) { xi <- d$val[d$group == g]; wi <- d$w[d$group == g]; q <- wq(xi, wi, c(.05, .25, .5, .75, .95))
        pl <- add_trace(pl, type = "box", name = g, x = g, q1 = list(q[2]), median = list(q[3]), q3 = list(q[4]),
                        lowerfence = list(q[1]), upperfence = list(q[5]), fillcolor = cols[[g]], line = list(color = "#333333"),
                        hovertemplate = sprintf("%s<br>5%%: %.1f<br>25%%: %.1f<br>median: %.1f<br>75%%: %.1f<br>95%%: %.1f<br>tracts: %d<extra></extra>",
                                                g, q[1], q[2], q[3], q[4], q[5], length(xi))) }
      layout(pl, yaxis = list(title = lab), xaxis = list(title = ""), showlegend = FALSE,
             annotations = list(x = 0.5, y = 1.06, xref = "paper", yref = "paper", showarrow = FALSE, font = list(size = 11),
                                text = if (isTRUE(input$popw)) "Boxes: population-weighted 25-50-75th percentiles; whiskers 5th-95th" else "Boxes: 25-50-75th percentiles; whiskers 5th-95th"))
    }
  })
  output$t_cmp <- renderDT({
    d <- groups(); gs <- sort(unique(d$group))
    res <- lapply(names(VARS), function(lab) {
      v <- VARS[[lab]]; x <- d[[v]]
      r <- data.frame(Indicator = lab)
      for (g in gs) { xi <- x[d$group == g]; pi <- d$population[d$group == g]; ok <- !is.na(xi)
        r[[paste0(g, ": median")]] <- round(median(xi, na.rm = TRUE), 1)
        r[[paste0(g, ": pop-weighted mean")]] <- round(weighted.mean(xi[ok], pi[ok], na.rm = TRUE), 1) }
      a <- x[d$group == gs[1]]; b <- x[d$group == gs[2]]
      r$`Wilcoxon p` <- tryCatch(format.pval(wilcox.test(a, b)$p.value, digits = 2, eps = 1e-4), error = function(e) NA)
      r })
    out <- bind_rows(res)
    ns <- table(d$group); pops <- tapply(d$population, d$group, sum, na.rm = TRUE)
    datatable(out, rownames = FALSE, options = list(dom = "t", pageLength = 20, scrollX = TRUE),
              caption = paste(sprintf("%s: %s tracts, population %s", names(ns), ns, format(pops[names(ns)], big.mark = ",")), collapse = " · "))
  })

  # ---- receptors
  recv <- reactive({
    s <- sel_sites() |> filter(radar == "Not on any list")
    r <- bind_rows(schools |> transmute(name, kind = type, detail = paste("Grades", grades), address, lat, lon),
                   health |> transmute(name, kind = category, detail = type, address, lat, lon)) |> filter(kind %in% input$recv)
    if (!nrow(s) || !nrow(r)) return(NULL)
    S <- st_transform(st_as_sf(s, coords = c("lon", "lat"), crs = 4326), 26913)
    R <- st_transform(st_as_sf(r, coords = c("lon", "lat"), crs = 4326), 26913)
    nb <- st_is_within_distance(R, S, dist = input$buf)
    keep <- lengths(nb) > 0
    if (!any(keep)) return(r[0, ])
    RX <- st_coordinates(R); SX <- st_coordinates(S)
    dmin <- mapply(function(i, js) round(min(sqrt((SX[js, 1] - RX[i, 1])^2 + (SX[js, 2] - RX[i, 2])^2))), which(keep), nb[keep])
    near <- mapply(function(js) paste(head(paste0(s$address[js], " (", s$first_year[js], "–", s$last_year[js], ")"), 3), collapse = "; "), nb[keep])
    r[keep, ] |> mutate(n_unknown_sites = lengths(nb[keep]), nearest_m = dmin, nearby_sites = near) |> arrange(nearest_m)
  })
  output$recv_sum <- renderTable({ r <- recv(); if (is.null(r) || !nrow(r)) return(data.frame(Note = "None within this distance"))
    r |> count(kind, name = "places") |> rename(Type = kind, `Within distance` = places) })
  for (o in c("rv_nsel", "nb_nsel", "recv_sum")) outputOptions(output, o, suspendWhenHidden = FALSE)   # small text/table outputs: empty spans count as hidden and would never render
  output$t_recv <- renderDT({ r <- recv(); if (is.null(r)) r <- data.frame(name = character(), kind = character(), detail = character(), address = character(), n_unknown_sites = integer(), nearest_m = numeric(), nearby_sites = character())
    datatable(r |> select(Name = name, Type = kind, Detail = detail, Address = address, `Unknown sites within distance` = n_unknown_sites,
                          `Nearest (m)` = nearest_m, `Nearby sites (first 3)` = nearby_sites),
              rownames = FALSE, filter = "top", options = list(pageLength = 25, scrollX = TRUE)) })

  # ---- corridors (Trends)
  output$p_eg <- renderPlotly({ if (is.null(eg)) return(NULL)
    d <- eg |> filter(scope == "Denver metro", sector %in% c("Chemicals", "Petroleum", "Rubber & plastics", "Primary metals", "Fabricated metals", "Machinery", "Transportation eq.", "Printing", "Food")) |> arrange(sector, year)
    if (!nrow(d)) return(NULL)
    pl <- plot_ly()
    for (sec in unique(d$sector)) { di <- d[d$sector == sec, ]
      pl <- add_trace(pl, data = di, x = ~year, y = ~gamma, type = "scatter", mode = "lines+markers", name = sec, legendgroup = sec,
                      marker = list(size = 8, symbol = ifelse(di$p < 0.05, "circle", "circle-open")),
                      text = sprintf("%s %s: γ = %.4f, p = %.3f (%s of %s firms)", sec, di$year, di$gamma, di$p, di$n, di$n_all), hoverinfo = "text") }
    layout(pl, xaxis = list(title = list(text = "Directory edition", standoff = 8), dtick = 5), yaxis = list(title = "Ellison–Glaeser γ", zeroline = TRUE),
           legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left"), margin = list(t = 10)) })
  output$p_trans <- renderPlotly({ if (is.null(trans)) return(NULL)
    d <- trans |> filter(from != to, !is.na(to), to != "", !is.na(from), from != "") |> arrange(desc(N)) |> head(15) |> mutate(lab = paste(from, "→", to), lab = factor(lab, rev(lab)))
    ggplotly(ggplot(d, aes(N, lab, text = sprintf("%s: %s cell-transitions (%.0f%% of transitions from %s)", lab, N, 100 * share_of_from, from))) + geom_col(fill = "#7a0177") +
               labs(x = "Cell-transitions, 1965–1992", y = NULL) + theme_minimal(), tooltip = "text") })


  # ---- Colorado trends
  output$p_eg_co <- renderPlotly({ if (is.null(eg)) return(NULL)
    d <- eg |> filter(scope == "statewide", sector %in% c("Chemicals", "Petroleum", "Rubber & plastics", "Primary metals", "Fabricated metals", "Machinery", "Transportation eq.", "Printing", "Food")) |> arrange(sector, year)
    pl <- plot_ly(); for (sec in unique(d$sector)) { di <- d[d$sector == sec, ]
      pl <- add_trace(pl, data = di, x = ~year, y = ~gamma, type = "scatter", mode = "lines+markers", name = sec, marker = list(size = 8, symbol = ifelse(di$p < 0.05, "circle", "circle-open")),
                      text = sprintf("%s %s: γ = %.4f, p = %.3f", sec, di$year, di$gamma, di$p), hoverinfo = "text") }
    layout(pl, xaxis = list(title = "Directory edition", dtick = 5), yaxis = list(title = "Ellison–Glaeser γ"), legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left"), margin = list(t = 10)) })
  REG_COL <- c("Denver (Arapahoe before 1902)" = "#d1491f", "Denver" = "#d1491f", "Denver suburbs" = "#f4a582", "mining counties" = "#4d4d4d", "Pueblo" = "#24589e", "southern Hispano counties" = "#1b7837",
               "rest of Colorado" = "#9a9a9a", "Boulder, Larimer, Weld" = "#7a0177", "Colorado Springs (El Paso)" = "#e6ab02", "Grand Junction (Mesa)" = "#41b6c4", "Colorado" = "#000000")
  output$p_co_reg <- renderPlotly({ req(co_reg); pl <- plot_ly()
    for (r in unique(co_reg$region)) { d <- co_reg[co_reg$region == r, ]
      pl <- pl |> add_trace(x = d$census, y = d$pct_trades, type = "scatter", mode = "lines+markers", name = r, legendgroup = r, line = list(color = REG_COL[[r]]), marker = list(color = REG_COL[[r]]),
                            text = sprintf("%s %s: %s%% of trades (%s), %s%% of population", r, d$census, d$pct_trades, d$trades, d$pct_pop), hoverinfo = "text") |>
        add_trace(x = d$census, y = d$pct_pop, type = "scatter", mode = "lines", name = r, legendgroup = r, showlegend = FALSE, line = list(color = REG_COL[[r]], dash = "dash"), hoverinfo = "skip") }
    layout(pl, xaxis = list(title = "Census"), yaxis = list(title = "% of the state", rangemode = "tozero"), legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left"), margin = list(t = 10)) })
  output$t_co_cor <- renderTable({ req(co_cor); setNames(co_cor, c("Census", "Counties", "Foreign born", "Hispanic", "Laborers", "Black")) }, digits = 2)
  output$map_co <- renderLeaflet({ req(co_cnty, input$co_year, input$co_var); d <- co_cnty[co_cnty$census == as.integer(input$co_year), ]
    x <- if (input$co_var == "rate") ifelse(d$pop > 0, 1000 * d$firms_haz / d$pop, NA) else d[[input$co_var]]
    pal <- colorNumeric("YlOrRd", domain = x, na.color = "#eeeeee")
    lab <- names(c("Hazardous trades per 1,000 residents" = "rate", "Hispanic (%)" = "pct_hisp", "Foreign born (%)" = "pct_fb", "Black (%)" = "pct_black", "Laborers (%)" = "pct_laborers"))[c("rate", "pct_hisp", "pct_fb", "pct_black", "pct_laborers") == input$co_var]
    leaflet() |>                                                       # SVG renderer: the canvas one errors when this map is rebuilt on each year or variable change
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", options = tileOptions(maxNativeZoom = 16), attribution = "Tiles &copy; Esri") |>
      addPolygons(data = d, fillColor = pal(x), fillOpacity = 0.75, color = "#555", weight = 0.6,
                  popup = sprintf("<b>%s County, %s</b><br>Population %s<br>Hazardous trades of the decade: %s<br>Black %s%% · Hispanic %s%% · foreign born %s%% · laborers %s%%",
                                  esc(d$name), d$census, format(d$pop, big.mark = ","), d$firms_haz, d$pct_black, d$pct_hisp, d$pct_fb, d$pct_laborers)) |>
      addLegend("bottomright", pal = pal, values = x, title = paste0(lab, "<br><small>", input$co_year, "</small>"), opacity = 0.8) })
  output$p_co_share <- renderPlotly({ req(co_share); yrs <- setdiff(grep("^[0-9]{4}$", names(co_share), value = TRUE), "1965"); pl <- plot_ly()
    for (i in seq_len(nrow(co_share))) { r <- co_share$region[i]; y <- as.numeric(unlist(co_share[i, yrs]))
      pl <- pl |> add_trace(x = as.integer(yrs), y = y, type = "scatter", mode = "lines+markers", name = r, line = list(color = REG_COL[[r]]), marker = list(color = REG_COL[[r]]),
                            text = sprintf("%s %s: %.1f%%", r, yrs, y), hoverinfo = "text") }
    layout(pl, xaxis = list(title = "Directory edition"), yaxis = list(title = "% of hazardous manufacturers", rangemode = "tozero"), legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left"), margin = list(t = 10)) })
  output$t_co_pop <- renderTable({ req(co_share); d <- co_share[order(-co_share$pct_pop_1990), c("region", "pct_pop_1990")]; setNames(d, c("Region", "% of 1990 population")) }, digits = 1)
  output$p_co_assoc <- renderPlotly({ req(co_assoc, input$co_out); d <- co_assoc[co_assoc$set == "tracts with data 1990-2020" & co_assoc$outcome == input$co_out & co_assoc$region != "Grand Junction (Mesa)", ]
    if (!nrow(d)) return(NULL); pl <- plot_ly(); regs <- c("Colorado", "Denver", "Denver suburbs", "Boulder, Larimer, Weld", "Colorado Springs (El Paso)", "Pueblo", "rest of Colorado"); regs <- regs[regs %in% d$region]
    for (k in seq_along(regs)) { r <- regs[k]; di <- d[d$region == r, ]; di <- di[order(di$census), ]
      pl <- pl |> add_trace(x = di$census + (k - 4) * 0.9, y = di$b, type = "scatter", mode = "lines+markers", name = sprintf("%s (%s tracts)", r, max(di$tracts)),
                            line = list(color = REG_COL[[r]], width = if (r == "Colorado") 3 else 1.5), marker = list(color = REG_COL[[r]], size = 8),
                            error_y = list(type = "data", array = 1.96 * di$se, color = REG_COL[[r]], thickness = 1),
                            text = sprintf("%s %s: %+.2f (SE %.2f, p = %.3g)", r, di$census, di$b, di$se, di$p), hoverinfo = "text") }
    layout(pl, xaxis = list(title = "Census", tickvals = c(1990, 2000, 2010, 2020)), yaxis = list(title = "Points per log unit of firm density", zeroline = TRUE),
           legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left"), margin = list(t = 10)) })
  output$t_co_leg <- renderTable({ req(co_leg); d <- co_leg
    d$outcome <- c(people_of_color = "People of colour (%)", low_income = "Low income (%)", enviroscreen_pctl = "EnviroScreen (percentile)", pollution_climate_pctl = "Pollution & climate burden (percentile)")[d$outcome]
    d$predictor <- c("log1p(firm_years)" = "All manufacturing, firm-years", "log1p(haz_firm_years)" = "Hazardous sectors, firm-years", "log1p(hidden_sites)" = "Hazardous sites on no list")[d$predictor]
    data.frame(Outcome = d$outcome, Predictor = d$predictor, Estimate = sprintf("%+.2f", d$b), SE = sprintf("%.2f", d$se), p = ifelse(d$p < 0.001, "<0.001", sprintf("%.3f", d$p))) })
  output$t_co_gc <- renderTable({ req(co_gcd); d <- co_gcd[co_gcd$city != "Denver", ]; d$step[d$step == "business, industrial or fire district"] <- "business / industrial"
    setNames(d[order(d$city, match(d$step, c("best", "middle", "worst", "business / industrial"))), ], c("City", "Grade (common scale)", "Areas", "km²", "1965–1980", "1981–1992")) }, digits = 2)

  # ---- Denver over time: NHGIS tract panel on 2010 tracts + firms active in the decade
  output$p_pan <- renderPlotly({
    v <- input$pan_var; lab <- names(PAN_VARS)[PAN_VARS == v]
    validate(need(v %in% c("p_black", "p_white", "p_hisp", "p_fb", "p_pov", "p_owner", "mval_2020", "mrent_2020"), paste0("'", lab, "' is observed once (HMDA 2018-21, shown on the 2020 map), so there is no series to plot; choose a census measure.")),
             need(v %in% names(den_pan) && any(!is.na(den_pan[[v]])), paste0("'", lab, "' is not in the tract panel yet (rerun R/fetch_census.R and R/app_census_layers.R).")))
    d <- pan_trend()$d |> filter(tracts >= 15)
    validate(need(nrow(d) > 0, "Too few tracts with this measure to draw a series."))
    ggplotly(ggplot(d, aes(census, val, colour = group, group = group, text = sprintf("%s, %s: %s (%s tracts)", group, census, round(val, 1), tracts))) + geom_line() + geom_point(size = 2) +
               scale_colour_manual(values = c("Active hazardous firm in tract" = "#d1491f", "Legacy only (firms gone)" = "#7a4aa8", "Never a hazardous firm" = "#7f8c8d")) +
               scale_x_continuous(breaks = seq(1940, 2020, 10)) + labs(x = "Census", y = lab, colour = NULL) + theme_minimal(), tooltip = "text") |> hleg() })
  output$pan_title <- renderText({ v <- input$pan_var; lab <- names(PAN_VARS)[PAN_VARS == v]; if (!length(lab)) "Census tracts, 1940\u20132020" else paste0(lab, ", 1940\u20132020") })
  pan_trend <- reactive({ v <- input$pan_var; req(v %in% names(den_pan))
    b <- den_pan |> filter(!is.na(.data[[v]]), !is.na(pop), pop > 0, core)
    yrs <- sort(unique(b$census)); keep <- NULL
    if (isTRUE(input$pan_bal)) { keep <- b |> count(GEOID) |> filter(n == length(yrs)) |> pull(GEOID); b <- b |> filter(GEOID %in% keep) }
    d <- b |> mutate(group = case_when(firms_haz > 0 ~ "Active hazardous firm in tract", legacy_haz > 0 ~ "Legacy only (firms gone)", TRUE ~ "Never a hazardous firm")) |>
      group_by(census, group) |> summarise(val = weighted.mean(.data[[v]], pop), tracts = n(), .groups = "drop")
    list(d = d, yrs = yrs, n_bal = length(keep)) })
  output$pan_note <- renderUI({ tt <- pan_trend(); d <- tt$d; drop <- d |> filter(tracts < 15)
    HTML(paste0("<small>", if (isTRUE(input$pan_bal)) sprintf("Fixed set: <b>%s tracts</b> with a value in every census %s\u2013%s. ", tt$n_bal, min(tt$yrs), max(tt$yrs)) else "All tracts with a value each year (the set changes over time). ",
                if (nrow(drop)) paste0("Not drawn (under 15 tracts): ", paste(sprintf("%s %s (%s)", drop$group, drop$census, drop$tracts), collapse = "; "), ".") else "", "</small>")) })
  late_tab <- function() { if (is.null(ej_late)) return("")
    OUT <- c(p_black = "% Black", p_white = "% White (race)", p_hisp = "% Hispanic", p_fb = "% foreign born", ppov = "% poverty", p_owner = "% owner-occupied", lmval = "log home value", lmrent = "log rent")
    dd <- ej_late |> filter(outcome %in% names(OUT)) |> mutate(cell = sprintf("%+.2f%s<br><small>(%.2f)</small>", b, ifelse(p < 0.01, "**", ifelse(p < 0.05, "*", ifelse(p < 0.1, "\u2020", ""))), se), outcome = OUT[outcome]) |>
      select(census, outcome, cell) |> pivot_wider(names_from = outcome, values_from = cell)
    paste0("<p><b>2000\u20132020: legacy-site exposure.</b> No complete directory edition exists after 1992, so each later census is related to the tract's density of hazardous establishments listed 1983\u20131992 (per log-unit; population density and distance to downtown controlled; HC1 SE):</p>",
           "<table class='table table-sm' style='font-size:12px'><tr><th>Census</th>", paste0("<th>", names(dd)[-1], "</th>", collapse = ""), "</tr>",
           paste0("<tr><td>", dd$census, "</td>", apply(dd[, -1], 1, function(z) paste0("<td>", ifelse(is.na(z), "\u2013", z), "</td>", collapse = "")), "</tr>", collapse = ""), "</table>") }
  output$ej_models <- renderUI({ if (is.null(ej_mod)) return(NULL)
    TERMS <- c(act_w = "Within tract: change in active-firm density over time", act_b = "Between tracts: average active-firm density", leg_b = "Legacy density (firms gone before 1970)")
    OUT <- c(p_black = "% Black", p_white = "% White (race)", p_hisp = "% Hispanic", p_fb = "% foreign born", ppov = "% poverty", p_owner = "% owner-occupied", lmval = "log home value", lmrent = "log rent")
    h <- ej_mod |> filter(grepl("hybrid", model), outcome %in% names(OUT)) |> mutate(star = ifelse(p < 0.01, "**", ifelse(p < 0.05, "*", ifelse(p < 0.1, "†", ""))),
      cell = sprintf("%+.2f%s<br><small>(%.2f)</small>", b, star, se), outcome = OUT[outcome], term = TERMS[term]) |> select(term, outcome, cell) |>
      pivot_wider(names_from = outcome, values_from = cell)
    r <- if (!is.null(ej_rev)) ej_rev |> mutate(cell = sprintf("%+.3f%s (%.3f)", b, ifelse(p < 0.01, "**", ifelse(p < 0.05, "*", ifelse(p < 0.1, "†", ""))), se)) else NULL
    dec <- if (is.null(ej_dec)) "" else { dd <- ej_dec |> filter(term == "act_w", outcome %in% names(OUT)) |> mutate(cell = sprintf("%+.1f%s", b, ifelse(p < 0.01, "**", ifelse(p < 0.05, "*", ifelse(p < 0.1, "†", "")))), outcome = OUT[outcome]) |> select(census, outcome, cell) |> pivot_wider(names_from = outcome, values_from = cell)
      paste0("<p><b>Census by census</b> (the within-tract association, same controls, HC1 SE):</p><table class='table table-sm' style='font-size:12px'><tr><th>Census</th>", paste0("<th>", names(dd)[-1], "</th>", collapse = ""), "</tr>",
             paste0("<tr><td>", dd$census, "</td>", apply(dd[, -1], 1, function(z) paste0("<td>", ifelse(is.na(z), "–", z), "</td>", collapse = "")), "</tr>", collapse = ""), "</table>") }
    HTML(paste0("<p><b>Who moves in after industry arrives?</b> Pooled over the three censuses with a complete directory edition in the same year, 1970, 1980 and 1990 (", if (nrow(ej_mod)) max(ej_mod$n[grepl("hybrid", ej_mod$model)]) else "", " tract-years, tracts within 10 km of downtown): association with the outcome (percentage points; log points for value and rent) per log-unit of hazardous-establishment density; (SE); ** p&lt;0.01, * p&lt;0.05, † p&lt;0.1.</p>",
                "<table class='table table-sm' style='font-size:12px'><tr><th>Predictor</th>", paste0("<th>", names(h)[-1], "</th>", collapse = ""), "</tr>",
                paste0("<tr><td>", h$term, "</td>", apply(h[, -1], 1, function(z) paste0("<td>", z, "</td>", collapse = "")), "</tr>", collapse = ""), "</table>",
                if (!is.null(r)) paste0("<p><b>Does the population predict where industry goes next?</b> Change in a tract's active firms by the next edition, per percentage point of the predictor (tract density, population, distance and year controlled; tract-clustered SE): ",
                                        paste(sprintf("%s %s", OUT[r$predictor], r$cell), collapse = "; "), ".</p>") else "",
                dec, late_tab(), "<p><small>Reading: within a tract, a rise or fall in hazardous-establishment density between 1970 and 1990 was not followed by a change in Hispanic share or poverty in the same decade; the association is between places: ",
                "tracts with dense industry had larger Hispanic shares, smaller White shares, more poverty and lower home values. The same places still differ in 2000, 2010 and 2020 (table above). ",
                "Black share is not associated with industry at the tract scale. The reverse models ask whether composition at one census predicts the change in the number of hazardous establishments by the next census; with three censuses they are indicative, and an association in both directions is consistent with industry and disadvantaged residents each drawing the other to cheap land rather than with either causing the other.</small></p>")) })
  DL_FILES <- c(dl_zon_geo = "zoning_1929.geojson", dl_zon_holc = "zoning_shares_holc.csv", dl_zon_tr = "zoning_shares_tracts.csv", dl_zon_g = "holc_zoning_by_grade.csv", dl_holc_bd = "holc_boundary.csv", dl_holc_m = "holc_tract_models.csv",
                dl_sf1 = "site_fate_denver.csv", dl_sf2 = "site_fate_denver_pre1960.csv", dl_sf3 = "site_fate_summary.csv")
  DL_LAB <- c(dl_zon_geo = "1925 zoning districts as amended to 1929 (GeoJSON)", dl_zon_holc = "Zoning share by HOLC area (CSV)", dl_zon_tr = "Zoning share by 2010 tract (CSV)", dl_zon_g = "Zoning by HOLC grade (CSV)", dl_holc_bd = "HOLC boundary gaps with rail and zoning controls (CSV)", dl_holc_m = "Change in tract outcomes by HOLC class (CSV)",
              dl_sf1 = "Site fate: 1965-92 Denver sites on today's parcels (CSV)", dl_sf2 = "Site fate: pre-1960 Denver trades on today's parcels (CSV)", dl_sf3 = "Site fate: summary by decade of last listing (CSV)")
  for (k in names(DL_FILES)) local({ kk <- k; output[[kk]] <- downloadHandler(filename = function() DL_FILES[[kk]], content = function(f) file.copy(dd(DL_FILES[[kk]]), f)) })
  output$dl_zoning_btns <- renderUI({ have <- names(DL_FILES)[file.exists(dd(DL_FILES))]; if (!length(have)) return(tags$small(class = "text-muted", "Run R/zoning_1925.R, R/holc_covenants.R and R/site_fate.R to add these files."))
    do.call(tagList, lapply(have, function(k) tagList(downloadButton(k, DL_LAB[[k]], class = "btn-sm mb-1"), br()))) })
  output$dl_panel <- downloadHandler(filename = function() "denver_tract_panel_1940_2020.csv", content = function(f) write.csv(den_pan[den_pan$core, ], f, row.names = FALSE))

  # ---- Denver 1880-1940: reconstructed enumeration districts (R/grf_eds.R + R/denver_eds_analysis.R) with the IPUMS full count
  output$map_1880 <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", options = tileOptions(maxNativeZoom = 16),
               attribution = "Tiles &copy; Esri; districts reconstructed from Brown University GRF addresses; composition IPUMS USA full count; firms: Colorado State Business Directories") |>
      setView(-104.99, 39.74, 12) |> addMapPane("tr", zIndex = 380) |> addMapPane("haz", zIndex = 460) })
  output$ed_unit <- renderUI({ y <- as.integer(input$ed_year); if (is.na(y)) return(NULL)
    if (y >= 1950) tags$div(class = "alert alert-warning py-1 px-2 mb-2", tags$small(tags$b("Unit: census tracts"), " (Denver core, 2010 boundaries; interpolated before 2010). Microdata end at 1940, so the measures are the tract tables'.")) else tags$div(class = "alert alert-light py-1 px-2 mb-2", tags$small(tags$b("Unit: enumeration districts"), " reconstructed from the full count.")) })
  observeEvent(input$ed_year, { y <- as.integer(input$ed_year); if (is.na(y)) return()
    ch <- if (y >= 1950) TR_VARS else ED_VARS; cur <- input$ed_var
    map <- c(pct_black = "p_black", pct_hisp = "p_hisp", pct_fb = "p_fb", pct_owner_hh = "p_owner", median_rent = "mrent_2020", median_value = "mval_2020", p_black = "pct_black", p_hisp = "pct_hisp", p_fb = "pct_fb", p_owner = "pct_owner_hh", mrent_2020 = "median_rent", mval_2020 = "median_value")
    sel <- if (cur %in% ch) cur else if (!is.null(cur) && cur %in% names(map) && map[[cur]] %in% ch) map[[cur]] else ch[[1]]
    updateSelectInput(session, "ed_var", choices = ch, selected = sel) }, ignoreInit = TRUE)
  observe({
    req(input$map_1880_zoom); y <- as.integer(input$ed_year); v <- input$ed_var
    if (!is.na(y) && y >= 1950) { if (is.null(trd) || !v %in% names(trd)) return(); d <- trd[trd$census == y, ]; x <- d[[v]]; lab <- names(TR_VARS)[TR_VARS == v]
      pal <- if (all(is.na(x))) function(z) "#c7c7c7" else colorBin(if (v == "firms") "PuRd" else if (v == "dist_m") "Blues" else "YlOrBr", domain = x, bins = 7, pretty = TRUE, na.color = "#f0f0f0")
      px <- leafletProxy("map_1880") |> clearGroup("eds") |> clearGroup("firms") |> removeControl("ednote") |> removeControl("edlegend") |>
        addPolygons(data = d, fillColor = pal(x), fillOpacity = 0.7, color = "#555555", weight = 0.8, group = "eds", options = pathOptions(pane = "tr"),
                    label = sprintf("Tract %s (%s): %s = %s", d$GEOID, y, lab, ifelse(is.na(x), "no data", round(x, 1))),
                    popup = sprintf("<b>Tract %s</b>, %s census<br>Population %s · Black %s%% · Hispanic %s%% · foreign born %s%% · below poverty %s%% · owner-occupied %s%%<br>Median home value $%s · median rent $%s (2020 $)<br>Hazardous firms of the decade inside: <b>%s</b> · nearest firm %s m from the centroid",
                                    d$GEOID, y, format(d$pop, big.mark = ","), esc(d$p_black), esc(d$p_hisp), esc(d$p_fb), esc(d$p_pov), esc(d$p_owner), esc(d$mval_2020), esc(d$mrent_2020), esc(d$firms), esc(d$dist_m)))
      if (!all(is.na(x))) px <- px |> addLegend("bottomright", pal = pal, values = x, title = paste0(lab, "<br><small>", y, " census, tracts</small>"), layerId = "edlegend", opacity = 0.8)
      else px <- px |> addControl(sprintf("<div style='background:#fff3cd;padding:6px 10px;border-radius:4px;max-width:260px'><b>%s: not in the %s tract tables</b><br><small>Hispanic from 1960, poverty from 1970, foreign born not in 1950/1990 tract tables.</small></div>", lab, y), position = "bottomright", layerId = "ednote")
      if (isTRUE(input$ed_firms)) { a <- list("1950" = c(1941, 1950), "1960" = c(1951, 1960), "1970" = c(1961, 1970), "1980" = c(1971, 1980), "1990" = c(1981, 1990), "2000" = c(1983, 1992), "2010" = c(1983, 1992), "2020" = c(1983, 1992))[[as.character(y)]]
        f <- if (y <= 1960) { if (is.null(hist)) NULL else hist |> filter(precision != "town", !is.na(lat), fe_hazard %in% c(TRUE, "True"), first_year <= a[2], last_year >= a[1]) |> transmute(lon, lat, name, info = years) }
             else { ss <- sites |> filter(!is.na(lat), fe_hazard %in% c(TRUE, "True"), first_year <= a[2], last_year >= a[1]); ss |> transmute(lon, lat, name = address, info = paste(first_year, last_year, sep = "-")) }
        if (!is.null(f) && nrow(f)) px <- px |> addCircleMarkers(data = f, ~lon, ~lat, radius = 4, color = "#000000", weight = 1, fillColor = "#d1491f", fillOpacity = 0.9, group = "firms", options = pathOptions(pane = "haz"), label = sprintf("%s (%s)", f$name, f$info)) }
      return(px) }
    if (is.null(eds) || !v %in% names(eds)) return(); d <- eds[eds$year == y, ]; x <- d[[v]]; lab <- names(ED_VARS)[ED_VARS == v]
    pal <- if (all(is.na(x))) function(z) "#c7c7c7" else colorBin(if (v == "firms") "PuRd" else if (v == "dist_m") "Blues" else "YlOrBr", domain = x, bins = 7, pretty = TRUE, na.color = "#f0f0f0")
    extra <- paste(c(if ("pct_owner_hh" %in% names(d)) sprintf("owner-occupied %s%%", esc(d$pct_owner_hh)), if ("median_rent" %in% names(d)) sprintf("median rent $%s", esc(d$median_rent)), if ("mean_sei" %in% names(d)) sprintf("mean SEI %s", esc(d$mean_sei)),
                     if ("pct_haz_industry" %in% names(d)) sprintf("in hazardous industries %s%%", esc(d$pct_haz_industry)), if ("pct_movers" %in% names(d)) sprintf("moved since 1935 %s%%", esc(d$pct_movers))), collapse = " · ")
    if (!length(extra) || all(extra == "")) extra <- rep("", nrow(d))
    px <- leafletProxy("map_1880") |> clearGroup("eds") |> clearGroup("firms") |> removeControl("ednote") |> removeControl("edlegend") |>
      addPolygons(data = d, fillColor = pal(x), fillOpacity = 0.7, color = "#555555", weight = 0.8, group = "eds", options = pathOptions(pane = "tr"),
                  label = sprintf("ED %s (%s): %s = %s", d$ED, y, lab, ifelse(is.na(x), "no data", round(x, 1))),
                  popup = sprintf("<b>Enumeration district %s</b>, %s census<br>Population %s · Black %s%% · foreign born %s%% (Mexican-born %s%%) · Hispanic %s%% · laborers %s%% · foreign/mixed parentage %s%%<br>%s<br>Hazardous firms of the decade inside: <b>%s</b> · nearest firm %s m from the centroid<br><small>%s addresses geocoded (%s residents) · %s km² · the full table (all fields) is in Data &amp; downloads</small>",
                                  d$ED, y, format(d$pop, big.mark = ","), esc(d$pct_black), esc(d$pct_fb), esc(d$pct_fb_mexico), esc(d$pct_hisp), esc(d$pct_laborers), esc(d$pct_foreign_parentage), extra, esc(d$firms), esc(d$dist_m), esc(d$addresses), esc(d$persons_geocoded), esc(d$area_km2)))
    if (!all(is.na(x))) px <- px |> addLegend("bottomright", pal = pal, values = x, title = paste0(lab, "<br><small>", y, " census</small>"), layerId = "edlegend", opacity = 0.8)
    else px <- px |> addControl(sprintf("<div style='background:#fff3cd;padding:6px 10px;border-radius:4px;max-width:260px'><b>%s: not in the %s census</b><br><small>Availability: literacy to 1930; mother tongue 1910-30; home value, rent, radio 1930-40; citizenship and year of immigration 1900-40; education, wages and 1935 residence 1940 only.</small></div>", lab, y), position = "topright", layerId = "ednote")
    if (isTRUE(input$ed_firms) && !is.null(eds_f)) { f <- eds_f[eds_f$census == y, ]
      if (nrow(f)) px <- px |> addCircleMarkers(data = f, ~lon, ~lat, radius = 4.5, color = "#000000", weight = 1, fillColor = "#d1491f", fillOpacity = 0.95, group = "firms", options = pathOptions(pane = "haz"),
                                                label = sprintf("%s (%s)", f$name, f$listed), popup = sprintf("<b>%s</b><br>%s · listed %s", esc(f$name), esc(f$sector), f$listed)) }
    px })
  output$edg_title <- renderText({ y <- as.integer(input$ed_year); unit <- if (!is.na(y) && y >= 1950) "census tracts within 10 km of downtown" else "enumeration districts"
    win <- if (is.na(y)) "" else if (y <= 1960) "hazardous trade listed in the business directory in the preceding decade" else if (y <= 1990) "hazardous-sector manufacturer listed in the complete directory editions of the preceding decade" else "hazardous-sector manufacturer listed 1983\u20131992 (the last complete directory decade; no directory after 1992, so this compares places near historically listed sites)"
    sprintf("%s: %s with vs. without a %s (choose the census at the top of the tab)", y, unit, win) })
  output$t_edg <- renderTable({ y <- as.integer(input$ed_year)
    if (!is.na(y) && y >= 1950) { if (is.null(trd_g)) return(NULL)
      g <- trd_g |> filter(census == y) |> transmute(Group = sub("dissimilarity \\(all tracts\\)", "Dissimilarity index, Black vs rest, across all tracts (0\u20131)", group), Tracts = EDs, Population = population, `White % (race)` = p_white, `Black %` = p_black, `Hispanic %` = p_hisp, `Foreign born %` = p_fb, `Below poverty %` = p_pov, `Owner-occupied %` = p_owner, `Median value (2020 $)` = mval_2020, `Median rent (2020 $)` = mrent_2020)
      return(g[, sapply(g, function(z) !all(is.na(z))), drop = FALSE]) }
    if (is.null(eds_g)) return(NULL)
    gc <- function(v, r) if (v %in% names(eds_g)) round(eds_g[[v]][eds_g$census == y], r) else NA
    g <- eds_g |> filter(census == y) |> transmute(Group = sub("dissimilarity \\(all mapped EDs\\)", "Dissimilarity index across all districts (0\u20131)", group), EDs, Population = population, `White % (race)` = if ("pct_white" %in% names(eds_g)) round(pct_white, 1) else NA, `Black %` = round(pct_black, 2), `Foreign born %` = round(pct_fb, 1), `Mexican-born %` = round(pct_fb_mexico, 2), `Hispanic %` = round(pct_hisp, 2), `Laborers %` = round(pct_laborers, 1))
    g$`Owner households %` <- gc("pct_owner_hh", 1); g$`Median rent $` <- gc("median_rent", 0); g$`Mean SEI` <- gc("mean_sei", 1); g$`In hazardous industries %` <- gc("pct_haz_industry", 1); g$`Recent immigrants %` <- gc("pct_recent_immig", 1); g$`Moved since 1935 %` <- gc("pct_movers", 1)
    g[, sapply(g, function(z) !all(is.na(z))), drop = FALSE] }, striped = TRUE, spacing = "xs")
  output$t_edm <- renderTable({ y <- as.integer(input$ed_year)
    if (!is.na(y) && y >= 1950) { if (is.null(trd_m)) return(NULL); OUT <- c(p_white = "White % (race)", p_black = "Black %", p_hisp = "Hispanic %", p_fb = "Foreign born %", p_pov = "Below poverty %", p_owner = "Owner-occupied %", log_mval_2020 = "log home value", log_mrent_2020 = "log rent")
      return(trd_m |> filter(census %in% c(y, 0)) |> transmute(Census = ifelse(census == 0, "pooled 1950-2020", as.character(census)), Outcome = coalesce(OUT[outcome], outcome), `b per log m` = round(b_per_log_m, 3), SE = round(se, 3), p = format.pval(p, digits = 2, eps = 1e-4), Tracts = EDs)) }
    if (is.null(eds_m)) return(NULL)
    OUT <- c(pct_white = "White % (race)", pct_black = "Black %", pct_fb = "Foreign born %", pct_fb_mexico = "Mexican-born %", pct_hisp = "Hispanic %", pct_laborers = "Laborers %", pct_owner_hh = "Owner households %", median_rent = "Median rent $", mean_sei = "Mean SEI", pct_haz_industry = "In hazardous industries %", pct_recent_immig = "Recent immigrants %", pct_movers = "Moved since 1935 %", pct_illiterate = "Illiterate %", pct_boarders = "Boarders %")
    eds_m |> filter(census %in% c(y, 0)) |> transmute(Census = ifelse(census == 0, "pooled", as.character(census)), Outcome = coalesce(OUT[outcome], outcome), `b per log m` = round(b_per_log_m, 3), SE = round(se, 3), p = format.pval(p, digits = 2, eps = 1e-4), EDs) }, striped = TRUE, spacing = "xs")
  output$t_d80 <- renderTable({ if (is.null(d80)) return(NULL)
    d80 |> transmute(Distance = band, Residents = residents, `Foreign born %` = round(pct_foreign_born, 1), `German %` = round(pct_german, 1), `Black %` = round(pct_black, 1), `Chinese %` = round(pct_chinese, 1),
                     `Laborers %` = round(pct_laborers_employed, 1), `Mean SEI` = round(mean_sei_employed, 1)) }, striped = TRUE, spacing = "xs")
  output$t_m80 <- renderTable({ if (is.null(m80)) return(NULL)
    OUT <- c(fb = "Foreign born (all)", native_white = "Native-born white", white = "White (any birthplace)", black = "Black or mulatto", chinese = "Chinese", german = "German-born (incl. Prussia, Bavaria, Austria)", irish = "Irish-born", british = "British-born", scandinavian = "Scandinavian-born", canadian = "Canadian-born", other_fb = "Other foreign born", laborer = "Laborer (employed adults)", `sei (employed adults, linear)` = "SEI (linear, employed adults)")
    m80 |> transmute(Outcome = coalesce(OUT[outcome], outcome), `OR per log m` = round(odds_ratio_per_log_m, 3), SE = round(se, 3), p = format.pval(p, digits = 2, eps = 1e-6), n = n) }, striped = TRUE, spacing = "xs")
  output$t_g80 <- renderTable({ if (is.null(g80)) return(NULL)
    g80 |> transmute(Group = group, EDs, Population = population, `Foreign born %` = round(pct_fb, 1), `Black %` = round(pct_black, 1), `German %` = round(pct_german, 1), `Irish %` = round(pct_irish, 1), `Mean SEI` = round(mean_sei, 1)) }, striped = TRUE, spacing = "xs")
  output$p_city <- renderPlotly({ if (is.null(city1880)) return(NULL)
    d <- city1880 |> select(census, `Black %` = pct_black, `Foreign born %` = pct_fb, `Hispanic %` = pct_hispanic, `Dissimilarity: Black` = dissim_black, `Dissimilarity: foreign born` = dissim_fb) |>
      pivot_longer(-census) |> mutate(name = recode(name, `Dissimilarity: Black` = "Black vs non-Black, on each census's EDs (not comparable across years)", `Dissimilarity: foreign born` = "Foreign born vs rest, on each census's EDs"),
                                      panel = ifelse(grepl("vs", name), "Segregation (dissimilarity, 0–1)", "Share of population (%)"))
    if (!is.null(dis_fixed)) d <- bind_rows(d, dis_fixed |> transmute(census, name = paste0("Black vs non-Black, fixed 500 m grid: ", extent), value = dissimilarity_black_vs_nonblack, panel = "Segregation (dissimilarity, 0–1)"))
    ggplotly(ggplot(d, aes(census, value, colour = name, group = name, text = sprintf("%s, %s: %s", name, census, value))) + geom_line() + geom_point() + facet_wrap(~panel, scales = "free_y", ncol = 1) +
               scale_x_continuous(breaks = c(1880, 1900, 1910, 1920, 1930, 1940)) + labs(x = NULL, y = NULL, colour = NULL) + theme_minimal(), tooltip = "text") |> hleg() })
  output$dl_cells <- downloadHandler(filename = function() "industrial_corridor_cells_500m.csv", content = function(f) write.csv(cells, f, row.names = FALSE))
  output$dl_1880 <- downloadHandler(filename = function() "denver_1880_eds_and_firms.zip", content = function(f) {
    td <- tempfile(); dir.create(td); file.copy(Filter(file.exists, c(dd("denver_1880_eds.csv"), dd("denver_1880_firms.csv"), dd("denver_1880_distance.csv"), dd("denver_1880_models.csv"), dd("denver_eds.geojson"), dd("denver_eds_firms.csv"), dd("ed_year_groups.csv"), dd("ed_distance_models.csv"))), td)
    old <- setwd(td); on.exit(setwd(old)); zip(f, list.files(td)) })

  # ---- Redlining & covenants (R/holc_covenants.R)
  output$map_rl <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", options = tileOptions(maxNativeZoom = 16),
               attribution = "Tiles &copy; Esri; HOLC areas &copy; Mapping Inequality (U. Richmond DSL, CC-BY-NC); covenants: Denver Public Library, Mapping Prejudice (public domain)") |>
      setView(-104.97, 39.73, 12) |> addMapPane("ed", zIndex = 370) |> addMapPane("holcp", zIndex = 390) |> addMapPane("pts", zIndex = 460) })
  observe({
    req(input$map_rl_zoom); if (is.null(holc)) return()
    px <- leafletProxy("map_rl") |> clearGroup("holc") |> clearGroup("cov") |> clearGroup("firms") |> clearGroup("ed30") |> clearGroup("zon") |> removeControl("rllegend") |> removeControl("zonlegend") |> removeControl("ptlegend")
    L <- input$rl_layers
    px <- px |> removeControl("edlegend30")
    if ("ed30" %in% L && !is.null(eds_holc)) { e <- eds_holc; v <- input$rl_edvar; x <- e[[v]]
      if (v == "grade") { fc <- unname(HOLC_COL6[x]); fc[is.na(fc)] <- "#eeeeee"; px <- px |> addLegend("bottomleft", colors = unname(HOLC_COL6), labels = names(HOLC_COL6), title = "HOLC class of 1930 district", opacity = 0.7, layerId = "edlegend30") }
      else { pe <- colorBin(if (v %in% c("covenants", "firms_pre1938", "firms_1938_1956", "firms_1961_2002")) "Purples" else "Greys", domain = x, bins = 6, pretty = TRUE, na.color = "#f0f0f0"); fc <- pe(x)
        px <- px |> addLegend("bottomleft", pal = pe, values = x, title = paste0("1930 districts: ", names(c("Black (%)" = "pct_black", "Hispanic (%)" = "pct_hisp", "Foreign born (%)" = "pct_fb", "Laborers (%)" = "pct_laborers", "Racial covenants 1931-35" = "covenants", "Firms to 1937" = "firms_pre1938", "Firms 1938-56" = "firms_1938_1956", "Sites 1965-1992" = "firms_1961_2002"))[c("pct_black", "pct_hisp", "pct_fb", "pct_laborers", "covenants", "firms_pre1938", "firms_1938_1956", "firms_1961_2002") == v]), opacity = 0.8, layerId = "edlegend30") }
      px <- px |> addPolygons(data = e, fillColor = fc, fillOpacity = 0.7, color = "#999999", weight = 0.4, group = "ed30", options = pathOptions(pane = "ed"),
                              label = sprintf("ED %s (1930): HOLC %s · %s covenants · %s%% Black, %s%% Hispanic, %s%% foreign born, %s%% laborers · firms to 1937: %s, 1938-56: %s, sites 1965-1992: %s", e$ED, e$grade, e$covenants, e$pct_black, e$pct_hisp, e$pct_fb, e$pct_laborers, e$firms_pre1938, e$firms_1938_1956, e$firms_1961_2002)) }
    if ("holc" %in% L) { h <- holc; hcls <- ifelse(h$grade %in% names(HOLC_COL), h$grade, ifelse(grepl("Industrial", h$cat), "Industrial", ifelse(grepl("Commercial", h$cat), "Commercial", "ungraded"))); gcol <- unname(HOLC_COL6[hcls])
      px <- px |> addPolygons(data = h, fillColor = gcol, fillOpacity = ifelse("ed30" %in% L, 0.25, 0.45), color = gcol, weight = 2, group = "holc", options = pathOptions(pane = "holcp"),
        label = sprintf("%s (%s): %s", h$label, ifelse(hcls %in% c("Industrial", "Commercial"), paste(hcls, "zone, not graded"), paste("grade", h$grade)), esc(h$cat)),
        popupOptions = popupOptions(maxWidth = 520),
        popup = sprintf("<b>HOLC area %s \u2014 grade %s (%s)</b><br><b>Detrimental influences:</b> %s<br><b>Favorable:</b> %s<br><b>Occupation:</b> %s · <b>income:</b> %s<br><b>Foreign-born families:</b> %s · <b>Negro:</b> %s · <b>infiltration of:</b> %s · <b>relief families:</b> %s · <b>population:</b> %s<br><b>Remarks:</b> <small>%s</small><hr style='margin:4px 0'>Hazardous-trade firms inside: <b>%s</b> before the map (1871\u201337), %s in 1921\u201337, %s after (1938\u201356) · racial covenants 1931\u201335: <b>%s</b><br>1930 full count (reconstructed EDs): %s residents, Black %s%%, foreign born %s%%, Hispanic %s%%, laborers %s%% · 1940: Black %s%%, Hispanic %s%%",
                        h$label, h$grade, esc(h$cat), esc(h$detrimental), esc(h$favorable), esc(h$occupation), esc(h$income), esc(h$holc_foreign_born), esc(h$holc_negro), esc(h$infiltration), esc(h$relief), esc(h$pop_trend), esc(h$remarks),
                        h$firms_pre1938, h$firms_1921_1937, h$firms_1938_1956, h$covenants_1931_35, esc(h$pop_1930), esc(h$pct_black_1930), esc(h$pct_fb_1930), esc(h$pct_hisp_1930), esc(h$pct_laborers_1930), esc(h$pct_black_1940), esc(h$pct_hisp_1940))) |>
        addLegend("bottomright", colors = unname(HOLC_COL6[1:6]), labels = c("A \u2018best\u2019", "B \u2018still desirable\u2019", "C \u2018definitely declining\u2019", "D \u2018hazardous\u2019", "Industrial zone (not graded)", "Commercial zone (not graded)"), title = "HOLC 1938", opacity = 0.7, layerId = "rllegend") }
    px <- px |> clearGroup("zon44") |> removeControl("zon44legend") |> clearGroup("hwy")
    if ("hwy" %in% L && !is.null(hwy)) { h <- hwy[hwy$kind == "Freeway" & !is.na(hwy$start_year) & hwy$start_year >= 1950 & hwy$start_year <= 1979, ]
      px <- px |> addPolylines(data = h, color = "#111111", weight = 4, opacity = 0.85, group = "hwy", options = pathOptions(pane = "holcp"), label = sprintf("%s, opened %s", ifelse(is.na(h$ref_clean), "freeway", h$ref_clean), h$start_year)) }
    if ("zon" %in% L) { px <- add_zoning(px, input$rl_zyear, "zon", "holcp", 0.5, "topleft", "zonlegend")
      if (input$rl_zyear == "1944" && !is.null(zch)) px <- px |> addPolygons(data = zch, fill = TRUE, fillOpacity = 0, color = "#000000", weight = 2.5, dashArray = "5,4", group = "zon", options = pathOptions(pane = "holcp"), label = sprintf("Changed 1929-1944: %s (%.2f km²)", zch$change, zch$km2)) }
    if (any(c("cov", "firms") %in% L)) { lc <- c(if ("cov" %in% L) c("#333333", "#ff7f00"), if ("firms" %in% L) "#d1491f")
      ll <- c(if ("cov" %in% L) c("Racial covenant 1931-35", "Covenant that also bars manufacturing"), if ("firms" %in% L) sprintf("Hazardous-trade firm, %s", switch(input$rl_firms, pre = "1871-1937", mid = "1921-1937", post = "1938-1956")))
      px <- px |> addLegend("topright", colors = lc, labels = ll, title = "Points", opacity = 0.9, layerId = "ptlegend") }
    if ("cov" %in% L && !is.null(coven)) px <- px |> addCircleMarkers(data = coven, ~lon, ~lat, radius = 3, color = "#000000", weight = 0.5, fillColor = ifelse(coven$excludes_industry %in% TRUE, "#ff7f00", "#333333"), fillOpacity = 0.85, group = "cov", options = pathOptions(pane = "pts"),
        label = sprintf("Covenant %s, %s%s", coven$year, coven$subdivision, ifelse(coven$excludes_industry %in% TRUE, " (also bars business/manufacturing)", "")),
        popup = sprintf("<b>Racial covenant, %s</b><br>%s<br><i>\u201c%s\u201d</i>%s", coven$year, esc(coven$subdivision), esc(coven$restriction), ifelse(coven$excludes_industry %in% TRUE, "<br><b>Also restricts business or manufacturing use.</b>", "")))
    if ("firms" %in% L && !is.null(hist)) { w <- switch(input$rl_firms, pre = c(1871, 1937), mid = c(1921, 1937), post = c(1938, 1956)); f <- hist |> filter(precision != "town", town == "DENVER", first_year <= w[2], last_year >= w[1])
      px <- px |> addCircleMarkers(data = f, ~lon, ~lat, radius = 4.5, color = "#ffffff", weight = 0.8, fillColor = "#d1491f", fillOpacity = 0.95, group = "firms", options = pathOptions(pane = "pts"),
                                   label = sprintf("%s (%s)", f$name, f$years), popup = sprintf("<b>%s</b><br>%s · %s · listed %s", esc(f$name), esc(f$street), esc(f$sectors), esc(f$years))) }
    px })
  output$p_holc_sh <- renderPlotly({ if (is.null(holc_sh)) return(NULL)
    cls <- intersect(c("A", "B", "C", "D", "Industrial", "Commercial"), sub("share_", "", grep("^share_", names(holc_sh), value = TRUE)))
    d <- holc_sh |> select(layer, total, all_of(paste0("share_", cls))) |> rename_with(~ sub("share_", "", .x)) |> pivot_longer(all_of(cls), names_to = "grade", values_to = "share") |> mutate(layer = factor(layer, rev(unique(holc_sh$layer))), grade = factor(grade, cls))
    ggplotly(ggplot(d, aes(share, layer, fill = grade, text = sprintf("%s: %.1f%% in %s (n = %s)", layer, share, grade, round(total)))) + geom_col(position = "stack") +
               scale_fill_manual(values = c(A = "#4d8a3a", B = "#3b8fa0", C = "#c9a800", D = "#c0392b", Industrial = "#7f7f7f", Commercial = "#b07cb0")) + scale_x_continuous(breaks = seq(0, 100, 50)) + labs(x = "Share (%)", y = NULL, fill = "HOLC class") + theme_minimal(), tooltip = "text") |> hleg() })
  output$t_hmda <- renderTable({ if (is.null(hmda_g)) return(data.frame(Note = "Run R/fetch_hmda.R to add HMDA 2018-21 lending by grade."))
    hmda_g |> transmute(Grade = grade, Tracts = tracts, Applications = apps, `Denial rate %` = denial_rate, `Black denial %` = black_denial_rate, `Hispanic denial %` = hisp_denial_rate, `Hispanic share of applicants %` = pct_apps_hisp, `Black share %` = pct_apps_black, `Median loan $k` = median_loan_k, `Median income $k` = median_income_k) }, striped = TRUE, spacing = "xs")
  output$hmda_note <- renderUI({ if (is.null(hmda_m)) return(NULL)
    HTML(paste0("<small>Denial rate vs grade A, applicant income controlled (tracts with 30+ applications, weighted by applications): ", paste(sprintf("%s %+.1f pts (p = %.3f)", hmda_m$term, hmda_m$b, hmda_m$p), collapse = "; "), ".</small>")) })
  output$t_edcls <- renderTable({ if (is.null(ed_cls)) return(NULL)
    ed_cls |> filter(census == 1930) |> transmute(`HOLC class` = grade, `Covenants 1931-35` = ifelse(has_covenant, "yes", "none"), EDs, Population = population, `Black % 1930` = pct_black, `Hispanic % 1930` = pct_hisp, `Foreign born %` = pct_fb, `Laborers %` = pct_laborers,
                                                 `Firms to 1937 (per 10k)` = sprintf("%d (%.1f)", firms_pre1938, firms_per_10k_pre1938), `Firms 1938-56 (per 10k)` = sprintf("%d (%.1f)", firms_1938_1956, firms_per_10k_1938_56), `Sites 1965-1992 (per 10k)` = sprintf("%d (%.1f)", firms_1961_2002, firms_per_10k_1961_2002)) }, striped = TRUE, spacing = "xs")
  output$p_ed_sh <- renderPlotly({ if (is.null(ed_sh)) return(NULL)
    LAB <- c(pct_white = "White", pct_black = "Black", pct_fb = "foreign born", pct_fb_mexico = "Mexican-born", pct_hisp = "Hispanic", pct_laborers = "laborers", pct_owner_hh = "owner-occupied", median_rent = "rent", mean_sei = "SEI")
    d <- ed_sh |> filter(measure %in% names(LAB)) |> mutate(m = LAB[measure])
    if (!is.null(trd_s)) { LT <- c(p_white = "White", p_black = "Black", p_hisp = "Hispanic", p_fb = "foreign born", p_pov = "below poverty", p_owner = "owner-occupied", mrent_2020 = "rent", mval_2020 = "home value")
      d <- bind_rows(d, trd_s |> filter(measure %in% names(LT)) |> mutate(m = LT[measure])) }
    d <- d |> mutate(m = factor(m, unique(c(LAB, "below poverty", "home value")))); nb <- sum(unique(d$census) < 1950)
    ggplotly(ggplot(d, aes(factor(census), share_firms_top_quartile, fill = m, text = sprintf("%s, top quartile by %s: %.0f%% of %s firms (bottom quartile %.0f%%)", census, m, share_firms_top_quartile, firms, share_firms_bottom_quartile))) +
               geom_col(position = position_dodge(width = 0.8), width = 0.75) + geom_hline(yintercept = 25, linetype = "dashed", colour = "grey40") + geom_vline(xintercept = nb + 0.5, colour = "grey60") +
               labs(x = "Census", y = "% of the decade's firms in the top-quartile districts", fill = "Ranked by") + theme_minimal(), tooltip = "text") |> hleg() })
  output$t_holc_g <- renderTable({ if (is.null(holc_g)) return(NULL)
    holc_g |> transmute(Grade = grade, Areas = areas, `Firms before map (1871-1937)` = firms_pre1938, `Areas with one` = areas_with_firm_pre1938, `Firms 1921-37` = firms_1921_1937, `Firms 1938-56` = firms_1938_1956, `Remarks cite industry` = mentions_industry, Covenants = covenants_1931_35, `Pop 1930` = pop_1930, `Black % 1930` = pct_black_1930, `Hispanic % 1930` = pct_hisp_1930, `Laborers % 1930` = pct_laborers_1930, `Black % 1940` = pct_black_1940, `Hispanic % 1940` = pct_hisp_1940) }, striped = TRUE, spacing = "xs")
  output$p_holc_tr <- renderPlotly({ if (is.null(holc_tr)) return(NULL); v <- input$rl_var; lab <- c(p_hisp = "Hispanic (%)", p_black = "Black (%)", p_fb = "Foreign born (%)", p_pov = "Below poverty (%)", p_owner = "Owner-occupied (%)", mval_2020 = "Median home value (2020 $)", mrent_2020 = "Median rent (2020 $)", firms_haz = "Hazardous firms in decade")[[v]]
    if (!v %in% names(holc_tr)) return(NULL); d <- holc_tr |> filter(!is.na(.data[[v]]), !is.nan(.data[[v]])) |> mutate(basis = "2010 tracts by dominant grade", unit = sprintf("%s tracts", tracts)); if (!nrow(d)) return(NULL)
    if (!is.null(holc_pre) && v %in% names(holc_pre)) d <- bind_rows(holc_pre |> filter(!is.na(.data[[v]]), !is.nan(.data[[v]])) |> mutate(basis = "HOLC areas (districts area-weighted)", unit = sprintf("%s areas", areas)) |> select(census, grade, all_of(v), basis, unit), d)
    xb <- if (min(d$census) < 1940) seq(1900, 2020, 20) else seq(1940, 2020, 20)
    ggplotly(ggplot(d, aes(census, .data[[v]], colour = grade, group = interaction(grade, basis), linetype = basis, text = sprintf("Grade %s, %s: %.1f (%s; %s)", grade, census, .data[[v]], unit, basis))) + geom_vline(xintercept = 1938, colour = "grey60") + geom_line() + geom_point(size = 2) +
               scale_colour_manual(values = c(A = "#4d8a3a", B = "#3b8fa0", C = "#c9a800", D = "#c0392b")) + scale_linetype_manual(values = c("HOLC areas (districts area-weighted)" = "dashed", "2010 tracts by dominant grade" = "solid"), guide = "none") + scale_x_continuous(breaks = xb) + labs(x = NULL, y = lab, colour = "HOLC grade") + theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1)), tooltip = "text") |> gradeleg() |> plotly::layout(legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left"), margin = list(t = 10)) })
  bd_pair <- reactive({ pr <- strsplit(input$rl_pair, "-")[[1]]; list(hi = pr[1], lo = pr[2], col = gsub("-", "_minus_", input$rl_pair)) })
  output$holc_bd_note <- renderUI({ if (input$rl_bdes != "band" || is.null(holc_bd) || !"pair" %in% names(holc_bd)) return(NULL)
    if (!any(holc_bd$pair == input$rl_pair & holc_bd$outcome == input$rl_bvar)) tags$small(class = "text-warning", sprintf("Too few districts or tracts border both %s and %s areas for a boundary comparison (A and B areas are few and small); switch to 'All areas'.", bd_pair()$hi, bd_pair()$lo)) })
  output$p_holc_bd <- renderPlotly({ v <- input$rl_bvar; pp <- bd_pair()
    d <- if (input$rl_bdes == "band") { if (is.null(holc_bd) || !"pair" %in% names(holc_bd)) return(NULL); holc_bd |> filter(outcome == v, pair == input$rl_pair) |> transmute(census, basis, gap, lo = gap - 1.96 * se, hi = gap + 1.96 * se, text = sprintf("%s: %s %.1f vs %s %.1f (n = %d + %d); gap %+.1f (SE %.1f), %s", census, pp$hi, mean_D, pp$lo, mean_C, n_D, n_C, gap, se, basis)) }
         else { if (is.null(holc_gap) || !pp$col %in% names(holc_gap)) return(NULL); holc_gap |> filter(variable == v) |> transmute(census, basis, gap = .data[[pp$col]], lo = NA, hi = NA, text = sprintf("%s: %s %.1f vs %s %.1f; gap %+.1f (%s)", census, pp$hi, .data[[pp$hi]], pp$lo, .data[[pp$lo]], .data[[pp$col]], basis)) |> filter(!is.na(gap)) }
    if (!nrow(d)) return(NULL); lab <- c(p_black = "Black (%)", p_hisp = "Hispanic (%)", p_fb = "Foreign born (%)", p_owner = "Owner-occupied (%)", p_pov = "Below poverty (%)", p_laborers = "Laborers (%)")[[v]]
    g <- ggplot(d, aes(census, gap, group = basis, linetype = basis, text = text)) + geom_hline(yintercept = 0, colour = "grey50") + geom_vline(xintercept = 1938, colour = "grey60") + geom_line(colour = "#c0392b") + geom_point(colour = "#c0392b", size = 2) +
      scale_linetype_manual(values = c("districts" = "dashed", "HOLC areas" = "dashed", "2010 tracts" = "solid"), guide = "none") + scale_x_continuous(breaks = seq(1900, 2020, 20)) + labs(x = NULL, y = sprintf("%s minus %s: %s", pp$hi, pp$lo, lab)) + theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1))
    if (input$rl_bdes == "band") { g <- g + geom_errorbar(aes(ymin = lo, ymax = hi), width = 2, colour = "#c0392b", alpha = 0.6)
      if ("gap_rail" %in% names(holc_bd)) { r <- holc_bd |> filter(outcome == v, pair == input$rl_pair, !is.na(gap_rail)) |> transmute(census, basis, gap = gap_rail, text = sprintf("%s: gap net of distance to rail lines %+.1f (SE %.1f)", census, gap_rail, se_rail))
        if (nrow(r)) g <- g + geom_point(data = r, aes(census, gap, text = text), inherit.aes = FALSE, shape = 4, size = 2.5, colour = "#2c7fb8") }
      if ("gap_zone" %in% names(holc_bd)) { z <- holc_bd |> filter(outcome == v, pair == input$rl_pair, !is.na(gap_zone)) |> transmute(census = census + 1.5, basis, gap = gap_zone, text = sprintf("%s: gap net of rail and of the share zoned industrial in 1925 %+.1f (SE %.1f)", census - 1.5, gap_zone, se_zone))
        if (nrow(z)) g <- g + geom_point(data = z, aes(census, gap, text = text), inherit.aes = FALSE, shape = 3, size = 2.5, colour = "#1a9850") } }
    ggplotly(g, tooltip = "text") })
  output$t_holc_bd <- renderTable({ if (input$rl_bdes != "band" || is.null(holc_bd) || !"pair" %in% names(holc_bd)) return(NULL); pp <- bd_pair()
    d <- holc_bd |> filter(outcome == input$rl_bvar, pair == input$rl_pair); if (!nrow(d)) return(NULL)
    st <- function(b, p) sprintf("%+.1f%s", b, ifelse(is.na(p), "", ifelse(p < 0.01, "**", ifelse(p < 0.05, "*", ifelse(p < 0.1, "\u2020", "")))))
    d2 <- d |> transmute(Census = as.integer(census), Units = basis, lo = sprintf("%.1f (n=%d)", mean_C, n_C), hi = sprintf("%.1f (n=%d)", mean_D, n_D), Gap = st(gap, p), SE = se,
                         `Gap net of rail` = if ("gap_rail" %in% names(d)) ifelse(is.na(gap_rail), "", st(gap_rail, p_rail)) else NULL,
                         `Net of rail + 1925 zoning` = if ("gap_zone" %in% names(d)) ifelse(is.na(gap_zone), "", st(gap_zone, p_zone)) else NULL,
                         `Zoned industrial 1929 (lo / hi side)` = if ("ind29_C" %in% names(d)) sprintf("%.0f%% / %.0f%%", 100 * ind29_C, 100 * ind29_D) else NULL)
    names(d2)[3:4] <- c(paste(pp$lo, "side"), paste(pp$hi, "side")); d2 }, striped = TRUE, spacing = "xs")
  output$t_holc_ind <- renderTable({ if (is.null(holc_ind)) return(NULL); w <- holc_ind |> select(period, grade, per_km2) |> tidyr::pivot_wider(names_from = grade, values_from = per_km2)
    w |> mutate(`D / C` = ifelse(C > 0, sprintf("%.1f", D / C), "—"), Map = ifelse(as.integer(substr(period, 1, 4)) < 1938, "before", "after")) |> select(Period = period, Map, everything()) }, striped = TRUE, spacing = "xs")
  output$yrs_note <- renderUI({ y <- input$yrs; if (is.null(edcov)) return(NULL)
    e <- edcov |> filter(year >= y[1], year <= y[2]); cmp <- e |> filter(complete %in% c(TRUE, "TRUE")); b <- cmp |> filter(year < 1960); m <- cmp |> filter(year >= 1960)
    tags$small(class = "text-muted", sprintf("Editions in range: %d business-directory (%s) and %d complete manufacturers'-directory (%s).", nrow(b), if (nrow(b)) paste(range(b$year), collapse = "\u2013") else "none", nrow(m), if (nrow(m)) paste(m$year, collapse = ", ") else "none")) })
  # ---- what became of the sites (R/site_fate.R)
  sf_sel <- reactive({ d <- if (identical(input$sf_series, "H")) sf_pre else sf_den; if (is.null(d)) return(NULL)
    d <- d |> filter(use_now %in% input$sf_use); if (isTRUE(input$sf_sens)) d <- d |> filter(use_now %in% c("Residential", "Park / open space", "Civic / school / health"), if ("radar" %in% names(d)) radar == "Not on any list" else TRUE); d })
  output$map_sf <- renderLeaflet({ leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", options = tileOptions(maxNativeZoom = 16), attribution = "Tiles &copy; Esri; parcels: City and County of Denver open data") |> setView(-104.99, 39.75, 12) |> addMapPane("sfzp", zIndex = 380) |>
      addLegend("bottomright", colors = unname(USE_COL[1:6]), labels = names(USE_COL)[1:6], title = "Parcel use today", opacity = 0.9) })
  observe({ req(input$map_sf_zoom); px <- leafletProxy("map_sf") |> clearGroup("sfz") |> removeControl("sfzlegend"); if (input$sf_zyear != "none") add_zoning(px, input$sf_zyear, "sfz", "sfzp", 0.35, "topleft", "sfzlegend") })
  observe({ req(input$map_sf_zoom); d <- sf_sel(); px <- leafletProxy("map_sf") |> clearGroup("sf"); if (is.null(d) || !nrow(d)) return()
    nm <- if ("address" %in% names(d)) d$address else paste(d$name, d$street, sep = ", "); sec <- if ("fe_sectors" %in% names(d)) d$fe_sectors else d$sectors
    px |> addCircleMarkers(data = d, ~lon, ~lat, radius = 5, color = "#333333", weight = 0.6, fillColor = unname(USE_COL[d$use_now]), fillOpacity = 0.9, group = "sf",
      label = sprintf("%s (%s–%s): now %s", nm, d$first_year, d$last_year, d$use_now),
      popup = sprintf("<b>%s</b><br>Listed %s–%s · %s%s<br><b>Today:</b> %s (%s)<br>Zone %s · %s dwelling units · building of %s · parcel %s m from the geocoded point%s", esc(nm), d$first_year, d$last_year, esc(sec),
                      if ("radar" %in% names(d)) paste0("<br>Regulatory status: ", esc(d$radar)) else "", d$use_now, esc(d$D_CLASS_CN), esc(d$ZONE_ID), ifelse(is.na(d$TOT_UNITS), "0", d$TOT_UNITS), ifelse(is.na(d$year_built), "unknown year", d$year_built), ifelse(is.na(d$parcel_dist_m), "?", d$parcel_dist_m),
                      ifelse(d$redeveloped %in% TRUE, "<br><b>Rebuilt since the last listing</b>", ""))) })
  output$p_sf_use <- renderPlotly({ if (is.null(sf_sum)) return(NULL)
    d <- sf_sum |> group_by(series, use_now) |> summarise(n = sum(n), .groups = "drop") |> group_by(series) |> mutate(pct = 100 * n / sum(n)) |> ungroup() |> filter(use_now %in% names(USE_COL)[1:6]) |> mutate(use_now = factor(use_now, rev(names(USE_COL)[1:6])), series = ifelse(grepl("Manufact", series), "1965-1992 sites", "1891-1956 trades"))
    ggplotly(ggplot(d, aes(pct, use_now, fill = series, text = sprintf("%s: %.1f%% (%d sites)", series, pct, n))) + geom_col(position = position_dodge(width = 0.8), width = 0.75) + scale_fill_manual(values = c("1965-1992 sites" = "#d1491f", "1891-1956 trades" = "#8c510a")) +
               labs(x = "% of sites", y = NULL, fill = NULL) + theme_minimal(), tooltip = "text") |> hleg() })
  output$p_zland <- renderPlotly({ req(zot_land); d <- zot_land; lv <- c("1929", "1944", "1955", "2023", "today"); d$year <- factor(d$year, lv, c("1929", "1944", "1955", "2023", "Today")); cols <- c(ZT_COL, "Residence or business (1929, 1944)" = "#eeeeee", "Other districts (1955)" = "#e0e0e0"); pl <- plot_ly()
    for (k in names(cols)) { x <- d[d$cat == k, ]; if (!nrow(x)) next; pl <- pl |> add_trace(x = x$year, y = x$pct, type = "bar", name = k, marker = list(color = cols[[k]], line = list(color = "#999999", width = 0.4)), text = sprintf("%s, %s: %.1f%% (%.1f km²)", k, x$year, x$pct, x$km2), hoverinfo = "text", textposition = "none") }
    layout(pl, barmode = "stack", xaxis = list(title = ""), yaxis = list(title = "% of land", range = c(0, 100)), legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left", traceorder = "normal"), margin = list(t = 10)) })
  output$t_zgrade <- renderTable({ req(zot_grade); d <- zot_grade; d$cell <- ifelse(d$year %in% c("1929", "1944", "1955"), sprintf("%.1f%%", d$pct_industrial), sprintf("%.1f%% (%.1f%%)", d$pct_industrial, d$pct_industrial_incl_imx))
    w <- reshape(d[, c("grade", "year", "cell")], idvar = "grade", timevar = "year", direction = "wide"); names(w) <- c("HOLC grade", ifelse(sub("^cell\\.", "", names(w)[-1]) == "today", "Today", sub("^cell\\.", "", names(w)[-1]))); w }, striped = TRUE, spacing = "s")
  output$t_zfate <- renderTable({ req(zot_fate); d <- zot_fate
    data.frame(` ` = ifelse(d$part == "zoned today", "Zoned today", ifelse(d$part == "1929 industrial land in Denver County", "All 1929 industrial land", "Last rezoned (land no longer industrial)")), Group = d$group, `km²` = sprintf("%.2f", d$km2), `%` = sprintf("%.1f", d$pct), check.names = FALSE) }, striped = TRUE, spacing = "xs")
  output$t_zsites <- renderTable({ req(zot_sites); d <- zot_sites; d$year <- ifelse(d$year == "today", "Today", d$year)
    data.frame(Sites = ifelse(grepl("^Hazardous-sector", d$series), "1965–92 manufacturers", "Pre-1960 trades"), n = d$sites, Year = d$year, `% industrial` = d$pct_industrial, `% industrial incl. I-MX` = d$pct_industrial_incl_imx, `% where housing is allowed` = ifelse(is.na(d$pct_housing_allowed), "–", d$pct_housing_allowed), check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  output$t_zpaths <- renderTable({ req(zot_paths); d <- zot_paths
    data.frame(Tracts = d$path, n = d$tracts, Census = d$census, Residents = format(d$residents, big.mark = ","), `% Hispanic` = d$pct_hispanic, `% Black` = d$pct_black, `% White` = d$pct_white, `% in poverty` = d$pct_poverty, `% owner-occupied` = d$pct_owner_occupied, check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  output$map_lu <- renderLeaflet({ leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", options = tileOptions(maxNativeZoom = 16), attribution = "Tiles &copy; Esri; land use: USGS (Drummond et al. 2019)") |>
      setView(-104.97, 39.74, 12) |> addMapPane("lup", zIndex = 300) |> addMapPane("luo", zIndex = 420) |> addMapPane("lus", zIndex = 450) })
  observe({ req(input$map_lu_zoom, input$lu_year); px <- leafletProxy("map_lu") |> clearGroup("lu") |> removeControl("lulegend")
    add_landuse(px, input$lu_year, "lu", input$lu_op, TRUE, "lulegend") })
  observe({ req(input$map_lu_zoom); px <- leafletProxy("map_lu") |> clearGroup("luo")
    if (isTRUE(input$lu_holc) && !is.null(holc)) { h <- holc[holc$grade %in% "D", ]; px <- px |> addPolylines(data = h, color = "#c0392b", weight = 2.5, group = "luo", options = pathOptions(pane = "luo"), label = sprintf("HOLC %s (D, 1938)", h$label)) }
    if (isTRUE(input$lu_zon) && !is.null(zon)) { z <- zon[grepl("Industrial", zon$zone), ]; px <- px |> addPolylines(data = z, color = "#000000", weight = 1.5, dashArray = "4,3", group = "luo", options = pathOptions(pane = "luo"), label = "1929 industrial district") } })
  observe({ req(input$map_lu_zoom, input$lu_year); px <- leafletProxy("map_lu") |> clearGroup("luh") |> removeControl("luhlegend"); if (!isTRUE(input$lu_hwy)) return()
    h <- hw_open(as.integer(input$lu_year)); if (is.null(h) || !nrow(h)) return()
    px |> addPolylines(data = h, color = ifelse(h$kind == "Freeway", "#111111", "#555555"), weight = ifelse(h$kind == "Freeway", 3.5, 1.8), opacity = 0.9, group = "luh", options = pathOptions(pane = "luo"),
                       label = sprintf("%s%s: open %s%s", ifelse(is.na(h$ref_clean), "", h$ref_clean), ifelse(is.na(h$name), "", paste0(" ", h$name)), h$start_year, ifelse(is.na(h$end_year), "", paste0("\u2013", h$end_year)))) |>
      addLegend("topright", colors = c("#111111", "#555555"), labels = c("Freeway", "Major road"), title = paste("Open in", input$lu_year), opacity = 0.9, layerId = "luhlegend") })
  observe({ req(input$map_lu_zoom, input$lu_year); px <- leafletProxy("map_lu") |> clearGroup("lus"); if (!isTRUE(input$lu_sites)) return()
    y <- as.integer(input$lu_year)
    if (y <= 1957) { if (is.null(hist)) return(); h <- hist |> filter(precision != "town", fe_hazard %in% c(TRUE, "True"), first_year <= y, last_year >= y - 9)   # listed in the decade before the photographs
      px |> addCircleMarkers(data = h, ~lon, ~lat, radius = 3.5, color = "#ffffff", weight = 0.6, fillColor = "#111111", fillOpacity = 0.9, group = "lus", options = pathOptions(pane = "lus"), label = sprintf("%s (%s)", h$name, h$years)) }
    else { a <- if (y == 1977) c(1968, 1977) else c(1983, 1992); ids <- unique(site_yr$site_id[site_yr$year >= a[1] & site_yr$year <= a[2]]); s <- sites[sites$site_id %in% ids & sites$fe_hazard %in% c(TRUE, "True"), ]
      px |> addCircleMarkers(data = s, ~lon, ~lat, radius = 3.5, color = "#ffffff", weight = 0.6, fillColor = "#111111", fillOpacity = 0.9, group = "lus", options = pathOptions(pane = "lus"), label = sprintf("%s, %s", s$address, s$hazard_firms)) } })
  output$p_lu_year <- renderPlotly({ req(lu_year); d <- lu_year[lu_year$unit == "Study area", ]; pl <- plot_ly()
    for (k in seq_along(LU_GRP)) { x <- d[d$group == LU_GRP[k], ]; if (!nrow(x)) next
      pl <- pl |> add_trace(x = as.character(x$year), y = x$pct, type = "bar", name = LU_GRP[k], marker = list(color = LU_COL[k], line = list(color = "#999999", width = 0.4)), text = sprintf("%s, %s: %.1f%% (%.1f km\u00b2)", LU_GRP[k], x$year, x$pct, x$km2), hoverinfo = "text", textposition = "none") }
    layout(pl, barmode = "stack", xaxis = list(title = ""), yaxis = list(title = "% of mapped land", range = c(0, 100)), legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left", traceorder = "normal"), margin = list(t = 10)) })
  output$t_lu_holc <- renderTable({ req(lu_holc); g <- expand.grid(grade = c("A", "B", "C", "D"), year = LU_YEARS, group = c("Industrial", "Residential, single family"), stringsAsFactors = FALSE)
    d <- merge(g, lu_holc, by = c("grade", "year", "group"), all.x = TRUE); d$pct[is.na(d$pct)] <- 0
    w <- reshape(d, idvar = c("grade", "group"), timevar = "year", direction = "wide"); names(w) <- sub("pct\\.", "", names(w)); names(w)[1:2] <- c("HOLC grade", "Land use"); w[order(w$`Land use`, w$`HOLC grade`), ] }, digits = 1, striped = TRUE, spacing = "xs")
  output$t_lu_zone <- renderTable({ req(lu_zone); d <- lu_zone
    data.frame(`1929 zoning` = d$zoning, Year = d$year, `Industrial use (sq km)` = d$industrial_use_km2, `% of the district in industrial use` = d$pct_of_zone_in_industrial_use, `Share of all industrial use (%)` = d$share_of_all_industrial_use, check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  output$t_lu_sites <- renderTable({ req(lu_sites); d <- lu_sites
    data.frame(Sites = ifelse(grepl("^Hazardous-sector", d$series), "1965\u201392 manufacturers", "Pre-1960 trades"), Status = d$status, Year = d$year, n = d$sites, `% on industrial land` = d$pct_on_industrial_land, check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  output$t_lu_trans <- renderTable({ req(lu_trans); d <- lu_trans[lu_trans$land_use_1977 == "Industrial", ]
    data.frame(`1977` = d$land_use_1977, `1997` = d$land_use_1997, Sites = d$N, `%` = d$pct_of_1977_group, check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  output$t_lu_paths <- renderTable({ req(lu_paths); d <- lu_paths
    data.frame(Tracts = d$path, n = d$tracts, Census = d$census, Residents = format(d$residents, big.mark = ","), `% Hispanic` = d$pct_hispanic, `% Black` = d$pct_black, `% White` = d$pct_white, `% in poverty` = d$pct_poverty, `% owner-occupied` = d$pct_owner_occupied, check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  output$t_hw_holc <- renderTable({ req(hw_holc); d <- hw_holc; data.frame(`HOLC grade` = d$grade, `Area (sq km)` = d$area_km2, `Freeway km` = d$km_through, `km per sq km` = d$km_per_km2, `% of land within 250 m` = d$pct_within_250m, check.names = FALSE) }, digits = 2, striped = TRUE, spacing = "xs")
  output$t_hw_dec <- renderTable({ req(hw_dec); d <- hw_dec; data.frame(Decade = paste0(d$decade, "s"), `km opened (incl. rebuilt alignments)` = d$km_opened, `km removed` = d$km_removed, `km in service at decade end (net of removals)` = if (is.null(d$km_open_at_decade_end)) NA else d$km_open_at_decade_end, check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  output$t_hw_nb <- renderTable({ req(hw_nb); d <- hw_nb; data.frame(Interstate = d$route, `NBER: opened (Denver County)` = ifelse(is.na(d$nber_first_opened), "\u2013", paste0(d$nber_first_opened, "\u2013", d$nber_last_opened)), `NBER miles` = ifelse(is.na(d$nber_miles), "\u2013", d$nber_miles), `OpenHistoricalMap: first year` = ifelse(is.na(d$ohm_first), "\u2013", d$ohm_first), `OpenHistoricalMap km in service` = if (is.null(d$ohm_km_in_service)) NA else ifelse(is.na(d$ohm_km_in_service), "\u2013", d$ohm_km_in_service), check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  output$t_hw_zon <- renderTable({ req(hw_zon); d <- hw_zon; data.frame(`1929 zoning` = d$cls, `Freeway km` = d$km, `% of freeway km` = d$pct, `% of the land` = ifelse(is.na(d$share_of_land), "\u2013", d$share_of_land), check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  observe({ req(hw_ev); ch <- unique(hw_ev$comparison); updateSelectInput(session, "hw_ev_cmp", choices = ch, selected = ch[length(ch)]) })
  hw_ev_sel <- reactive({ req(hw_ev, input$hw_ev_cmp); hw_ev[hw_ev$comparison == input$hw_ev_cmp, ] })
  output$p_hw_ev <- renderPlotly({ d <- hw_ev_sel(); pl <- plot_ly()
    S <- list(gap_hispanic = c("% Hispanic", "#c0392b"), gap_white = c("% white", "#2c7fb8"), gap_black = c("% Black", "#7b3294"), gap_owner = c("% owner-occupied", "#4d9221"), gap_poverty = c("% in poverty", "#e08214"))
    for (v in names(S)) pl <- pl |> add_trace(x = d$decades_since_opening, y = d[[v]], type = "scatter", mode = "lines+markers", name = S[[v]][1], line = list(color = S[[v]][2]), marker = list(color = S[[v]][2]), connectgaps = FALSE,
      text = sprintf("%s, %+d decades: %+.1f points", S[[v]][1], d$decades_since_opening, d[[v]]), hoverinfo = "text")
    layout(pl, xaxis = list(title = "Decades since the freeway opened (0 = last census before)", dtick = 1, zeroline = FALSE), yaxis = list(title = "Gap from comparison tracts (points)", zeroline = TRUE),
      shapes = list(list(type = "line", x0 = 0.5, x1 = 0.5, y0 = 0, y1 = 1, yref = "paper", line = list(dash = "dot", color = "#888888"))),
      legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left"), margin = list(t = 10)) })
  output$t_hw_ev <- renderTable({ d <- hw_ev_sel(); f <- function(x) ifelse(is.na(x), "\u2013", sprintf("%+.1f", x))
    data.frame(`Decades since opening` = d$decades_since_opening, Tracts = d$tracts, `Population (freeway tracts)` = d$pop_index, `Population (comparison)` = d$comparison_pop_index,
      `Hispanic gap` = f(d$gap_hispanic), `White gap` = f(d$gap_white), `Black gap` = f(d$gap_black), `Owner gap` = f(d$gap_owner), `Poverty gap` = f(d$gap_poverty), check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  output$cs_counts <- renderUI({ req(cs_lnk); d <- cs_lnk; f <- function(k) d[startsWith(d$file, k), ]
    tags$p(class = "small", sprintf("%s Denver residents in 1940, %s with a street-level address; linked to a death record: %s men who died in 1975\u20132020 and %s men and women who died in 1988\u20132005.",
      format(d$linked[1], big.mark = ","), format(d$with_address_point[1], big.mark = ","), format(f("DMF")$with_address_point, big.mark = ","), format(f("Numident")$with_address_point, big.mark = ","))) })
  output$p_cs_grp <- renderPlotly({ req(cs_grp, input$cs_file); d <- cs_pick(cs_grp, CS_FILE[[input$cs_file]]); d <- d[d$measure == input$cs_meas, ]; req(nrow(d))
    lab <- c(industrial = "Industrial district", commercial = "Commercial district", residence = "Residence district", "off the map" = "Outside the 1929 map", ungraded = "Ungraded")
    d$lab <- ifelse(d$group %in% names(lab), lab[d$group], ifelse(nchar(d$group) == 1, paste("Grade", d$group), d$group)); d$lab <- sub("^h", "H", sub("^n", "N", sub("^u", "U", d$lab)))
    d <- d[order(d$adj_mean_age_at_death), ]
    plot_ly(d, x = ~adj_mean_age_at_death, y = ~factor(lab, lab), type = "scatter", mode = "markers", marker = list(size = 12, color = "#2c5d8f"),
            text = ~sprintf("%s: %.1f years (%s people)", lab, adj_mean_age_at_death, format(n, big.mark = ",")), hoverinfo = "text") |>
      layout(xaxis = list(title = "Mean age at death (years)", range = c(min(d$adj_mean_age_at_death) - 0.8, max(d$adj_mean_age_at_death) + 0.8)), yaxis = list(title = "", automargin = TRUE), margin = list(l = 10, t = 10)) })
  CS_EXP <- c(zone_ind = "1929 industrial district", ind10 = "Industrial land within 250 m, 1937 (per 10 points)", haz_500 = "Hazardous trade within 500 m (to 1940)",
              haz_kz = "Hazardous trades to 1940 (per SD)", com10 = "Commercial land within 250 m (check)", holc_D = "HOLC grade D (vs A/B)",
              hidden_kz = "1965\u201392 sites on no inventory (per SD)", known_kz = "1965\u201392 sites on an inventory (per SD)")
  cs_mods <- reactive({ req(cs_mod, input$cs_file); d <- cs_pick(cs_mod, CS_FILE[[input$cs_file]]); d <- d[d$term %in% names(CS_EXP) & grepl("^M[123]:", d$model), ]
    d$m <- substr(d$model, 1, 2); d$feature <- CS_EXP[d$term]; d })
  output$p_cs_coef <- renderPlotly({ d <- cs_mods(); d <- d[d$m %in% input$cs_models, ]; req(nrow(d))
    MC <- c(M1 = "#9e9e9e", M2 = "#c0392b", M3 = "#2c7fb8"); ML <- c(M1 = "Birth year only", M2 = "+ 1940 traits", M3 = "+ same district")
    ord <- rev(CS_EXP); off <- c(M1 = 0.22, M2 = 0, M3 = -0.22); pl <- plot_ly()
    for (k in intersect(names(MC), unique(d$m))) { x <- d[d$m == k, ]; yy <- match(x$feature, ord) + off[[k]]
      pl <- pl |> add_trace(x = x$years, y = yy, type = "scatter", mode = "markers", name = ML[[k]], marker = list(color = MC[[k]], size = 9),
        error_x = list(type = "data", symmetric = FALSE, array = x$hi - x$years, arrayminus = x$years - x$lo, color = MC[[k]], thickness = 1.5, width = 0),
        text = sprintf("%s<br>%s: %+.2f years (%.2f to %.2f)", x$feature, ML[[k]], x$years, x$lo, x$hi), hoverinfo = "text") }
    layout(pl, xaxis = list(title = "Difference in age at death (years)", zeroline = TRUE, zerolinecolor = "#555555"),
           yaxis = list(title = "", tickvals = seq_along(ord), ticktext = unname(ord), range = c(0.5, length(ord) + 0.5), automargin = TRUE),
           legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", xanchor = "left"), margin = list(l = 10, t = 10)) })
  output$t_cs_mod <- renderTable({ d <- cs_mods(); d <- d[order(match(d$term, names(CS_EXP)), d$m), ]
    data.frame(Feature = d$feature, Model = c(M1 = "Birth year only", M2 = "+ 1940 traits", M3 = "+ same district")[d$m], `Years` = sprintf("%+.2f", d$years),
               `95% interval` = sprintf("%.2f to %.2f", d$lo, d$hi), p = ifelse(d$p < 0.01, "<0.01", sprintf("%.2f", d$p)), People = format(d$n, big.mark = ","), check.names = FALSE) }, striped = TRUE, spacing = "xs")
  output$p_enl <- renderPlotly({ req(enl_mod, input$enl_sample, input$enl_out); d <- enl_mod[enl_mod$sample == gsub("\u2013", "-", input$enl_sample) & enl_mod$outcome == input$enl_out, ]; req(nrow(d))
    d <- d[rev(seq_len(nrow(d))), ]; d$exposure <- factor(d$exposure, d$exposure)
    plot_ly(d, x = ~estimate, y = ~exposure, type = "scatter", mode = "markers", marker = list(color = "#c0392b", size = 9),
            error_x = list(type = "data", symmetric = FALSE, array = d$hi - d$estimate, arrayminus = d$estimate - d$lo, color = "#c0392b", width = 0),
            text = ~sprintf("%s<br>%+.2f (%.2f to %.2f); %s men", exposure, estimate, lo, hi, format(n, big.mark = ",")), hoverinfo = "text") |>
      layout(xaxis = list(title = paste("Difference:", input$enl_out), zeroline = TRUE, zerolinecolor = "#555555"), yaxis = list(title = "", automargin = TRUE), margin = list(l = 10, t = 10)) })
  output$t_enl_sh <- renderTable({ req(enl_sh); d <- enl_sh
    data.frame(`1940 address` = d$address_1940, `Men in 1940` = format(d$men_1940, big.mark = ","), `% enlisted (linked)` = d$pct_enlisted, `Height (in)` = d$mean_height,
               `Weight (lb)` = d$mean_weight, `Years of school` = d$mean_school_years, `Men with height` = d$with_height, check.names = FALSE) }, striped = TRUE, spacing = "xs", digits = 1)
  CHK_NOTE <- c("By age in 1940" = "Each model is run separately for people aged 0\u201314, 15\u201329 and 30 and over in 1940. Years of life (95% interval), with 1940 traits.",
    "Own job and household head's job" = "Men's own 1940 industry (hazardous sectors; any manufacturing) and the household head's, alone and alongside the address features. Years of life (95% interval).",
    "Groups" = "The models run separately for Hispanic residents, white non-Hispanic residents, and renting and owning households (groups with at least 200 people). Years of life (95% interval).",
    "Who stayed in the Denver area" = "From the Numident place of death (men and women, deaths 1988\u20132005): whether a 1940 address feature predicts dying in the Denver metro (percentage points), and the age-at-death models among those who died there or elsewhere.",
    "Who links to a death record" = "Share of Denver residents aged 0\u201350 in 1940 who appear in each death file. Linking depends both on matching names and on dying inside the window.",
    "Survival model (Gompertz) check" = "Hazard ratios from CenSoc's recommended doubly-truncated Gompertz model (above 1 = higher mortality), with the implied change in life expectancy at 65. Men's deaths are limited to 1975\u20132005 here, and both files to deaths at ages 65\u2013100 (the ages CenSoc's weights cover).",
    "Freeways and cleared land" = "1940 addresses within 75 m of a freeway built 1950\u20131979 (its path), 75\u2013500 m from one, on residential land cleared by 1977 (USGS land use), or within 100 m of a major road open in 1940; with and without comparing neighbours in the same 1940 enumeration district. We know where people lived in 1940, not whether they were still there when the land was cleared.",
    "Who lived in a later freeway's path" = "Composition of Denver's 1940 residents (all, not only those linked) by where their address stood relative to the later freeways and clearance.",
    "Earlier addresses, 1910\u20131930" = "Denver residents of 1940 traced to their 1910, 1920 and 1930 Denver addresses. Exposure in each census is the address's percentile among all Denver residents that year in nearness to hazardous trades listed in the ten years before it (so censuses with few surviving directories are not penalised); models use the mean percentile (per 10 points), the share of censuses in the top quarter, the same using only censuses whose ten-year window lists 20+ sites, the raw count of censuses within 500 m (for comparison), and the childhood address (ages 0\u201314). Years of life (95% interval).",
    "Earlier addresses: who stayed put" = "Of 1940 residents linked to an earlier Colorado census record: share counted in Denver's census then (whether or not their address could be placed), and, among those whose earlier address was placed, the share within 100 m and 1 km of their 1940 address, within 500 m of a hazardous trade listed in the decade before, and in that census's top quarter for exposure.")
  output$cs_chk_note <- renderUI(tags$p(class = "small text-muted", CHK_NOTE[[input$cs_chk]]))
  output$t_cs_chk <- renderTable({ req(input$cs_chk); d <- cs_chk[[input$cs_chk]]; req(d); drop <- "converged"; if ("term" %in% names(d) && all(is.na(d$term) | grepl("^[A-Za-z_0-9]*$", d$term))) drop <- c(drop, "term"); d <- d[, setdiff(names(d), drop), drop = FALSE]
    d <- d[, c(names(d)[!vapply(d, is.numeric, TRUE)], names(d)[vapply(d, is.numeric, TRUE)]), drop = FALSE]
    names(d) <- gsub("_", " ", names(d)); for (k in names(d)) if (is.numeric(d[[k]]) && grepl("^p$", k)) d[[k]] <- ifelse(d[[k]] < 0.01, "<0.01", sprintf("%.2f", d[[k]]))
    d }, striped = TRUE, spacing = "xs", digits = 2)
  # CX_VARS is defined above the UI
  observe({ req(hl_tr); ch <- CX_VARS[CX_VARS %in% names(hl_tr)]; updateSelectInput(session, "cx_var", choices = ch, selected = ch[1]) })
  observe({ req(aqs); p <- sort(unique(aqs$pollutant)); updateSelectInput(session, "cx_pol", choices = p, selected = if ("Lead (TSP)" %in% p) "Lead (TSP)" else p[1]) })
  observe({ req(tri_fy); r <- range(tri_fy$year); updateSliderInput(session, "cx_tri_year", min = r[1], max = r[2], value = r[1]) })
  cx_tr <- reactive({ req(den_tr, hl_tr); t <- den_tr[den_tr$core | substr(den_tr$GEOID, 1, 5) == "08031", ]; merge(t, hl_tr, by = "GEOID", all.x = TRUE) })
  output$map_cx <- renderLeaflet({
    m <- leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", options = tileOptions(maxNativeZoom = 16), attribution = "Tiles &copy; Esri", group = "Light grey") |>
      setView(-104.97, 39.75, 12) |> addMapPane("trc", zIndex = 380) |> addMapPane("poly", zIndex = 400) |> addMapPane("pts", zIndex = 450)
    if (!is.null(ou_poly)) m <- m |> addPolygons(data = ou_poly, color = "#b30000", weight = 2, fillOpacity = 0.05, group = "Superfund operable units", options = pathOptions(pane = "poly"),
                                                  popup = sprintf("<b>%s</b><br>%s", esc(tools::toTitleCase(tolower(ou_poly$SITE_NAME))), esc(ou_poly$SITE_FEATURE_NAME)))
    if (!is.null(vb_nb)) m <- m |> addPolygons(data = vb_nb, color = "#67000d", weight = 1.5, fillColor = "#fb6a4a", fillOpacity = 0.25, group = "Superfund soil sampling by neighbourhood",
        options = pathOptions(pane = "poly"), label = vb_nb$NBHD_NAME,
        popup = paste0("<b>", vb_nb$NBHD_NAME, "</b> \u2014 Vasquez Blvd/I-70 residential soils, 1998\u20132003<br>", vb_nb$soil_html, "<br><small>EPA Record of Decision 2003, Table 3 (average of yard composites). Cleanup level: lead 400 ppm, arsenic 70 ppm.</small>"))
    if (!is.null(ur_poly)) m <- m |> addPolygons(data = ur_poly, color = "#4a1486", weight = 2, fillOpacity = 0.05, dashArray = ifelse(ur_poly$boundary_confidence == "mapped boundary", NA, "4"),
                                                  group = "Urban renewal projects", options = pathOptions(pane = "poly"), label = tools::toTitleCase(ur_poly$project))
    if (!is.null(pet)) m <- m |> addCircleMarkers(data = pet, ~lon, ~lat, radius = 2.5, stroke = FALSE, fillColor = ifelse(grepl("closed|nfa", tolower(pet$status)), "#fdae6b", "#d94801"), fillOpacity = 0.8,
                                                   group = "Petroleum releases", options = pathOptions(pane = "pts"), popup = sprintf("<b>%s</b><br>%s<br>Reported %s · %s", esc(pet$site_name), esc(pet$address), pet$release_year, esc(pet$status)))
    if (!is.null(sites)) { hs <- sites[sites$fe_hazard %in% c(TRUE, "True") & !is.na(sites$lat), ]
      m <- m |> addCircleMarkers(data = hs, ~lon, ~lat, radius = 3, color = "#222222", weight = 0.6, fillColor = ifelse(hs$radar == "Not on any list", "#e6550d", "#3182bd"), fillOpacity = 0.9,
                                 group = "Historical sites 1965\u201392", options = pathOptions(pane = "pts"), popup = paste0("<b>", esc(hs$address), "</b><br>", esc(hs$radar), ctx_html(hs$site_id))) }
    if (!is.null(aqs_mon)) m <- m |> addCircleMarkers(data = aqs_mon, ~longitude, ~latitude, radius = 6, color = "#006d2c", weight = 2, fillColor = "#a1d99b", fillOpacity = 1,
                                                       group = "Air monitors (AQS)", options = pathOptions(pane = "pts"), label = ~site_name)
    m |> addLegend("bottomleft", colors = c("#d94801", "#fdae6b", "#e6550d", "#3182bd", "#7a0177"), labels = c("Petroleum release, open", "Petroleum release, closed", "1965\u201392 site on no inventory", "1965\u201392 site on an inventory", "TRI facility (size = air releases)"), opacity = 0.9) |>
      addLayersControl(overlayGroups = c("Petroleum releases", "Historical sites 1965\u201392", "TRI facilities", "Air monitors (AQS)", "Urban renewal projects", "Superfund operable units", "Superfund soil sampling by neighbourhood"),
                       options = layersControlOptions(collapsed = TRUE)) |> hideGroup(c("Air monitors (AQS)"))
  })
  observe({ t <- cx_tr(); v <- input$cx_var; req(v %in% names(t)); x <- t[[v]]
    pal <- colorNumeric(if (v == "life_expectancy") "RdYlBu" else "YlOrRd", x, na.color = "#eeeeee", reverse = FALSE)
    lab <- names(CX_VARS)[CX_VARS == v]
    leafletProxy("map_cx") |> clearGroup("tracts") |> removeControl("cxleg") |>
      addPolygons(data = t, fillColor = pal(x), fillOpacity = input$cx_op, color = "#ffffff", weight = 0.4, group = "tracts", options = pathOptions(pane = "trc"),
                  popup = sprintf("<b>Tract %s</b><br>%s: <b>%s</b><br>Historical sites inside: %s known, %s hidden 1965\u201392 · %s pre-1960 trades%s",
                                  t$GEOID, lab, ifelse(is.na(x), "\u2013", round(x, 1)), t$known_1965_92, t$hidden_1965_92, t$pre1960_trades,
                                  if ("industrial_1937" %in% names(t)) sprintf("<br>Industrial land in 1937: %s%%", round(t$industrial_1937, 1)) else "")) |>
      addLegend("bottomright", pal = pal, values = x, title = lab, layerId = "cxleg", opacity = 0.8) })
  observe({ req(tri_fy); d <- tri_fy[tri_fy$year == input$cx_tri_year, ]
    px <- leafletProxy("map_cx") |> clearGroup("TRI facilities"); if (!nrow(d)) return()
    px |> addCircleMarkers(data = d, ~lon, ~lat, radius = 3 + 2 * log10(1 + d$air_lb), color = "#49006a", weight = 1, fillColor = "#7a0177", fillOpacity = 0.6, group = "TRI facilities",
                           options = pathOptions(pane = "pts"), popup = sprintf("<b>%s</b><br>%s<br>%s: %s lb to air, %s lb on-site, %s chemicals%s", esc(d$name), esc(d$address), d$year,
                           format(round(d$air_lb), big.mark = ","), format(round(d$onsite_lb), big.mark = ","), d$chemicals, ifelse(d$near_historical_site %in% TRUE, "<br>Within 100 m of a historical site", ""))) })
  observe({ px <- leafletProxy("map_cx") |> clearGroup("aerial"); if (isTRUE(input$cx_aerial)) px |> addTiles(AERIAL_1933, attribution = AERIAL_ATTR, group = "aerial", options = tileOptions(maxNativeZoom = 19, zIndex = 300)) })
  output$t_cx_pet <- renderTable({ req(pet_status); d <- pet_status
    data.frame(Series = d$series, Status = d$status, Sites = d$sites, `% with a petroleum release` = d$pct_petroleum_release_50m, `% with an open release` = d$pct_open_release,
               `% with a tank facility` = d$pct_tank_facility_50m, check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  output$t_cx_pet_use <- renderTable({ req(pet_use); d <- pet_use[order(-pet_use$sites), ]
    data.frame(Series = d$series, `Parcel today` = d$today, Sites = d$sites, `% with a petroleum release` = d$pct_petroleum_release_50m, `% with a tank facility` = d$pct_tank_facility_50m, check.names = FALSE) },
    digits = 1, striped = TRUE, spacing = "xs")
  output$p_cx_tri <- renderPlotly({ req(tri_holc_y); d <- tri_holc_y; pl <- plot_ly(); G <- c(A = "#76a865", B = "#7cb5bd", C = "#ffff00", D = "#d9838d", ungraded = "#999999")
    for (g in intersect(names(G), unique(d$holc))) { x <- d[d$holc == g, ]; y <- if (input$cx_tri_measure == "air") x$air_lb else x$facilities
      pl <- pl |> add_trace(x = x$year, y = y, type = "scatter", mode = "lines+markers", name = if (g == "ungraded") "Ungraded" else paste("Grade", g), line = list(color = if (g == "C") "#c9b400" else G[[g]]), marker = list(color = if (g == "C") "#c9b400" else G[[g]], size = 5)) }
    layout(pl, xaxis = list(title = ""), yaxis = list(title = if (input$cx_tri_measure == "air") "Pounds released to air" else "TRI facilities", rangemode = "tozero"), legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom"), margin = list(t = 10)) })
  output$p_cx_aqs <- renderPlotly({ req(aqs, input$cx_pol); d <- aqs[aqs$pollutant == input$cx_pol, ]; req(nrow(d))
    plot_ly(d, x = ~year, y = ~mean, type = "scatter", mode = "lines+markers", line = list(color = "#006d2c"), marker = list(color = "#006d2c", size = 5),
            text = ~sprintf("%s %s: %s %s (%s monitors)", pollutant, year, signif(mean, 3), units, monitors), hoverinfo = "text") |>
      layout(xaxis = list(title = ""), yaxis = list(title = paste0("Annual mean (", d$units[1], ")"), rangemode = "tozero"), margin = list(t = 10)) })
  output$t_cx_ur <- renderTable({ req(ur_tab); d <- ur_tab; f <- function(v) ifelse(is.na(v), "\u2013", format(round(v), big.mark = ","))
    data.frame(Project = tools::toTitleCase(d$project_name), Years = paste0(d$first_year, "\u2013", d$last_year), Families = f(d$total_families), White = f(d$white_families), `Non-white` = f(d$nonwhite_families),
               `Substandard dwellings` = f(d$substandard_dwellings), Acres = f(d$acres), `Acres to industry` = f(d$acres_to_industrial), Mapped = ifelse(d$mapped %in% TRUE, "yes", ""), check.names = FALSE) }, striped = TRUE, spacing = "xs")
  output$t_cx_health <- renderTable({ req(hl_hist); d <- hl_hist; nm <- c(history = "Tracts with", tracts = "Tracts", population = "Population", life_expectancy = "Life expectancy",
      casthma = "Asthma %", copd = "COPD %", chd = "Heart disease %", diabetes = "Diabetes %", bphigh = "High BP %", depression = "Depression %", cancer = "Cancer %", csmoking = "Smoking %",
      obesity = "Obesity %", lpa = "Inactive %", access2 = "Uninsured %", lead_risk_decile = "Lead-risk decile")
    d <- d[, intersect(names(nm), names(d)), drop = FALSE]; d$population <- format(d$population, big.mark = ","); names(d) <- nm[names(d)]; d }, digits = 1, striped = TRUE, spacing = "xs")
  UR_TEXT <- list(
    "avondale neighborhood" = "One of the first four projects of the Denver Urban Renewal Authority, created by the City Council in 1958. The federal reports list 249 families in the project area (246 white, 3 non-white) and 110 substandard and 43 standard dwellings on 39.8 acres; the planned reuse was 23.8 acres residential and 9.5 commercial.",
    "blake st" = "One of the authority's first four projects. 189 families (181 white, 8 non-white) and 186 substandard dwellings on 45.7 acres beside the rail yards; 23.6 acres were planned for industrial reuse \u2014 renewal here turned housing into industrial land.",
    "whittier school" = "One of the first four projects, in the historically Black neighbourhood northeast of downtown. 132 families, 128 of them non-white, and 132 substandard dwellings on 8.4 acres, cleared mostly for residential reuse (7.2 acres).",
    "jerome park" = "One of the first four projects. 69 white families and 34 substandard dwellings on 6.3 acres, 4.3 acres of them planned for industrial reuse.",
    "mitchell neighborhood" = "A later project (1966\u20131974 in the federal reports) northeast of downtown; the reports give no family counts. Its boundary here is approximate.",
    "skyline" = "Approved by Denver voters in 1967: 120 acres of downtown were to be cleared of bars, cheap hotels and missions for new towers. About 1,600 people lived in the area, many relocated to public housing farther out; Larimer Square was saved by Dana Crawford, and much of the cleared land stood as parking for decades (Denverite). The federal reports give no family counts for Skyline.",
    "auraria" = "A largely Hispanic neighbourhood by the 1960s, flooded by the South Platte in June 1965. The Auraria Higher Education Center was announced in 1968; the bond issue passed on 4 November 1969 with 52% of the vote over the opposition of the Auraria Residents Organization; relocations were complete by 1972 and the campus by 1976. St. Cajetan's parish moved away, and Ninth Street was preserved as a historic park (Denver Public Library). Renewing Inequality has no boundary or family counts for this project, so it is not on the map.")
  output$ur_case_text <- renderUI({ k <- input$ur_case; req(k); u <- if (!is.null(ur_tab)) ur_tab[ur_tab$project_name == k, ] else NULL; st <- if (!is.null(ur_sites)) ur_sites[ur_sites$project == k, ] else NULL
    tagList(tags$p(class = "small", UR_TEXT[[k]]),
      if (!is.null(u) && nrow(u)) tags$p(class = "small text-muted", sprintf("Federal reports, %s\u2013%s.", u$first_year[1], u$last_year[1])),
      if (!is.null(st) && nrow(st)) tags$p(class = "small", tags$b("Inside the project area: "), sprintf("%s pre-1960 hazardous trades, %s hazardous-sector manufacturers of 1965\u201392, %s petroleum releases since 1986.",
                                                                                                st$historical_sites_inside[1], st$sites_1965_92_inside[1], st$petroleum_releases_inside[1]))) })
  ur_case_d <- reactive({ req(ur_comp, input$ur_case); ur_comp[ur_comp$project == input$ur_case, ] })
  output$p_ur_case <- renderPlotly({ d <- ur_case_d(); req(nrow(d)); pl <- plot_ly()
    S <- list(pct_hispanic = c("% Hispanic", "#c0392b"), pct_black = c("% Black", "#7b3294"), pct_owner = c("% owner-occupied", "#4d9221"), pct_poverty = c("% in poverty", "#e08214"))
    for (v in names(S)) pl <- pl |> add_trace(x = d$census, y = d[[v]], type = "scatter", mode = "lines+markers", name = S[[v]][1], line = list(color = S[[v]][2]), marker = list(color = S[[v]][2]), connectgaps = FALSE)
    pl <- pl |> add_trace(x = d$census, y = d$residents_est, type = "bar", name = "Residents (est.)", yaxis = "y2", marker = list(color = "rgba(120,120,120,0.25)"))
    layout(pl, xaxis = list(title = "", dtick = 10), yaxis = list(title = "%", range = c(0, 100)), yaxis2 = list(title = "Residents", overlaying = "y", side = "right", rangemode = "tozero", showgrid = FALSE),
           legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom"), margin = list(t = 10, r = 50)) })
  output$t_ur_case <- renderTable({ d <- ur_case_d(); req(nrow(d)); f <- function(v) ifelse(is.na(v), "\u2013", sprintf("%.1f", v))
    data.frame(Census = d$census, Residents = format(d$residents_est, big.mark = ","), `% Hispanic` = f(d$pct_hispanic), `% Black` = f(d$pct_black), `% owner` = f(d$pct_owner), `% poverty` = f(d$pct_poverty), check.names = FALSE) },
    striped = TRUE, spacing = "xs")
  output$map_own <- renderLeaflet({ req(den_tr, own_tr, input$ow_var); t <- merge(den_tr[substr(den_tr$GEOID, 1, 5) == "08031", ], own_tr, by = "GEOID"); v <- input$ow_var
    t <- st_transform(t, 4326); x <- ifelse(t$rental_units >= 50, t[[v]], NA); pal <- colorNumeric("PuRd", c(0, 100), na.color = "#eeeeee")
    lab <- names(OW_VARS)[OW_VARS == v]; bb <- unname(st_bbox(t))
    leaflet(options = leafletOptions(preferCanvas = TRUE)) |> addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", options = tileOptions(maxNativeZoom = 16), attribution = "Tiles &copy; Esri") |>
      fitBounds(bb[1], bb[2], bb[3], bb[4]) |>
      addPolygons(data = t, fillColor = pal(x), fillOpacity = 0.7, color = "#ffffff", weight = 0.5,
                  popup = sprintf("<b>Tract %s</b><br>%s units, %s not owner-occupied (%s%%)<br>Held by owners of 20+ units: %s%% · 100+: %s%%<br>Companies: %s%% · Owners outside Colorado: %s%% · Public: %s%%<br>Historical sites inside: %s known, %s hidden 1965\u201392",
                                  t$GEOID, format(t$units, big.mark = ","), format(t$rental_units, big.mark = ","), t$pct_rental, t$pct_rental_owner_20plus, t$pct_rental_owner_100plus,
                                  t$pct_rental_company, t$pct_rental_out_of_state, t$pct_rental_public, t$known_1965_92, t$hidden_1965_92)) |>
      addLegend("bottomright", pal = pal, values = c(0, 100), title = paste0(lab, "<br>"), opacity = 0.8) })
  output$p_own_size <- renderPlotly({ req(own_size); d <- own_size[own_size$grouping == input$ow_group, ]; req(nrow(d))
    d$size <- factor(d$size, levels = c("1 unit", "2-4 units", "5-19 units", "20-99 units", "100-999 units", "1,000+ units"))
    plot_ly(d, x = ~size, y = ~pct_rental_units, type = "bar", marker = list(color = "#7a0177"), text = ~paste0(pct_rental_units, "%"), textposition = "outside",
            cliponaxis = FALSE, hoverinfo = "text", hovertext = ~sprintf("%s: %s owners (%s%% of owners) hold %s rental units (%s%%)", size, format(owners, big.mark = ","), pct_owners, format(rental_units, big.mark = ","), pct_rental_units)) |>
      layout(xaxis = list(title = "owner size (rental units held in Denver)"), yaxis = list(title = "% of rental units"), margin = list(t = 10)) |> config(displayModeBar = FALSE) })
  output$t_own_conc <- renderTable({ req(own_conc); data.frame(Owners = own_conc$grouping, `Top 10` = paste0(own_conc$top10_pct, "%"), `Top 100` = paste0(own_conc$top100_pct, "%"),
    `Top 1% of owners` = paste0(own_conc$top1pct_owners_pct, "%"), `Owners of 20+ units` = paste0(own_conc$owners_20plus_pct, "%"), `Owners of 100+` = paste0(own_conc$owners_100plus_pct, "%"), check.names = FALSE) },
    striped = TRUE, spacing = "s", caption = "Share of privately owned rental units held by the largest owners", caption.placement = "top")
  output$t_own_types <- renderTable({ req(own_types); data.frame(Owner = own_types$owner_type, `Rental units` = format(own_types$rental_units, big.mark = ","), Share = paste0(own_types$pct_rental_units, "%"), check.names = FALSE) },
    striped = TRUE, spacing = "s", caption = "All rental units by type of owner", caption.placement = "top")
  output$t_own_place <- renderTable({ req(own_site, own_holc)
    a <- data.frame(Area = own_site$area, `Rental units` = format(own_site$rental_units, big.mark = ","), `Not owner-occ.` = paste0(own_site$pct_rental, "%"),
                    `Owners 20+` = paste0(own_site$pct_rental_owner_20plus, "%"), Companies = paste0(own_site$pct_rental_company, "%"), `Out of state` = paste0(own_site$pct_rental_out_of_state, "%"), check.names = FALSE)
    b <- data.frame(Area = paste("HOLC", own_holc$holc), `Rental units` = format(own_holc$rental_units, big.mark = ","), `Not owner-occ.` = paste0(own_holc$pct_rental, "%"),
                    `Owners 20+` = paste0(own_holc$pct_rental_owner_20plus, "%"), Companies = paste0(own_holc$pct_rental_company, "%"), `Out of state` = paste0(own_holc$pct_rental_out_of_state, "%"), check.names = FALSE)
    rbind(a, b) }, striped = TRUE, spacing = "s")
  SIZE_ORD <- c("all", "1 unit", "2-4 units", "5-19 units", "20-99 units", "100-999 units", "1,000+ units"); ord_rows <- function(d) d[order(match(d$value, SIZE_ORD), d$value), ]
  output$t_own_ladder <- renderTable({ req(own_ladder); d <- own_ladder
    data.frame(Stage = d$grouping, Owners = format(d$owners, big.mark = ","), `Top 10` = paste0(d$top10_pct, "%"), `Top 100` = paste0(d$top100_pct, "%"), `Top 1%` = paste0(d$top1pct_owners_pct, "%"),
               `Owners of 100+` = paste0(d$owners_100plus_pct, "%"), check.names = FALSE) }, striped = TRUE, spacing = "s")
  output$t_own_loc <- renderTable({ req(own_loc); d <- ord_rows(own_loc[startsWith(own_loc$group, input$ow_loc_group) | own_loc$group == "All private rental units", ])
    data.frame(` ` = d$value, `On the property` = paste0(d$pct_lives_on_the_property, "%"), `Rest of Denver` = paste0(d$pct_elsewhere_in_denver, "%"),
               Metro = paste0(d$pct_denver_metro_within_40_km, "%"), `Rest of CO` = paste0(d$pct_elsewhere_in_colorado, "%"), `Other state` = paste0(d$pct_another_state, "%"),
               `Median km` = d$median_km_to_owner, `Owner ZIP income` = format(d$owner_zip_income, big.mark = ","), `Property ZIP income` = format(d$property_zip_income, big.mark = ","),
               `Owner ZIP 25%+ richer` = paste0(d$pct_owner_zip_richer_25, "%"), check.names = FALSE) }, striped = TRUE, spacing = "xs")
  output$t_cond_rates <- renderTable({ req(cond_rates); d <- ord_rows(cond_rates[cond_rates$group %in% c(input$cond_group, "All rental buildings"), ])
    data.frame(` ` = d$value, Buildings = format(d$buildings, big.mark = ","), `Inside requests per 100 homes a year (rented or owner-occupied)` = d$inside_per_100_units_yr,
               `Buildings with an inside request` = paste0(d$pct_buildings_inside_request, "%"), `Outside requests per 100 buildings a year` = d$outside_per_100_buildings_yr, check.names = FALSE) },
    striped = TRUE, spacing = "xs")
  output$t_cond_models <- renderTable({ req(cond_models); d <- cond_models
    data.frame(Requests = sub("Requests about ", "", d$outcome), Portfolio = d$portfolio, Term = d$term, Ratio = sprintf("%.2f (%.2f-%.2f)", d$irr, d$lo, d$hi), p = format(d$p, digits = 2), check.names = FALSE) },
    striped = TRUE, spacing = "xs", caption = "Requests by the owner's portfolio size (rate ratios)", caption.placement = "top")
  output$t_ev_county <- renderTable({ req(ev_c); data.frame(Year = as.integer(ev_c$year), Filings = format(ev_c$filings, big.mark = ","), `Filing rate` = sprintf("%.1f", ev_c$filing_rate),
    `Judgments` = format(ev_c$judgments, big.mark = ","), `Judgment rate` = sprintf("%.1f", ev_c$judgment_rate), check.names = FALSE) }, striped = TRUE, spacing = "xs",
    caption = "Denver County, per 100 renter households", caption.placement = "top")
  output$ev_note <- renderText({ if (is.null(ev_s)) "Tract-level filings are not yet available here (the Eviction Lab tract file could not be downloaded), so the comparison with large owners is not shown." else "" })
  output$t_ev <- renderTable({ req(ev_s); data.frame(`Tracts by share of rentals held by 100+ unit owners` = ev_s$large_owner_tercile, Tracts = ev_s$tracts,
    `Filings a year` = format(ev_s$filings_per_year, big.mark = ","), `Filing rate (% of renter households)` = ev_s$filing_rate, Years = ev_s$years, check.names = FALSE) }, striped = TRUE, spacing = "s")
  output$t_ev_m <- renderTable({ req(ev_m); d <- ev_m[!ev_m$term %in% c("p_black", "p_hisp", "p_pov", "any_hidden", "any_known"), ]
    data.frame(Model = d$model, `Per point of share` = sprintf("%+.3f", d$estimate), p = format(d$p, digits = 2), Tracts = d$tracts, check.names = FALSE) }, striped = TRUE, spacing = "s")
  output$t_own_assoc <- renderTable({ req(own_assoc); lab <- c(pct_rental_owner_20plus = "Owners of 20+ units", pct_rental_owner_100plus = "Owners of 100+ units", pct_rental_company = "Companies", pct_rental_out_of_state = "Out of state")
    data.frame(`Share of rental units held by` = lab[own_assoc$outcome], `Tract characteristic` = own_assoc$term, Difference = sprintf("%+.2f", own_assoc$estimate), p = format(own_assoc$p, digits = 2), check.names = FALSE) },
    striped = TRUE, spacing = "s")
  output$t_s03_area <- renderTable({ req(s03_area); d <- s03_area
    data.frame(Area = d$area, Dwellings = format(d$dwellings, big.mark = ","), `Same block: hazardous` = paste0(d$pct_same_block_haz, "%"), `Same block: heavy` = paste0(d$pct_same_block_heavy, "%"),
               `Across the street: hazardous` = if (is.null(d$pct_across_street_haz)) "" else paste0(d$pct_across_street_haz, "%"),
               `Within 150 m: hazardous (incl. same block)` = paste0(d$pct_within_150_haz, "%"), `Facing industry` = format(d$facing_industry, big.mark = ","), check.names = FALSE) }, striped = TRUE, spacing = "s")
  output$s03_cov_txt <- renderText({ req(s03_cov); d <- s03_cov
    sprintf("Figures cover the %d of %d sheets placed on today's map: %s of %s dwellings read (%s%% in volume 1, where Auraria's vanished streets left fewer corners to match; %s%% in volume 2).",
            sum(d$sheets_placed), sum(d$sheets_read), format(sum(d$dwellings_on_placed_sheets), big.mark = ","), format(sum(d$dwellings_read), big.mark = ","),
            d$pct_dwellings_covered[d$volume == 1], d$pct_dwellings_covered[d$volume == 2]) })
  outputOptions(output, "s03_cov_txt", suspendWhenHidden = FALSE)
  output$t_s03_zone <- renderTable({ req(s03_zexp); d <- s03_zexp
    data.frame(`1903 situation` = d$exposure, `1929 zoning` = d$zone_1929, Dwellings = format(d$dwellings, big.mark = ","), `Share of group` = paste0(d$pct_of_exposure_group, "%"), check.names = FALSE) }, striped = TRUE, spacing = "s")
  output$t_s03_who <- renderTable({ req(s03_who); d <- s03_who
    data.frame(`1903 situation` = d$exposure, `Foreign-born` = paste0(d$pct_fb, "%"), Black = paste0(d$pct_black, "%"), Laborers = paste0(d$pct_laborers, "%"), `Owner households` = paste0(d$pct_owner_hh, "%"), check.names = FALSE) }, striped = TRUE, spacing = "s")
  output$t_s03_trades <- renderTable({ req(s03_trades); d <- head(s03_trades, 12); data.frame(Trade = d$trade, Blocks = d$N) }, striped = TRUE, spacing = "s", caption = "Most common trades", caption.placement = "top")
  output$t_rz_holc <- renderTable({ req(rz_holc); d <- rz_holc
    data.frame(`1938 HOLC grade` = d$holc, Changes = d$changes, `Residential to business or industry` = paste0(d$pct_res_to_business_or_industrial, "%"), `To residential` = paste0(d$pct_to_residential, "%"), check.names = FALSE) },
    striped = TRUE, spacing = "s", caption = "Where the zone map changed, 1925 to 1956 (rezonings, not annexations)", caption.placement = "top")
  output$t_rz_dir <- renderTable({ req(rz_dir); rz_dir }, striped = TRUE, spacing = "xs", caption = "Direction of change by period", caption.placement = "top")
  output$rz_note <- renderText({ req(rz_placed); paste0(sprintf("%d changes; %d placed on the map (%s at a subdivision block the ordinance names, or at street crossings that a named subdivision confirms). ", sum(rz_placed$changes), sum(rz_placed$changes[rz_placed$placed_by != "not placed"]),
    sum(rz_placed$changes[grepl("^subdivision and block", rz_placed$placed_by)]) + sum(rz_placed$checked_both_ways[rz_placed$placed_by == "street crossings"])),
    if (!is.null(rz_test)) { w <- rz_test[grepl("within periods", rz_test$period), ]
      sprintf("HOLC D vs A and B, share rezoned from residential to business or industry: Fisher's exact p = %s over the whole period; but such rezonings became more common after the war, when more of D's changes came, and comparing within each period (1925-45, 1946-54, 1955-56) the odds ratio is %s, p = %s, so the pattern is suggestive rather than settled. ",
              format(rz_test$p_all_placed[1], digits = 2), if (nrow(w)) sub(".*common odds ratio ([0-9.]+).*", "\\1", w$comparison[1]) else "?", if (nrow(w)) format(w$p_all_placed[1], digits = 2) else "?") } else "",
    "HOLC grades date from 1938, so changes before then are classed by the grade their area later received. Ordinances describe changes as written; the scans' text has errors, and a few changes could not be read or placed.") })
  output$t_s03_out <- renderTable({ req(s03_out); d <- head(s03_out, 8); data.frame(Trade = d$trade, Plants = d$plants) }, striped = TRUE, spacing = "s",
    caption = "Plants drawn on unplatted ground (rail yards, river bottoms, smelter and packing-house grounds), placed from their outlines", caption.placement = "top")
  output$t_s03_pers <- renderTable({ req(s03_pers); d <- s03_pers
    if (is.null(d$what)) { d$what <- "Blocks with a hazardous trade"; d$n <- d$hazardous_blocks_1903 }
    data.frame(`1903` = d$what, N = d$n, `With a 1965-92 hazardous-sector site within 150 m` = paste0(d$pct_with_1965_92_site_150m, "%"),
               `... on no current inventory` = paste0(d$pct_with_hidden_site_150m, "%"), `... on a current inventory` = paste0(d$pct_with_known_site_150m, "%"), check.names = FALSE) },
    striped = TRUE, spacing = "s", caption = "Did the same places stay industrial?", caption.placement = "top")
  output$p_hedonic <- renderPlotly({ req(hed); d <- hed[hed$model == input$hd_model & hed$sample == "All residential sales" & grepl("^Hidden|^Known|^Pre-1960", hed$kind) & hed$distance %in% c("0-200 m", "200-400 m", "400-800 m"), ]
    req(nrow(d)); cols <- c("Hidden (no current inventory)" = "#c2410c", "Known (on a current inventory)" = "#1d4ed8", "Pre-1960 hazardous trade" = "#6b7280")
    p <- plot_ly()
    for (k in names(cols)) { x <- d[d$kind == k, ]; if (!nrow(x)) next
      p <- add_trace(p, x = x$distance, y = x$pct, type = "scatter", mode = "markers", name = k, marker = list(color = cols[[k]], size = 10),
                     error_y = list(type = "data", symmetric = FALSE, array = x$hi - x$pct, arrayminus = x$pct - x$lo, color = cols[[k]]),
                     text = sprintf("%s, %s: %+.1f%% (%.1f to %.1f), p = %s", k, x$distance, x$pct, x$lo, x$hi, x$p), hoverinfo = "text") }
    layout(p, yaxis = list(title = "% difference in sale price", zeroline = TRUE), xaxis = list(title = "distance from the nearest site", categoryorder = "array",
                                                                                                categoryarray = c("0-200 m", "200-400 m", "400-800 m")),
           legend = list(orientation = "h", y = -0.25), margin = list(t = 10)) |> config(displayModeBar = FALSE) })
  output$t_hedonic <- renderTable({ req(hed); d <- hed[hed$model == "M6 within 400 m (pooled)", ]; req(nrow(d))
    data.frame(`Site within 400 m` = d$kind, `Price difference` = sprintf("%+.1f%%", d$pct), `95% CI` = sprintf("%.1f to %.1f", d$lo, d$hi), p = format(d$p, digits = 2),
               Sales = format(d$n, big.mark = ","), check.names = FALSE) }, striped = TRUE, spacing = "s")
  output$t_cx_rod <- renderTable({ req(rod); data.frame(Neighbourhood = rod$neighborhood, `Yards sampled` = format(rod$properties_sampled, big.mark = ","), `Lead 95th pct` = rod$lead_95th_pct_ppm, `Lead max` = rod$lead_max_ppm,
                                                        `Arsenic 95th pct` = rod$arsenic_95th_pct_ppm, `Arsenic max` = rod$arsenic_max_ppm, check.names = FALSE) }, striped = TRUE, spacing = "xs", digits = 0)
  output$t_hw_tr <- renderTable({ req(hw_tr); d <- hw_tr; data.frame(Tracts = d$crossed, n = d$tracts, Census = d$census, Residents = format(d$residents, big.mark = ","), `Population (1950 = 100)` = d$pop_index_1950_100, `% Hispanic` = ifelse(is.na(d$pct_hispanic) | is.nan(d$pct_hispanic), "\u2013", d$pct_hispanic), `% Black` = d$pct_black, `% owner-occupied` = d$pct_owner_occupied, check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "xs")
  Z23_CATS <- c("Industrial (housing not allowed)" = "#7a0177", "Industrial mixed use (housing allowed)" = "#c51b8a", "Mixed use with housing" = "#fa9fb5",
                "Residential" = "#fdd0a2", "Commercial" = "#9ecae1", "Open space, civic, other" = "#c7e9c0")
  output$t_z29 <- renderTable({ req(z23_29); d <- z23_29[match(c("Industrial A", "Industrial B", "Commercial"), z23_29$zone1929), ]
    SH <- c("Industrial", "Industrial mixed use", "Mixed use with housing", "Residential", "Commercial", "Other")
    out <- data.frame(`1929 district` = d$zone1929, `Area (sq km)` = sprintf("%.1f", d$km2_1929), check.names = FALSE)
    for (i in seq_along(Z23_CATS)) out[[SH[i]]] <- sprintf("%.0f%%", d[[names(Z23_CATS)[i]]]); out }, striped = TRUE, spacing = "s")
  output$p_zsites <- renderPlotly({ req(z23_s, z23_d)
    a <- z23_s[z23_s$where != "Study area", ]; a$row <- paste0(ifelse(grepl("^Hazardous-sector", a$series), "1965–92 sites", "Pre-1960 trades"), ", ", ifelse(a$where == "Denver County", "Denver County", "suburbs"), " (", a$n, ")")
    b <- z23_d; b$row <- paste0("1965–92 sites last listed ", b$last_decade, " (", b$n, ")")
    d <- rbind(a[, c("row", names(Z23_CATS))], b[, c("row", names(Z23_CATS))]); d$row <- factor(d$row, levels = rev(d$row)); pl <- plot_ly()
    for (k in names(Z23_CATS)) pl <- pl |> add_trace(y = d$row, x = d[[k]], type = "bar", orientation = "h", name = k, marker = list(color = Z23_CATS[[k]]),
                                                   text = sprintf("%s: %.1f%%", k, d[[k]]), hoverinfo = "text", textposition = "none")
    layout(pl, barmode = "stack", xaxis = list(title = "% of sites", range = c(0, 100)), yaxis = list(title = ""), legend = list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom", traceorder = "normal"), margin = list(l = 10, t = 10)) })
  output$t_ztr <- renderTable({ req(z23_t); d <- z23_t
    data.frame(`2023 industrial share of the tract` = d$group, Tracts = d$tracts, Residents = format(d$residents, big.mark = ","), `% Hispanic` = d$pct_hispanic, `% Black` = d$pct_black,
               `% White` = d$pct_white, `% foreign born` = d$pct_foreign_born, `% in poverty` = d$pct_poverty, `% owner-occupied` = d$pct_owner_occupied, check.names = FALSE) }, digits = 1, striped = TRUE, spacing = "s")
  output$t_sf_zone <- renderTable({ if (is.null(sf_zone)) return(NULL); sf_zone |> transmute(Series = ifelse(grepl("Manufact", series), "1965-92 sites", "1891-1956 trades"), Sites = n, `Zoned industrial %` = pct_zone_industrial, `Rebuilt %` = pct_redeveloped, `Median year built` = as.integer(median_year_built)) }, striped = TRUE, spacing = "xs")
  output$t_sf_dec <- renderTable({ if (is.null(sf_sum)) return(NULL); ser <- if (identical(input$sf_series, "H")) "Business" else "Manufact"
    # Sites: every site last listed in that decade (matched or not), the base of the percentages
    d <- sf_sum |> filter(grepl(ser, series)) |> group_by(last_decade) |> mutate(sites = sum(n)) |> ungroup() |> filter(use_now %in% names(USE_COL)[1:6]) |> transmute(`Last listed` = last_decade, sites, use_now, pct) |> tidyr::pivot_wider(names_from = use_now, values_from = pct, values_fill = 0) |> arrange(`Last listed`)
    d |> rename(Sites = sites) }, striped = TRUE, spacing = "xs")
  # ---- benchmarks
  observe({ if (!is.null(bm_cty)) updateSelectInput(session, "bm_year", choices = sort(unique(bm_cty$year), decreasing = TRUE), selected = 1990) })
  output$p_bm_state <- renderPlotly({ if (is.null(bm_state)) return(NULL); h <- isTRUE(input$bm_haz)
    d <- bm_state |> transmute(year, CBP = if (h) cbp_haz else cbp_mfg, Directory = if (h) dir_haz else dir_mfg) |> tidyr::pivot_longer(-year, names_to = "series", values_to = "n") |> filter(!is.na(n))
    ggplotly(ggplot(d, aes(year, n, colour = series, group = series, text = sprintf("%s %s: %s", series, year, format(n, big.mark = ",")))) + geom_line() + geom_point(size = 2) + scale_colour_manual(values = c(CBP = "#2c7fb8", Directory = "#d1491f")) + expand_limits(y = 0) +
               labs(x = NULL, y = if (h) "Hazardous-sector establishments" else "Manufacturing establishments", colour = NULL) + theme_minimal(), tooltip = "text") |> hleg() })
  output$t_bm_fit <- renderTable({ if (is.null(bm_cty)) return(NULL); h <- isTRUE(input$bm_haz); d <- bm_cty |> filter(dir_all > 0) |> mutate(dir = if (h) dir_haz else dir_mfg, cbp = if (h) cbp_haz else cbp_mfg)
    f <- d |> group_by(Edition = year) |> summarise(`Directory` = sum(dir), CBP = sum(cbp), Ratio = round(sum(dir) / sum(cbp), 2), `r (log counts)` = round(cor(log1p(dir), log1p(cbp)), 2), .groups = "drop") |> mutate(Edition = as.integer(Edition))
    if (!is.null(bm_state) && "pages" %in% names(bm_state)) f <- f |> left_join(bm_state |> transmute(Edition = as.integer(year), `Pages scanned` = as.integer(pages), `No code (%)` = pct_no_code), by = "Edition"); f }, striped = TRUE, spacing = "xs")
  output$bm_fit_note <- renderUI(tags$small(class = "text-muted", "Correlation across the 64 counties of log establishment counts in the same year; the ratio is directory / CBP, statewide. ",
    "Only the complete editions are shown. The ratio follows scan density (22\u201346 listings per page; 1988 and 1992 were scanned at the lowest density) and the share of listings printed without an industry code (1977: 25%, 1992: 14%), which drop out of the sector counts. Edition-to-edition swings are therefore largely scan coverage, not industrial change."))
  output$p_bm_cty <- renderPlotly({ if (is.null(bm_cty) || is.null(input$bm_year) || input$bm_year == "") return(NULL); h <- isTRUE(input$bm_haz)
    d <- bm_cty |> filter(year == as.integer(input$bm_year)) |> mutate(dir = if (h) dir_haz else dir_mfg, cbp = if (h) cbp_haz else cbp_mfg)
    ggplotly(ggplot(d, aes(cbp, dir, text = sprintf("%s: CBP %d, directory %d (%d at a street address)", county_name, cbp, dir, dir_street))) + geom_abline(slope = 1, intercept = 0, colour = "grey60", linetype = "dashed") + geom_point(colour = "#d1491f", alpha = 0.8, size = 2.5) +
               scale_x_log10() + scale_y_log10() + labs(x = "CBP establishments (log scale)", y = "Directory establishments (log scale)") + theme_minimal(), tooltip = "text") })
  output$t_bm_cty <- renderTable({ if (is.null(bm_cty) || is.null(input$bm_year) || input$bm_year == "") return(NULL); h <- isTRUE(input$bm_haz)
    bm_cty |> filter(year == as.integer(input$bm_year)) |> arrange(desc(cbp_mfg)) |> head(12) |> transmute(County = county_name, CBP = if (h) cbp_haz else cbp_mfg, Directory = if (h) dir_haz else dir_mfg, `Street-level` = dir_street, Ratio = round(Directory / pmax(CBP, 1), 2)) }, striped = TRUE, spacing = "xs")
  output$t_bm_at <- renderTable({ if (is.null(bm_at)) return(NULL); bm_at |> filter(year == 1880) |> transmute(Sector = ifelse(hazardous, paste0(sector, " *"), sector), Establishments = as.integer(establishments), Workers = as.integer(workers), `Capital ($)` = format(round(capital), big.mark = ",")) }, striped = TRUE, spacing = "xs")
  output$bm_nh <- renderUI({ if (is.null(bm_nh)) return(tags$small(class = "text-muted", "Not yet built: run Rscript R/benchmarks.R with an NHGIS key to add the 1880-1940 comparison."))
    d <- bm_nh |> group_by(Census = as.integer(census)) |> summarise(Counties = n(), `Census mfg. establishments` = sum(mfg_estab, na.rm = TRUE), `Directory hazardous trades` = sum(dir_haz), `r (log)` = round(cor(log1p(mfg_estab), log1p(dir_haz)), 2), .groups = "drop")
    HTML(renderTable(d, striped = TRUE, spacing = "xs")()) })
  output$t_holc_m <- renderTable({ if (is.null(holc_m)) return(NULL)
    holc_m |> filter(outcome == input$rl_mvar) |> mutate(star = ifelse(p < 0.01, "**", ifelse(p < 0.05, "*", "")), Outcome = c(p_black = "Black %", p_hisp = "Hispanic %", p_pov = "Poverty %", p_owner = "Owner-occupied %", lmval = "log median home value (2020 $)")[outcome]) |>
      transmute(Outcome, Period = period, `Class (vs A)` = grade, Change = sprintf("%+.1f%s", b, star), SE = round(se, 1), Tracts = n,
                `Net of 1925 zoning` = if ("b_zone" %in% names(holc_m)) ifelse(is.na(b_zone), "", sprintf("%+.1f%s", b_zone, ifelse(p_zone < 0.01, "**", ifelse(p_zone < 0.05, "*", "")))) else NULL) }, striped = TRUE, spacing = "xs")
  output$t_zon44 <- renderTable({ req(zg44); d <- zg44[zg44$grade %in% c("A", "B", "C", "D"), ]
    data.frame(Grade = d$grade, District = d$cls, `% of grade, 1929` = d$pct_1929, `% of grade, 1944` = d$pct_1944, `km², 1929` = d$km2_1929, `km², 1944` = d$km2_1944, check.names = FALSE) }, digits = 2, striped = TRUE, spacing = "xs")
  output$t_zch <- renderTable({ req(zch_t); d <- zch_t
    data.frame(`1929` = d$from_1929, `1944` = d$to_1944, `km²` = d$km2, `HOLC grade` = d$holc_grade, Near = d$near, check.names = FALSE) }, digits = 3, striped = TRUE, spacing = "xs")
  output$t_holc_zon <- renderTable({ if (is.null(zon_g)) return(NULL); zon_g |> transmute(Grade = grade, Areas = areas, `km²` = km2, `Zoned industrial in 1929 (%)` = pct_industrial_1929, `Zoned commercial (%)` = pct_commercial_1929) }, striped = TRUE, spacing = "xs")

  # ---- downloads
  output$dl_one <- downloadHandler(filename = function() if (as.integer(input$dl_year) < 1960) sprintf("CO_business_directory_%s_hazardous_trades.csv", input$dl_year) else sprintf("CO_DCM_%s_geocoded.csv", input$dl_year),
                                   content = function(f) { y <- as.integer(input$dl_year)
                                     if (y < 1960) write.csv(pre60[pre60$year == y, ], f, row.names = FALSE) else file.copy(file.path(by_year_dir, sprintf("CO_DCM_%s_geocoded.csv", y)), f) })
  output$t_edcov <- DT::renderDataTable({ if (is.null(edcov)) return(NULL)
    DT::datatable(edcov |> transmute(Series = series, Edition = as.integer(year), `Scanned pages` = as.integer(pages), Listings = as.integer(listings), `Hazardous firms` = as.integer(hazardous), `Street-level (%)` = street_level_pct, `No code (%)` = no_code_pct, Complete = ifelse(complete %in% c(TRUE, "TRUE"), "yes", "NO"), Note = note),
                  rownames = FALSE, options = list(pageLength = 12, scrollX = TRUE, order = list(list(1, "asc"))), class = "compact stripe") |> DT::formatStyle("Complete", target = "row", backgroundColor = DT::styleEqual("NO", "#fff3cd")) })
  output$dl_btns <- renderUI({ n <- format(nrow(sel_sites()), big.mark = ",")
    tagList(downloadButton("dl_sites", sprintf("Download the %s sites matching the sidebar filters", n)), br(), br(),
            downloadButton("dl_firms", sprintf("Download firms at those %s sites", n)), br(), br()) })
  output$dl_sites <- downloadHandler(filename = function() "CO_hazardous_sites_filtered.csv",
                                     content = function(f) write.csv(sel_sites(), f, row.names = FALSE))
  output$dl_firms <- downloadHandler(filename = function() "CO_firms_at_hazardous_sites_filtered.csv",
    content = function(f) write.csv(if (is.null(firms)) data.frame() else firms[firms$site_id %in% sel_sites()$site_id, ], f, row.names = FALSE))
  output$dl_hist <- downloadHandler(filename = function() "CO_pre1960_hazardous_sites.csv",
                                    content = function(f) write.csv(if (is.null(hist)) data.frame() else hist, f, row.names = FALSE))
  output$geo_note <- renderUI(HTML(paste0(
    "<p>Addresses were OCR'd from scanned directories and geocoded offline against US Census TIGER/Line 2023 address ranges. ",
    "<b>address</b> = house number interpolated on the matching street segment; <b>address_approx</b> = street found only after OCR correction, ",
    "in a neighbouring ZIP, or at the nearest segment end (check before field work). Listings that could only be placed at a ZIP or city ",
    "centroid are in the edition CSVs but not on the map.</p>",
    "<p><b>Checked three ways (Oct 2026).</b> (1) Against Colorado's statewide address points (rooftop/parcel locations, independent of ",
    "TIGER) for 1,000 random sites: address-level points median 49 m away, 94% within 250 m, 0.9% over 1 km; approximate points median 103 m, ",
    "75% within 250 m, 10% over 1 km; a re-check on the final data (400 sites) gave 88% within 250 m and 3.8% over 1 km at address level, the misses being ",
    "Denver addresses printed without a direction (N vs S), which are now counted as approximate. (2) Against EPA Facility Registry coordinates for identical addresses (table below). (3) Against the scans: ",
    "about 1 in 25 house numbers carries an OCR digit error. Misread house numbers and streets renumbered since the 1960s are the main error sources.</p>",
    "<p><b>Pre-1960 layer.</b> Business-directory entries are placed at a street address only for Denver from 1891 (after the city's 1887 ",
    "renumbering) and for larger cities from 1910, and only when the house number falls inside a current TIGER address range; old street names ",
    "(e.g. Holladay → Market) are translated. Everything else sits at the USGS GNIS point for the town and is drawn as a cluster. ",
    "Where a pre-1960 firm reappears in the 1965–1992 directory with an address, that address is used.</p>")))
  output$valid <- renderTable(validation)
}

shinyApp(ui, server)
