# Colorado Hidden Hazards — explore historical hazardous manufacturing sites (Colorado Directory of Manufacturers,
# 1961–2002, and hazardous trades in Colorado State Business Directories, 1871–1956), current EPA TRI facilities, cleanup sites, schools and health facilities, and CDPHE EnviroScreen 2.0.
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
ej_mod   <- rd_opt("ej_panel_models.csv"); ej_rev <- rd_opt("ej_panel_reverse.csv"); ej_dec <- rd_opt("ej_panel_by_decade.csv")
cells    <- rd_opt("corridor_cells.csv"); eg <- rd_opt("corridor_eg.csv"); trans <- rd_opt("corridor_transitions.csv")
ed80     <- rd_opt("denver_1880_eds.csv"); ed80_poly <- if (file.exists(dd("denver_1880_eds.geojson"))) st_read(dd("denver_1880_eds.geojson"), quiet = TRUE) |> mutate(ED = as.integer(ED)) else NULL; f80 <- rd_opt("denver_1880_firms.csv"); d80 <- rd_opt("denver_1880_distance.csv"); m80 <- rd_opt("denver_1880_models.csv"); g80 <- rd_opt("denver_1880_ed_groups.csv")
city1880 <- rd_opt("denver_city_1880_1940.csv")
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
               pct_boarders = "Boarders and lodgers (% of population)", pct_group_quarters = "In group quarters (%)", pct_movers = "Moved since 1935 (%)", pct_movers_other_state = "Moved from another state since 1935 (%)",
               pct_veterans = "Veterans (% of adults)", children_per_mother = "Children ever born per mother", firms = "Hazardous firms in the decade", dist_m = "Distance to nearest firm (m)")
ED_VARS  <- c("Black (%)" = "pct_black", "Foreign born (%)" = "pct_fb", "Mexican-born (%)" = "pct_fb_mexico", "Hispanic (%)" = "pct_hisp", "Laborers (% of population)" = "pct_laborers",
              "Foreign or mixed parentage (%)" = "pct_foreign_parentage", "Hazardous firms in the decade" = "firms", "Distance to nearest firm (m)" = "dist_m")   # replaced by whatever the district file provides
if (!is.null(eds)) { have <- names(ED_LABELS)[names(ED_LABELS) %in% names(eds)]; have <- have[sapply(have, function(k) any(!is.na(eds[[k]])))]; if (length(have)) ED_VARS <- setNames(have, ED_LABELS[have]) }
holc     <- if (file.exists(dd("holc_denver.geojson"))) st_read(dd("holc_denver.geojson"), quiet = TRUE) else NULL      # R/holc_covenants.R
coven    <- rd_opt("covenants_denver.csv"); holc_bd <- rd_opt("holc_boundary.csv"); holc_gap <- rd_opt("holc_gaps.csv"); holc_ind <- rd_opt("holc_industry_periods.csv"); bm_state <- rd_opt("cbp_vs_directory_state.csv"); bm_cty <- rd_opt("cbp_vs_directory_county.csv"); bm_nh <- rd_opt("nhgis_mfg_vs_directory.csv"); bm_at <- rd_opt("atack_colorado_by_sector.csv"); edcov <- rd_opt("edition_coverage.csv"); holc_g <- rd_opt("holc_by_grade.csv"); holc_tr <- rd_opt("trajectories_by_grade.csv"); holc_pre <- rd_opt("trajectories_pre_by_grade.csv"); holc_m <- rd_opt("holc_tract_models.csv"); holc_sh <- rd_opt("holc_facility_shares.csv"); ed_sh <- rd_opt("ed_firm_shares.csv"); ed_cls <- rd_opt("ed_holc_classes.csv")
# 1925 zoning ordinance as mapped in 1929 (R/zoning_1925.R) and what became of the Denver sites (R/site_fate.R)
zon      <- if (file.exists(dd("zoning_1929.geojson"))) st_read(dd("zoning_1929.geojson"), quiet = TRUE) else NULL; zon_g <- rd_opt("holc_zoning_by_grade.csv")
ZON_COL  <- c("Industrial A" = "#b2182b", "Industrial B" = "#762a83", "Commercial" = "#e6ab02")
sf_sum   <- rd_opt("site_fate_summary.csv"); sf_zone <- rd_opt("site_fate_zoning.csv"); sf_den <- rd_opt("site_fate_denver.csv"); sf_pre <- rd_opt("site_fate_denver_pre1960.csv")
USE_COL  <- c("Industrial / utility" = "#636363", "Commercial / office" = "#e6ab02", "Residential" = "#d7301f", "Vacant" = "#bdbdbd", "Civic / school / health" = "#1f78b4", "Park / open space" = "#33a02c", "Other" = "#f0f0f0", "No parcel match" = "#ffffff")
eds_holc <- if (file.exists(dd("eds_holc_1930.geojson"))) st_read(dd("eds_holc_1930.geojson"), quiet = TRUE) else NULL
HOLC_COL6 <- c(A = "#76a865", B = "#7cb5bd", C = "#ffff00", D = "#d9838d", Industrial = "#8c8c8c", Commercial = "#c8a2c8", ungraded = "#eeeeee")
HOLC_COL <- c(A = "#76a865", B = "#7cb5bd", C = "#ffff00", D = "#d9838d")
PAN_YEARS <- c(if (!is.null(co_cnty)) c(1880, 1900, 1910, 1920, 1930), seq(1940, 2020, 10))
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
hleg <- function(p) plotly::layout(p, legend = list(orientation = "h", x = 0, y = -0.32, yanchor = "top"), margin = list(b = 120))   # horizontal legend clear of the axis title

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
      "Each 1961–2002 directory listing carries its own SIC/NAICS code, so a site is in a sector if any firm listed at the address had that code. ",
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
           "'No match in searched inventories' (stored as 'Not on any list' in the downloads) = no match by location (40\u201375 m), address or name in EPA FRS, TRI, RCRA, Superfund, brownfield or CDPHE cleanup inventories; geocoding error of tens of metres can move a site across those thresholds, so it is a lead, not a finding.")
)

ui <- page_navbar(id = "nav",
  title = "Colorado Hidden Hazards", fillable = "Map",   # other tabs scroll so their plots keep full height
  theme = bs_theme(version = 5, bootswatch = "flatly", primary = "#24589e", base_font = font_google("Public Sans", local = FALSE)),
  header = tags$style(HTML(".leaflet .info.legend { font-size: 11px; line-height: 1.25; max-width: 260px; } .leaflet-control-layers { font-size: 11.5px; } .leaflet-top.leaflet-left .info.legend { margin-top: 6px; } @media (max-width: 900px) { .leaflet-control-layers-expanded { display: none; } }")),
  sidebar = sidebar(width = 300,
    conditionalPanel("['Map','Trends','Census tracts over time','Neighborhoods','Nearby schools & health care','Data & downloads'].includes(input.nav)", do.call(tagList, filters)),
    conditionalPanel("!['Map','Trends','Census tracts over time','Neighborhoods','Nearby schools & health care','Data & downloads'].includes(input.nav)",
      tags$small(class = "text-muted", "The site filters apply to the Map, Trends, Census tracts, Neighborhoods, Nearby schools and Data tabs. This tab uses its own controls.")),
    conditionalPanel("input.nav == 'Census tracts over time'", tags$small(class = "text-muted", "On this tab the sector and status filters select the firms drawn on the map; the year slider is not used (each census shows the firms of its own decade), and the census charts are not filtered."))),
  nav_panel("Map",
    layout_columns(col_widths = c(9, 3),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map", height = "72vh"))),
      card(card_header("EnviroScreen layer"),
           selectInput("esvar", "Shade census tracts by", VARS, selected = "enviroscreen_pctl"),
           sliderInput("esop", "Opacity", 0, 1, 0.45, step = 0.05),
           hr(),
           tags$b("Sites shown"), textOutput("nsites"),
           tags$small(class = "text-muted",
             "Use the layer control (top right of the map) to add TRI facilities, schools, hospitals, clinics, ",
             "residential care, brownfields and other cleanup sites. Click any point for details."),
           tags$details(tags$summary(tags$small("What the map layers are")), tags$small(class = "text-muted", tags$dl(class = "mb-0",
             tags$dt("Historical hazardous sites"), tags$dd("Addresses of manufacturers in Frickel & Elliott's hazardous sectors from the 1961–2002 Directory of Colorado Manufacturers, filtered by the sidebar."),
             tags$dt("Pre-1960 hazardous trades"), tags$dd("Smelters, foundries, refineries, tanneries, gas works and similar trades in the 1871–1956 Colorado State Business Directory; street-level in Denver from 1891, otherwise one marker per town."),
             tags$dt("Industrial corridors"), tags$dd("500 m cells with any manufacturer 1961–2002, classed by persistence (definition on the Data & downloads tab)."),
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
    card(card_header("Hazardous-trade firms and sites listed, 1871\u20132002: both directory series on one timeline"),
         radioButtons("tl_mode", NULL, c("All editions (incomplete scans hollow)" = "all", "Complete editions only" = "complete"), inline = TRUE), plotlyOutput("p_timeline", height = 320),
         tags$small(class = "text-muted", "Brown: hazardous trades found in the Colorado State Business Directory (34 editions, every trade, OCR'd scans; counts depend on each edition's coverage and scan quality). Orange: hazardous-sector sites in the Directory of Colorado Manufacturers (25 editions, manufacturers only). The two series are not on the same footing \u2014 the business directories list far more small trades \u2014 but together they trace the whole span. Twelve of the 25 manufacturers' directory editions reached us as partial scans - typically the scan stops at Denver or Colorado Springs and the counties after them are missing - and are drawn hollow or dropped (complete: 1965-68, 1970, 1973-74, 1977, 1980, 1983, 1988, 1990, 1992); the Data & downloads tab lists what each edition contains. Both respond to the sidebar filters.")),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Hazardous-sector sites listed per directory edition, by sector"), plotlyOutput("p_sector", height = 420)),
      card(card_header("…by current regulatory status"), plotlyOutput("p_status", height = 420))),
    card(card_header("Share of listed sites on no current inventory"), plotlyOutput("p_share", height = 300)),
    tags$small(class = "text-muted", "Editions are irregular (25 between 1961 and 2002); only the 13 complete editions (1965\u201368, 1970, 1973\u201374, 1977, 1980, 1983, 1988, 1990, 1992) enter the site inventory."),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Phases of Colorado manufacturing: share of listed firms by industry, 1961–2002 (all manufacturers)"), plotlyOutput("p_mix", height = 420),
           tags$small(class = "text-muted", "* = Frickel & Elliott hazardous sector. Shares of firms with an industry code in each edition; the directories' coverage changes between editions.")),
      card(card_header("How long did firms stay listed?"), plotlyOutput("p_longev", height = 420),
           tags$small(class = "text-muted", "Years between a firm's first and last listing (firms linked across editions). Firms still listed in 2002 or first listed in 1961 are cut off by the directory's own span."))),
    card(card_header("Before 1960: hazardous-trade firms listed per Colorado State Business Directory edition"), plotlyOutput("p_hist", height = 360),
         tags$small(class = "text-muted", "Counts come from searchable text of the scanned directories and are not comparable to the manufacturers' directory: ",
                    "the business directories list every trade and their OCR quality varies by edition. 1891 and 1910–1939 include large Denver sections.")),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Do hazardous sectors cluster more than manufacturing in general? Ellison–Glaeser index by edition"),
           radioButtons("eg_scope", NULL, c("Denver metro (25 km)" = "Denver metro", "Statewide" = "statewide"), inline = TRUE), plotlyOutput("p_eg", height = 380),
           tags$small(class = "text-muted", "γ > 0: the sector is more concentrated across 1 km cells than all located manufacturers of that edition; filled points are significant at p < 0.05 (permutation test, 500 draws). ",
                      "Petroleum, printing and machinery are the consistently clustered sectors; chemicals and primary metals are few and scattered.")),
      card(card_header("Succession: what replaced what in 500 m cells (dominant sector, one edition to the next)"), plotlyOutput("p_trans", height = 380),
           tags$small(class = "text-muted", "The 15 most common changes of a cell's dominant sector between consecutive editions, 1961–2002. Cells are also drawn on the Map as 'Industrial corridors'.")))
    ),
  nav_menu("Historical change",
  nav_panel("Census tracts over time",
    layout_columns(col_widths = c(3, 9),
      card(card_header("Census tracts 1940–2020 vs. industry"),
           radioButtons("pan_year", "Decennial census (1880\u20131930 counties, 1940\u20132020 tracts)", choices = PAN_YEARS, selected = 1970, inline = TRUE),
           uiOutput("pan_avail"),
           radioButtons("pan_area", "Area", c("Colorado" = "co", "Denver core (185 tracts)" = "core"), inline = TRUE),
           selectInput("pan_var", "Shade tracts by", PAN_VARS, selected = "p_hisp"),
           checkboxInput("pan_firms", "Show hazardous firms active in the decade", TRUE),
           tags$small(class = "text-muted",
             if (!is.null(co_cnty)) "1880\u20131930 (and 1940 as a check) are counties, from the IPUMS full-count census files aggregated by county on that census's county boundaries, with all pre-1960 hazardous trades (street- or town-level) of the preceding decade. ",
             "1940\u20132020 tract values are from the decennial censuses (NHGIS), re-weighted by area onto 2010 tract boundaries. Only cities were tracted early: Denver in 1940 and 1950; the Denver, Boulder, Colorado Springs and Pueblo metros from 1960; Fort Collins, Greeley and Grand Junction from 1970–1980; the whole state from 1990. ",
             "Firms are the sites in the sidebar's sectors listed in a directory edition of the decade ending in the census year (1961–2002 manufacturers' directory; before 1961, street-level pre-1960 trades; 2000, 2010 and 2020 use the last complete decade, 1983–1992, so those columns measure proximity to historically listed sites). ",
             "Hispanic: Spanish surname (1960), Spanish American (1970), Spanish origin (1980), Hispanic (1990+); not available before 1960. Poverty: 1970+."),
           hr(), downloadButton("dl_panel", "Download tract panel CSV")),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map_den", height = "62vh")))),
    layout_columns(col_widths = c(6, 6),
      card(card_header(textOutput("pan_title")), plotlyOutput("p_pan", height = 380),
           tags$small(class = "text-muted", "Population-weighted means over the tracts with a census value that year (the tracted area grows over time; see the counts in the hover text). 'Legacy only' = tracts whose hazardous firms had all left by that decade.")),
      card(card_header("Panel models (Denver core): does industry predict who moves in, or do residents predict where industry goes?"), uiOutput("ej_models"),
           tags$small(class = "text-muted", "Hybrid (within/between) models after Marlow, Frickel & Elliott (2020), the 185 tracts of Denver and its first-ring suburbs within 10 km of downtown, 1970–2010, directory editions 1970/1980/1990/1999/2002, tract-clustered SE; the between part also as a spatial error model. Reproduce with Rscript R/ej_panel.R.")))
    ),
  nav_panel("Denver 1880–2020",
    layout_columns(col_widths = c(3, 6, 3),
      card(card_header("Denver by enumeration district (1880–1940) and census tract (1950–2020)"),
           radioButtons("ed_year", "Census", choices = c(if (is.null(eds)) 1880 else sort(unique(eds$year)), if (is.null(trd)) NULL else sort(unique(trd$census))), selected = 1880, inline = TRUE),
           uiOutput("ed_unit"),
           selectInput("ed_var", "Districts shaded by", ED_VARS, selected = "pct_fb"),
           checkboxInput("ed_firms", "Show hazardous-trade firms of the decade", TRUE),
           tags$small(class = "text-muted",
             "District boundaries are this project's reconstruction (see About the data): every household address in Brown University's Geographic Reference Files for Denver (1900–1940) ",
             "was geocoded with the project's offline TIGER geocoder and the districts drawn as the dissolved Voronoi cells of their addresses; 1880 uses Brown's geocoded buildings the same way. ",
             "Composition is the IPUMS full count aggregated by district. Firms: the hazardous trades of the business directories listed in the preceding decade, at their street address (1878–1885 firms on the 1880 grid for 1880). ",
             tags$b("From 1950 the unit changes to the census tract"), " (the 185 tracts of the Denver core on 2010 boundaries, earlier censuses interpolated), because census microdata are sealed for 72 years and the address files that let us draw districts stop at 1940. ",
             "The same analyses are run on tracts with the tract tables' measures (race, Hispanic origin, nativity, poverty, tenure, value, rent); firms of the decade are the manufacturers' directory sites from 1970 (2000, 2010 and 2020 use the last complete directory decade, 1983–1992)."),
           ),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map_1880", height = "70vh"))),
      card(card_header("Composition vs. distance to the nearest firm"), tableOutput("t_edm"),
           tags$small(class = "text-muted", "Percentage points per log-metre from the district or tract centroid to the nearest hazardous firm (population-weighted, robust SE; negative = higher near industry). 'pooled' = all censuses with census effects (1880–1940 districts and 1950–2020 tracts pooled separately). Value and rent enter as logs. ",
             "SEI = Duncan socioeconomic index (IPUMS): each occupation scored 0-96 from the income and education of its holders in 1950, the only income proxy available for every census. ",
             "'In hazardous industries' = share of a district's employed residents working in chemical, metal, petroleum and similar industries (IPUMS IND1950): if the people next to the plants were mainly their own workers this coefficient would be negative; it is nil or positive in every census, so the analysis finds no consistent negative association with hazardous-industry employment; it cannot establish where residents actually worked."),
           card_header("Dissimilarity across districts, 1880–1940"), plotlyOutput("p_city", height = 260),
           tags$small(class = "text-muted", "0 = evenly spread, 1 = complete separation (IPUMS full count; 1880 and 1900 Arapahoe County)."))),
    card(card_header(textOutput("edg_title")), tableOutput("t_edg"),
         tags$small(class = "text-muted", "Population-weighted means of the district composition (IPUMS full count). The last row is the dissimilarity index of each group against the rest of the population across all mapped districts (0\u20131).")),
    card(card_header("Where the firms were: share of each decade's hazardous firms in the districts (1880–1940) or tracts (1950–2020) housing the top population quartile on each measure"), plotlyOutput("p_ed_sh", height = 340),
         tags$small(class = "text-muted", "Districts or tracts are ranked on the measure and the top 25% of the population taken; if firms were spread like people, 25% (dashed line) would fall there. Hover for the share in the bottom quartile. The grey line marks the change of unit.")),
    layout_columns(col_widths = c(4, 8),
      card(card_header("1880 at the building level (Brown University Urban Transition HGIS)"),
           tags$small(class = "text-muted", "The 1880 census geocoded to buildings against the hazardous trades of the 1878–1885 directories placed on the 1880 street grid: 34,386 residents, 60 firms at the building. Only aggregates and model results are shown; Brown's building-level data are not redistributed."),
           hr(), tags$b("Residents by distance to the nearest hazardous firm"), tableOutput("t_d80"),
           tags$b("Enumeration districts with vs. without a hazardous firm (Brown's ED composition)"), tableOutput("t_g80")),
      card(card_header("Person-level odds of living farther from a hazardous firm (1880)"), tableOutput("t_m80"),
           tags$small(class = "text-muted", "Odds ratio per log-metre of distance (> 1 = more common farther away), building-clustered SE. Foreign-born (German, Canadian, other), Black and Chinese residents lived closer; native-born whites, British- and Scandinavian-born lived farther; employed adults' SEI rose with distance; unskilled laborers (SEI 8) were, on average, farther out.")))
    ),
  nav_panel("What became of the sites",
    layout_columns(col_widths = c(3, 6, 3),
      card(card_header("Denver's historical hazardous sites on today's parcels"),
           radioButtons("sf_series", "Sites", c("Manufacturers' directory sites, complete editions 1965–1992" = "S", "Business-directory hazardous trades 1891–1956 (street level)" = "H")),
           checkboxGroupInput("sf_use", "Current parcel use", choices = names(USE_COL)[1:6], selected = names(USE_COL)[1:6]),
           checkboxInput("sf_sens", "Only residential, school, park or health parcels with no matching cleanup record", FALSE),
           tags$small(class = "text-muted", "Each geocoded site is matched to the nearest City and County of Denver assessor parcel within 40 m (1,256 of 1,258 points; median distance 10 m) through Denver's open-data parcel service, which gives the assessor's property class, the current zone district, dwelling units and the year the present building was built (R/site_fate.R). ",
             "A geocoded street address can land on a neighbouring lot where parcels have been consolidated or split, so individual matches should be checked against the Sanborn sheets and reverse directories before being cited. ",
             "'No matching cleanup record' means the site matched no record in the inventories this project searched (EPA FRS/SEMS/RCRA, CDPHE VCUP, environmental covenants); it does not establish that a site was never assessed or remediated.")),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map_sf", height = "62vh"))),
      card(card_header("Current use of the former sites"), plotlyOutput("p_sf_use", height = 300), tableOutput("t_sf_zone"),
           tags$small(class = "text-muted", "Share of each series' sites by the assessor's current property class. 'Rebuilt' = the present building is newer than the site's last directory listing (a redevelopment indicator, not a closure date); 'zoned industrial' = I-A, I-B or I-MX districts of the 2010 code."))),
    card(card_header("Current use by the decade a site was last listed"), tableOutput("t_sf_dec"),
         tags$small(class = "text-muted", "Sites that left the directory earlier have had longer to be converted, so the rows are not a conversion rate; they show what stands today on the sites of each cohort. The 1990s row is the sites still listed in 1990 or 1992, the last complete editions."))),
  nav_panel("Redlining & covenants",
    layout_columns(col_widths = c(3, 6, 3),
      card(card_header("HOLC 1938 map and racial covenants 1931\u201335"),
           checkboxGroupInput("rl_layers", NULL, c("HOLC security grades (1938)" = "holc", "1925 zoning ordinance: industrial and commercial districts (1929 map)" = "zon", "Racial covenants 1931-35 (deeds)" = "cov", "Hazardous-trade firms" = "firms", "1930 enumeration districts" = "ed30"),
                              selected = c("holc", "cov", "firms")),
           conditionalPanel("input.rl_layers.includes('zon')", tags$small(class = "text-muted", "Denver's first zoning ordinance (February 1925) as shown on the official Building Zone Map revised to January 1929 (Denver Public Library, CG4314 .D4 G44 1929), georeferenced from 13 street intersections (RMSE 25 m) and classified by hatch pattern: Industrial A, Industrial B and Commercial districts; everything else was Residence A–E or Business. Residence E (apartments) shares a hatch with Industrial A and is told apart only by lot lines, so a few platted blocks are uncertain (R/zoning_1925.R).")),
           conditionalPanel("input.rl_layers.includes('ed30')", selectInput("rl_edvar", "Shade 1930 districts by", c("Black (%)" = "pct_black", "Hispanic (%)" = "pct_hisp", "Foreign born (%)" = "pct_fb", "Laborers (%)" = "pct_laborers",
                                                                                 "Racial covenants recorded 1931-35" = "covenants", "HOLC class of the district (1938)" = "grade", "Hazardous firms before the map (to 1937)" = "firms_pre1938", "Hazardous firms after the map (1938-56)" = "firms_1938_1956", "Hazardous-sector sites 1961-2002" = "firms_1961_2002"))),
           conditionalPanel("input.rl_layers.includes('firms')", radioButtons("rl_firms", "Hazardous-trade firms listed (orange-red dots)", c("Before the map: 1871-1937 (street level)" = "pre", "1921-1937 only" = "mid", "After the map: 1938-1956" = "post"), selected = "pre")),
           tags$small(class = "text-muted",
             "The Home Owners' Loan Corporation graded Denver's neighbourhoods A (\u2018best\u2019) to D (\u2018hazardous\u2019) in 1938; its appraisers' forms record what they saw as detrimental influences, the share of foreign-born and Black families and any \u2018infiltration\u2019. ",
             "Click an area for its description. Racial covenants are deeds recorded 1931\u201335 that barred non-white occupants (Denver Public Library's Mapping Prejudice pilot); some also barred manufacturing. ",
             "Xu (2022) showed for Chicago that HOLC's maps were post-hoc appraisals while the FHA's map drove lending; we have not located a surviving Denver FHA mortgage-risk map, so the question here is what the HOLC grades ratified: the 1900\u20131940 districts show who already lived next to industry before the map was drawn, and the 1940\u20132020 panel what followed."),
           ),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map_rl", height = "62vh"))),
      card(card_header("After the map: 2010 tracts by dominant HOLC grade, 1940\u20132020"),
           selectInput("rl_var", NULL, c("Hispanic (%)" = "p_hisp", "Black (%)" = "p_black", "Foreign born (%)" = "p_fb", "Below poverty (%)" = "p_pov", "Owner-occupied (%)" = "p_owner", "Median home value (2020 $)" = "mval_2020", "Median rent (2020 $)" = "mrent_2020", "Hazardous firms in decade" = "firms_haz"), selected = "p_hisp"),
           plotlyOutput("p_holc_tr", height = 300),
           tags$small(class = "text-muted", "Dashed, 1900-1940: the reconstructed enumeration districts of each census area-weighted into the HOLC polygons themselves (fixed boundaries, so no harmonisation; the only approximation is the area weighting). ",
             "Solid, 1940-2020: population-weighted means of 2010 tracts at least 40% inside graded areas (4 A, 6 B, 41 C, 19 D tracts), with earlier censuses interpolated to 2010 tracts. The two 1940 points show how much the change of unit matters. Vertical line: the 1938 map. ",
             "Gaps: no census tract table measures Hispanic origin before 1960 (the 1900-1940 values are the full count's HISPAN; the 1940 tract point is filled from the districts), poverty starts in 1970, and 'hazardous firms in decade' counts street-level directory firms active in the ten years to each census."),
           )),
    card(card_header("1930 enumeration districts by HOLC class and covenants: who lived there, and industry before and after the map"), tableOutput("t_edcls"),
         tags$small(class = "text-muted", "Each 1930 district takes the HOLC class covering most of its area ('ungraded' = outside all HOLC areas); 'covenants' = at least one 1931-35 racial covenant deed inside it. Firms per 10,000 residents of 1930. HOLC's Industrial and Commercial zones carried no residential grade but held most of the pre-map industry.")),
    layout_columns(col_widths = c(7, 5, 5, 7),
      card(card_header("HOLC areas by grade: industry, the appraisers' remarks, covenants, and who lived there (1930 and 1940 full count, reconstructed districts)"), tableOutput("t_holc_g"),
           tags$small(class = "text-muted", "Population-weighted; 'remarks cite industry' = the area's detrimental influences or remarks mention industry, factories, smelters, railroads, smoke or odors. Firms are the street-level hazardous trades of the business directories; 'before the map' = any listing 1871-1937.")),
      card(card_header("Where the facilities are: share by HOLC grade, then and now"), plotlyOutput("p_holc_sh", height = 360),
           tags$small(class = "text-muted", "Share of each layer's facilities that fall inside HOLC's A-D residential grades and its ungraded Industrial and Commercial zones (facilities outside all HOLC areas excluded), against the classes' shares of land and of 1940 population. Hazardous trades: street-level business-directory listings; 1961-2002: this project's geocoded hazardous-sector sites; today: EPA TRI and the cleanup inventories.")),
      card(card_header("Mortgage lending today by HOLC grade: HMDA 2018-21 home-purchase applications"), tableOutput("t_hmda"), uiOutput("hmda_note"),
           tags$small(class = "text-muted", "2010 tracts by dominant HOLC grade; denial rate = denied / (originated + denied), so withdrawn and incomplete applications are excluded. Context for the 1938 map, not evidence that its classifications were implemented: who gets credit in the graded areas today. Source: CFPB HMDA data browser (R/fetch_hmda.R).")),
      card(card_header("Change in tract outcomes by grade, A = reference"), selectInput("rl_mvar", "Outcome", c("Black %" = "p_black", "Hispanic %" = "p_hisp", "Poverty %" = "p_pov", "Owner-occupied %" = "p_owner", "log median home value (2020 $)" = "lmval")), tableOutput("t_holc_m"),
           tags$small(class = "text-muted", "Percentage points over the period relative to tracts dominated by A areas; the period's starting value of the outcome, 1940 % Black and 1931-40 firms controlled (poverty is first measured in 1970, so its periods start in 1970); 'net of 1925 zoning' adds the tract's share zoned industrial in 1929; HC1 SE, no spatial adjustment. ** p<0.01, * p<0.05. Industrial and Commercial = tracts at least 40% inside HOLC's ungraded zones of that kind (few tracts, so wide SEs). Compare Xu (2022), Table 3, for Chicago."))),
    layout_columns(col_widths = c(7, 5),
      card(card_header("Did the map create or reinforce? The D–C gap census by census, 1900–2020"),
           layout_columns(col_widths = c(4, 3, 5), selectInput("rl_bvar", "Outcome", c("Black (%)" = "p_black", "Hispanic (%)" = "p_hisp", "Foreign born (%)" = "p_fb", "Owner-occupied (%)" = "p_owner", "Below poverty (%)" = "p_pov", "Laborers (%)" = "p_laborers")),
                          selectInput("rl_pair", "Grades", c("D minus C" = "D-C", "D minus B" = "D-B", "D minus A" = "D-A", "C minus B" = "C-B", "C minus A" = "C-A", "B minus A" = "B-A")),
                          radioButtons("rl_bdes", "Comparison", c("Boundary band: units within 400 m (districts) / 800 m (tracts) of both grades, lying in one of them" = "band", "All areas of each grade" = "all"))),
           uiOutput("holc_bd_note"),
           plotlyOutput("p_holc_bd", height = 340), tableOutput("t_holc_bd"),
           tags$small(class = "text-muted", "Design after Aaronson, Hartley & Mazumder (2021): the D-side minus C-side difference (population-weighted, HC1 SE) is tracked before and after the 1938 map (grey line). Before 1940 the units are the reconstructed enumeration districts, ",
             "whose centroid falls in a C or D area; from 1940 they are 2010 tracts with earlier censuses interpolated. A gap already widening before 1938 means the map ratified an existing divergence; one that opens only afterwards points to the map (or to the FHA practices and covenants of the same years — Fishback, Rose, Snowden & Storrs 2024 find FHA, not HOLC, drove lending). ",
             "Green crosses and the 'net of rail + 1925 zoning' column add the share of each unit zoned industrial on the 1929 building-zone map as a second control (the ordinance that the appraisers were themselves reading). Blue crosses and the 'net of rail' column: the same gap with each unit's distance to the nearest rail line (TIGER/Line; today's network, in Denver essentially the pre-1900 trunk lines and yards) added to the regression, since a boundary that follows a railway can differ for reasons other than the grade. The 1925 zoning ordinance is not controlled. ",
             "Error bars are 95% intervals of the difference in population-weighted means across the units in the band: they are wide after 1940 because only ~15 tracts lie on each side and tract-level shares are far more dispersed than district-level ones (a few Five Points tracts were 60-80% Black while most were near 0), and for pairs involving A or B because those areas are few.")),
      card(card_header("Industry by HOLC grade before and after the map: hazardous firms per km²"), tableOutput("t_holc_ind"),
           tags$small(class = "text-muted", "Street-level hazardous trades in the business directory (1891–1956) and hazardous-sector manufacturers in the Directory of Colorado Manufacturers (1961–2002), active in each period, per km² of each grade's area. ",
             "The D/C ratio before 1938 measures the industrial geography the appraisers found; its change afterwards is what the map, zoning and the post-war land market added."),
           tags$hr(), tags$b("The 1925 zoning ordinance by HOLC grade"), tableOutput("t_holc_zon"),
           tags$details(tags$summary(tags$small("See the 1929 Building Zone Map and how it was classified")),
             layout_columns(col_widths = c(6, 6),
               tags$figure(tags$a(href = "zoning_1929_scan.jpg", target = "_blank", tags$img(src = "zoning_1929_scan.jpg", style = "width:100%; border:1px solid #ddd")),
                           tags$figcaption(tags$small("Building Zone Map, City and County of Denver, adopted February 1925, revised to January 1, 1929. Denver Public Library Western History Collection, CG4314 .D4 G44 1929. Click to open full size."))),
               tags$figure(tags$a(href = "zoning_1929_classified.jpg", target = "_blank", tags$img(src = "zoning_1929_classified.jpg", style = "width:100%; border:1px solid #ddd")),
                           tags$figcaption(tags$small("The same scan with the texture classification drawn over it: red = Industrial A, blue = Industrial B, yellow = Commercial. Residential (hatched blocks with lot lines) and Business (solid black) districts are left unclassified. Georeferenced in R/zoning_1925.R and shown as a map layer above."))))),
           tags$small(class = "text-muted", "Share of each grade's land that the city had zoned Industrial (A or B) or Commercial by January 1929, thirteen years before the HOLC map (R/zoning_1925.R; see the map layer). The ordinance and the appraisers drew the same line: the industrial corridor of the Platte and the rail yards is D land or left ungraded as 'Industrial'.")))
    ),
  ),
  nav_menu("Explore more",
  nav_panel("Neighborhoods",
    layout_columns(col_widths = c(3, 9),
      card(card_header("Compare census tracts"),
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
           card_header("All indicators: medians, means and Wilcoxon rank-sum test"), DTOutput("t_cmp")))),
  nav_panel("Nearby schools & health care",
    layout_columns(col_widths = c(3, 9),
      card(card_header("Sensitive places near potentially unknown sites"),
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
           hr(), selectInput("bm_year", "County comparison: edition", NULL), checkboxInput("bm_haz", "Hazardous sectors only", FALSE),
           tags$small(class = "text-muted", "CBP: Eckert, Fort, Schott & Yang (2021) raw county files (1975–85 National Archives, 1986+ Census Bureau). NHGIS: county manufacturing tables 1880–1940 (IPUMS NHGIS). Atack–Bateman–Weiss: Census of Manufactures samples 1870, 1880 (Vanderbilt / ICPSR). Rscript R/benchmarks.R reproduces this tab.")),
      div(
        layout_columns(col_widths = c(6, 6),
          card(card_header("1975–2002: manufacturing establishments in Colorado — County Business Patterns vs the Directory of Colorado Manufacturers"), plotlyOutput("p_bm_state", height = 360),
               tags$small(class = "text-muted", "CBP counts every establishment with a payroll (SIC 20–39 to 1997, NAICS 31–33 from 1998), from administrative records; the directory lists firms that answered the publisher's questionnaire. The ratio is the directory's coverage rate; it varies by edition mainly with how much of each volume was scanned (see the table), which is why edition-to-edition changes in site counts on the Trends tab should be read against this chart.")),
          card(card_header("County agreement"), tableOutput("t_bm_fit"), uiOutput("bm_fit_note"))),
        layout_columns(col_widths = c(7, 5),
          card(card_header("Counties in the chosen edition: directory vs CBP"), plotlyOutput("p_bm_cty", height = 380), tableOutput("t_bm_cty")),
          card(card_header("1880–1940: census manufacturing establishments by county vs the business directory's hazardous trades"), uiOutput("bm_nh"),
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
          tags$dt("Historical hazardous sites, 1961\u20132002"),
          tags$dd("Every manufacturer listed in the Colorado Directory of Manufacturers (25 editions, CU Boulder Libraries scans, OCR'd with Tesseract) ",
                  "whose industry code falls in Frickel & Elliott's hazardous sectors: SIC 28 chemicals, 29 petroleum, 30 rubber & plastics, 33 primary metals, ",
                  "34 fabricated metals, 35 industrial machinery, 37 transportation equipment. Addresses are geocoded offline on US Census TIGER/Line 2023 address ranges; ",
                  "listings within 30 m form one site. 'Extended sectors' adds wood preserving, tanning, electronics & circuit boards, batteries, photographic chemicals and ore milling."),
          tags$dt("Current regulatory status"),
          tags$dd("Each site is compared with EPA's Facility Registry Service (all programs: RCRA, air, water, Superfund, brownfields, TRI\u2026), EPA TRI, and the CDPHE layers below. ",
                  "A site is 'known' when a record lies within 75 m (cleanup programs), 100 m (TRI) or 40 m (RCRA handlers, other permits), shares the firm's name within 250 m, ",
                  "has the same address, or lies inside a cleanup-site boundary. 'Not on any list' means none of these. It is a lead for records review or soil testing, not evidence of contamination."),
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
          tags$dd("Every 500 m grid cell (UTM 13N) with a street-level-geocoded manufacturer in 1961\u20132002, classed by how long industry stayed: persistent (first listed by 1968, still listed in 1990 or later, with a firm in at least 60% of the editions in between), ",
                  "persistent with sector turnover (dominant 2-digit SIC sector changed, three or more sectors led the cell), emerging (first listed 1980 or later), former (last listed 1980 or earlier) and intermittent (the rest). Popups give first and last edition, peak number of firms, ",
                  "first and last dominant sector and any street-level pre-1960 hazardous trade in the cell. Clustering (Ellison\u2013Glaeser) and succession statistics are on the Trends tab; Rscript R/corridors.R reproduces them."),
          tags$dt("Census tracts 1940\u20132020 (Census tracts over time tab)"),
          tags$dd("Decennial census tract tables from IPUMS NHGIS (Manson et al., University of Minnesota), fetched through the NHGIS API (Rscript R/fetch_census.R): total population, Black (the 1940 tract table reports nonwhite, which is used as the 1940 value and labelled so in the downloads), ",
                  "Hispanic (Spanish surname 1960, Spanish American 1970, Spanish origin 1980, Hispanic 1990+), foreign born and persons below the poverty line (1970+). ",
                  "1940\u20131980 values are on each census's own tracts and are re-weighted by area onto 2010 tracts; 1990\u20132020 use NHGIS's standardised 2010-tract time series. ",
                  "Firm counts per tract come from this project's geocoded directories. All 1,249 Colorado tracts (2010 boundaries) are shown; the panel models use the 185 tracts of Denver and the first-ring suburbs within 10 km of downtown."),
          tags$dt("Denver enumeration districts 1880\u20131940 (reconstructed; Denver 1880\u20132020 tab)"),
          tags$dd("No public source has boundaries for the enumeration districts (EDs) of 1900\u20131940 (Brown's Urban Transition project drew 1880's, and 1880 is rebuilt here from its geocoded buildings so that all six censuses are constructed the same way); IPUMS gives every person's ED number but no addresses. Brown University's Geographic Reference Files (GRF) ",
                  "for Denver list every person of the 1900\u20131940 censuses with the household's street, house number and ED (no coordinates). The districts here are reconstructed from them: ",
                  "(1) every distinct address is geocoded with this project's offline TIGER/Line geocoder (Denver's modern numbering dates from 1887; a few renamed streets such as Holladay \u2192 Market are translated), ",
                  "keeping street-level results only; (2) stray geocodes are dropped \u2014 farther from the district's person-weighted median centre than max(400 m, 2.5\u00d7 the median) or with fewer than 30% of their ten nearest neighbours in the same district; ",
                  "(3) a Voronoi tessellation of the remaining addresses is dissolved by district and clipped to the concave hull of all addresses, each district keeps its main body and freed ground goes to the nearest district, so the districts are space-filling like tracts; ",
                  "(4) the IPUMS full-count totals are attached by district number. 1880 is tessellated the same way from Brown's geocoded 1880 buildings. 73% of the 1900 population is placed at street level; the geocoding log is in data/results/denver_eds/ed_geocoding.csv. ",
                  "Boundaries are therefore approximate (a block or so at the edges) and are this project's derived product; the address files stay with the project under Brown's conditions of use. ",
                  "Reproduce with Rscript R/grf_eds.R (or python pipeline/historical/grf_eds.py) and Rscript R/denver_eds_analysis.R."),
          tags$dt("How units are harmonised over time"),
          tags$dd("Three kinds of unit appear, each handled differently. (1) Census tracts 1940\u20132020 are all expressed on 2010 tract boundaries: NHGIS's own standardised time series for 1990\u20132020 (counts re-allocated by block-level weights), ",
                  "and for 1940\u20131980 this project's area-weighted interpolation (each old tract's counts split among the 2010 tracts it overlaps in proportion to area; 2020 ACS counts likewise); shares are then computed from the re-allocated counts. ",
                  "Area weighting assumes people are spread evenly within an old tract, so values are approximate where an old tract straddled very different neighbourhoods. (2) Counties 1880\u20131940 are shown on each census's own boundaries and are not harmonised ",
                  "(counties were created and split through 1913), so compare the labelled county, not the shape. (3) Enumeration districts 1880\u20131940 are each census's own districts (reconstructed as described above) and are not linked across censuses; ",
                  "where they are compared with HOLC areas or 2010 tracts, their counts are area-weighted onto those units in the same way as the tracts."),
          tags$dt("HOLC 1938 redlining map (Redlining & covenants tab)"),
          tags$dd("The Home Owners' Loan Corporation's Residential Security Map of Denver (1938) and the appraisers' area-description forms, from Mapping Inequality (Nelson, Winling et al., University of Richmond Digital Scholarship Lab; spatial data CC-BY-NC), ",
                  "with their crosswalk of HOLC areas to 2010 census tracts. HOLC graded only residential neighbourhoods, A ('best') to D ('hazardous'); areas it judged non-residential were outlined but not graded and labelled Industrial or Commercial - Denver has 16 such zones, drawn in grey and lilac on the map, holding 12% of HOLC's land area and 6% of the 1940 population but three-quarters of the pre-map hazardous trades. The tab reads the grades against the reconstructed 1930 and 1940 districts (area-weighted), the firms of 1921\u201340 and the 1940\u20132020 tract panel. Rscript R/holc_covenants.R."),
          tags$dt("Denver 1925 zoning ordinance (Map and Redlining tabs)"),
          tags$dd("Building Zone Map, City and County of Denver, as adopted by the City Council February 1925, revised to January 1, 1929 (Denver Public Library Western History Collection, CG4314 .D4 G44 1929; the 1944 revision is CG4314 .G44 1944). ",
                  "The scan is a monochrome hatched map; a texture classifier labelled 32-pixel cells by hatch pattern as Industrial A, Industrial B or Commercial districts (residence and business districts are not drawn), and R/zoning_1925.R georeferenced it from 13 street intersections and park corners resolved to TIGER road intersections (affine fit, RMSE 25 m). ",
                  "Residence E (apartment) districts share a hatch with Industrial A and are separated only by lot lines, so some platted blocks near the Platte and the unplatted land north-east of the 1929 city are the least certain cells. The share of each HOLC area, district and tract zoned industrial enters the Redlining tab's boundary gaps and change models as a control."),
          tags$dt("What became of the sites (City and County of Denver assessor parcels)"),
          tags$dd("Denver open-data parcel feature service (ODC_PROP_PARCELS_A): assessor property class, zone district, dwelling units and original year built, queried for the nearest parcel within 40 m of every geocoded Denver site (R/site_fate.R; downloads of October 2026). ",
                  "Built from the complete directory editions only. A match identifies the parcel at the geocoded address today, not necessarily the historical lot; absence from the cleanup inventories this project searched is not evidence that a site was never assessed or remediated."),
          tags$dt("Racial covenants 1931\u20131935"),
          tags$dd("Mapping Prejudice: Denver (Denver Public Library Special Collections, pilot project; public domain, data.colorado.gov): 764 deeds recorded 1931\u201335 with racially restrictive language, placed at the parcel (730 with a location). The deed text is searched for clauses that also bar business or manufacturing use."),
          tags$dt("Colorado counties 1880\u20131940 (Census tracts over time tab)"),
          tags$dd("The IPUMS full count aggregated to counties on each census's own county boundaries (NHGIS), with the pre-1960 hazardous trades of the preceding decade assigned to counties by location (town centre where no street is known). Rscript R/county_panel_1880_1940.R."),
          tags$dt("Denver 1880 at the building level (Brown University Urban Transition HGIS)"),
          tags$dd("Brown's Spatial Structures in the Social Sciences project geocoded the complete 1880 census of 39 cities to buildings and drew the enumeration districts and 1880 street grid ",
                  "(Logan et al.; s4.ad.brown.edu/Projects/UTP2). The hazardous trades of the 1878\u20131885 Colorado State Business Directories were placed on that 1880 grid by their printed house numbers, ",
                  "and residents' distance to the nearest firm computed at the building. The app shows only enumeration-district aggregates, firm points and model results; the person- and building-level files ",
                  "stay with the project under Brown's conditions of use (no redistribution). Rscript R/denver_1880.R reproduces the analysis from Brown's downloads."),
          tags$dt("Denver 1950\u20132020 by census tract (Denver 1880\u20132020 tab)"),
          tags$dd("The district analyses carried forward on the 185 tracts of the Denver core (2010 boundaries, earlier censuses interpolated as on the Census tracts tab): firms of the decade from the business directory (1941-60) and the manufacturers' directory (1961-1992 complete editions; 2000, 2010 and 2020 use the last complete decade, 1983-1992, i.e. proximity to historically listed sites), ",
                  "distance from each tract centroid to the nearest one, population-weighted regressions on log distance, tracts with vs without a firm, and firm shares by population quartile. Measures are the tract tables' (race, Hispanic origin from 1960, nativity, poverty from 1970, tenure, value, rent). Rscript R/denver_tracts_1950_2020.R."),
          tags$dt("Denver 1880\u20131940 (IPUMS USA full count)"),
          tags$dd("The complete-count census microdata for 1880, 1900, 1910, 1920, 1930 and 1940 (Ruggles et al., IPUMS USA), Colorado only, aggregated to enumeration districts (Rscript R/fetch_ipums_fullcount.R): ",
                  "population, Black, foreign born by region, Hispanic (IPUMS HISPAN, inferred before 1970) and laborers (OCC1950 970\u2013979). ",
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
          tags$dt("Census tracts: EnviroScreen"),
          tags$dd("CDPHE Colorado EnviroScreen 2.0: environmental, health and social indicators for 2020 census tracts, with percentile scores. Health indicators come from CDPHE administrative data or modelled estimates (see the tool's documentation)."),
          tags$dt("Base maps and address ranges"),
          tags$dd("Esri light grey canvas, OpenStreetMap and Esri world imagery tiles; US Census Bureau TIGER/Line 2023 ADDRFEAT for geocoding. ",
                  "All the CDPHE and EPA inventories are live services that change over time; the app shows a snapshot. Code and data: github.com/pdez90/Colorado_hiddenhazards.")))
    )),
  nav_panel("Data & downloads",
    layout_columns(col_widths = c(4, 8),
      card(card_header("Geocoded directory listings by edition"),
           selectInput("dl_year", "Edition", { dcm <- sort(as.integer(sub("CO_DCM_(\\d+)_geocoded.csv", "\\1", list.files(by_year_dir, "CO_DCM_.*csv")))); bd <- if (is.null(pre60)) integer() else sort(unique(pre60$year))
             c(setNames(as.list(bd), paste(bd, "(State Business Directory: hazardous trades)")), setNames(as.list(dcm), paste(dcm, "(Directory of Colorado Manufacturers)"))) }, selected = 1961),
           downloadButton("dl_one", "Download edition CSV"),
           tags$small(class = "text-muted d-block mt-1 mb-3", "1871-1956 files hold the hazardous-trade listings extracted from that edition of the Colorado State Business Directory (volume, page, town, trade, sector, placement precision, coordinates, linked firm id). 1961-2002 files hold every manufacturer listed in that edition with its codes and geocode."), br(),
           uiOutput("dl_btns"),
           downloadButton("dl_hist", "Download pre-1960 hazardous-trade firms (1871–1956)"), br(), br(),
           downloadButton("dl_cells", "Download industrial corridor cells (500 m)"),
           tags$hr(), tags$b("Zoning, redlining and site-fate files"), br(),
           tags$small(class = "text-muted d-block mt-1 mb-2", "Denver's 1925 zoning ordinance as mapped in January 1929 (industrial and commercial districts, georeferenced from the Denver Public Library scan; see Redlining & covenants), the share of every HOLC area and 2010 tract zoned industrial and commercial, the HOLC boundary gaps and change models with their rail and zoning adjustments, and what stands today on each Denver site."),
           uiOutput("dl_zoning_btns"),
           tags$small(class = "text-muted d-block mt-1 mb-3", tags$b("How corridor cells are defined. "),
             "Every geocoded manufacturer in the 1961–2002 Directory of Colorado Manufacturers (street-level geocodes only) is snapped to a 500 m × 500 m grid cell (UTM zone 13N), ",
             "and every cell with at least one manufacturer in any edition is kept (4,078 cells). For each cell the script counts establishments per edition, finds the dominant 2-digit SIC sector, ",
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
             "1880 is tessellated the same way from Brown's geocoded 1880 buildings. About 73% of the 1900 population is placed at street level (data/results/denver_eds/ed_geocoding.csv); boundaries are approximate by a block or so at the edges. ",
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
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}",
               attribution = "Tiles &copy; Esri &mdash; Esri, HERE, Garmin, &copy; OpenStreetMap contributors", group = "Light grey") |>
      addTiles("https://tile.openstreetmap.org/{z}/{x}/{y}.png",
               attribution = "&copy; OpenStreetMap contributors", group = "OpenStreetMap") |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
               attribution = "Tiles &copy; Esri &mdash; Source: Esri, Maxar, Earthstar Geographics", group = "Satellite") |>
      setView(-105.2, 39.3, 7) |>
      addMapPane("tr", zIndex = 380) |> addMapPane("ctx", zIndex = 430) |> addMapPane("haz", zIndex = 460)
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
    # industrial corridors: 500 m cells with any manufacturer 1961-2002, classed by persistence (R/corridors.R)
    if (!is.null(cells) && nrow(cells)) {
      cc <- cells[order(match(cells$class, rev(CELL_CLASSES))), ]
      m <- m |> addCircleMarkers(data = cc, ~lon, ~lat, radius = pmin(3 + 1.5 * sqrt(cc$max_n), 14), stroke = TRUE, weight = 0.6, color = "#333333",
        fillColor = unname(CELL_COL[cc$class]), fillOpacity = 0.75,
        popup = sprintf("<b>Industrial cell: %s</b><br>Manufacturers listed %s–%s in %s editions; up to %s firms at once%s<br>Dominant sector first %s, last %s (%s sectors over time)%s",
                        esc(cc$class), cc$first, cc$last, cc$editions, cc$max_n, ifelse(cc$ever_haz %in% TRUE, " · <b>hazardous sector present</b>", ""),
                        esc(cc$first_sector), esc(cc$last_sector), cc$n_sectors,
                        ifelse(is.na(cc$pre1960_first), "", sprintf("<br>Pre-1960 hazardous trade here since %s (%s firms)", cc$pre1960_first, cc$pre1960_firms))),
        group = "Industrial corridors (500 m cells)", options = pathOptions(pane = "ctx")) |>
        addLegend("topleft", colors = unname(CELL_COL), labels = CELL_CLASSES, title = "Industrial corridors<br><small>500 m cells, 1961–2002; size = peak firms</small>",
                  opacity = 0.8, group = "Industrial corridors (500 m cells)")
    }
    if (!is.null(zon)) { zc <- unname(ZON_COL[zon$zone]); zc[is.na(zc)] <- "#999999"
      m <- m |> addPolygons(data = zon, fillColor = zc, fillOpacity = 0.45, color = zc, weight = 1, group = "Denver 1925 zoning (1929 map)", options = pathOptions(pane = "tr"),
                            label = sprintf("Denver 1925 zoning ordinance, as mapped in 1929: %s district", zon$zone)) |>
        addLegend("topleft", colors = unname(ZON_COL), labels = names(ZON_COL), title = "Denver 1925 zoning<br><small>Building Zone Map rev. 1929 (DPL); residential and business districts not shown</small>", opacity = 0.7, group = "Denver 1925 zoning (1929 map)") }
    m |> addLayersControl(baseGroups = c("Light grey", "OpenStreetMap", "Satellite"),
          overlayGroups = c("Historical hazardous sites", "Pre-1960 hazardous trades", "Industrial corridors (500 m cells)", if (!is.null(zon)) "Denver 1925 zoning (1929 map)", "EnviroScreen tracts", "EPA TRI facilities", "Schools", "Hospitals", "Clinics",
                            "Residential & long-term care", CLEAN_LAYERS),
          options = layersControlOptions(collapsed = FALSE)) |>
      hideGroup(c("Industrial corridors (500 m cells)", "Denver 1925 zoning (1929 map)", "Schools", "Hospitals", "Clinics", "Residential & long-term care", "Environmental covenants / land-use controls",
                  "RCRA corrective action", "Voluntary cleanup (VCUP)", "Superfund (SEMS)")) |>
      identity()
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
                   esc(s$address), esc(s$city), esc(s$radar), esc(s$confidence), s$n_editions, s$haz_first, s$haz_last, s$span_years,
                   s$first_year, s$last_year, esc(s$years_in_range),
                   ft, esc(s$fe_sectors), esc(s$ext_sectors),
                   ifelse(is.na(s$hist_first_year), "", sprintf("<br><b>Pre-1960 precursor (since %s):</b> %s", s$hist_first_year, esc(s$hist_names))),
                   ifelse(s$known_match == "" | is.na(s$known_match), "none", esc(s$known_match)), s$site_id, s$lat, s$lon)
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
      ifelse(d$persists_to_1961plus, sprintf("<br><b>Persisted:</b> %s in the 1961–2002 directory (%s; matched by %s)", esc(d$dcm_name), esc(d$dcm_years), esc(d$link)), ""),
      esc(d$example))
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
                      ifelse(tg$n_persist > 0, sprintf("<br>&#9679; = still listed in the 1961–2002 directory (%s)", tg$n_persist), ""), tg$rows)
      px <- px |> addCircleMarkers(data = tg, ~lon, ~lat, radius = pmin(4 + 1.6 * sqrt(tg$n), 18), color = ifelse(tg$n_persist > 0, "#000000", "#ffffff"),
                    weight = ifelse(tg$n_persist > 0, 2, 0.8), fillColor = HIST_COL, fillOpacity = 0.5, popup = tpop,
                    popupOptions = popupOptions(maxWidth = 420), label = sprintf("%s: %s firms", tg$town, tg$n),
                    group = "Pre-1960 hazardous trades", options = pathOptions(pane = "haz"))
    }
    if (nrow(st)) px <- px |> addCircleMarkers(data = st, ~lon, ~lat, radius = 3 + 1.2 * sqrt(st$editions), color = ring(st),
                    weight = ifelse(st$persists_to_1961plus, 2, 0.8), fillColor = HIST_COL, fillOpacity = 0.95, popup = pop(st),
                    group = "Pre-1960 hazardous trades", options = pathOptions(pane = "haz"))
    px |> addLegend("topleft", colors = c(HIST_COL, HIST_COL), labels = c("Street address (Denver 1891+, larger cities 1910+)", "Town centre only (one marker per town; size = number of firms)"),
                    title = "Pre-1960 hazardous trades<br><small>black ring = firm or address still in 1961–2002 directory</small>",
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
    if (identical(input$tl_mode, "complete")) d <- d |> filter(complete); if (!nrow(d)) return(NULL)
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
    ggplotly(ggplot(d, aes(factor(yr), n, fill = app_sectors)) + geom_col() + labs(x = "Business directory edition", y = "Firms", fill = NULL) +
               theme_minimal())
  })
  output$p_mix <- renderPlotly({ if (is.null(mix)) return(NULL)
    ggplotly(ggplot(mix, aes(year, share, fill = group, text = sprintf("%s, %s: %.1f%% (%s firms)", group, year, 100 * share, establishments))) +
               geom_col(position = "stack", width = 0.9) + scale_y_continuous(labels = scales::percent) +
               labs(x = "Directory edition", y = "Share of listed firms", fill = NULL) + theme_minimal(), tooltip = "text") })
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
  output$t_recv <- renderDT({ r <- recv(); if (is.null(r)) return(datatable(data.frame()))
    datatable(r |> select(Name = name, Type = kind, Detail = detail, Address = address, `Unknown sites within distance` = n_unknown_sites,
                          `Nearest (m)` = nearest_m, `Nearby sites (first 3)` = nearby_sites),
              rownames = FALSE, filter = "top", options = list(pageLength = 25, scrollX = TRUE)) })

  # ---- corridors (Trends)
  output$p_eg <- renderPlotly({ if (is.null(eg)) return(NULL)
    d <- eg |> filter(scope == input$eg_scope, sector %in% c("Chemicals", "Petroleum", "Rubber & plastics", "Primary metals", "Fabricated metals", "Machinery", "Transportation eq.", "Printing", "Food")) |> arrange(sector, year)
    if (!nrow(d)) return(NULL)
    pl <- plot_ly()
    for (sec in unique(d$sector)) { di <- d[d$sector == sec, ]
      pl <- add_trace(pl, data = di, x = ~year, y = ~gamma, type = "scatter", mode = "lines+markers", name = sec, legendgroup = sec,
                      marker = list(size = 8, symbol = ifelse(di$p < 0.05, "circle", "circle-open")),
                      text = sprintf("%s %s: γ = %.4f, p = %.3f (%s of %s firms)", sec, di$year, di$gamma, di$p, di$n, di$n_all), hoverinfo = "text") }
    layout(pl, xaxis = list(title = "Directory edition"), yaxis = list(title = "Ellison–Glaeser γ (vs. all manufacturing)", zeroline = TRUE), legend = list(orientation = "h", y = -0.25)) })
  output$p_trans <- renderPlotly({ if (is.null(trans)) return(NULL)
    d <- trans |> filter(from != to, !is.na(to), to != "", !is.na(from), from != "") |> arrange(desc(N)) |> head(15) |> mutate(lab = paste(from, "→", to), lab = factor(lab, rev(lab)))
    ggplotly(ggplot(d, aes(N, lab, text = sprintf("%s: %s cell-transitions (%.0f%% of transitions from %s)", lab, N, 100 * share_of_from, from))) + geom_col(fill = "#7a0177") +
               labs(x = "Cell-transitions, 1961–2002", y = NULL) + theme_minimal(), tooltip = "text") })

  # ---- Denver over time: NHGIS tract panel on 2010 tracts + firms active in the decade
  county_mode <- reactive(!is.null(co_cnty) && as.integer(input$pan_year) < 1940)
  pan_year <- reactive({ y <- as.integer(input$pan_year)
    if (county_mode()) { cc <- co_cnty[co_cnty$census == y, ]
      return(cc |> transmute(GEOID = name, p_black = pct_black, p_hisp = pct_hisp, p_fb = pct_fb, p_pov = NA_real_, p_owner = NA_real_, mval_2020 = NA_real_, mrent_2020 = NA_real_, hmda_denial = NA_real_, hmda_denial_hisp = NA_real_, hmda_denial_black = NA_real_, hmda_pct_hisp_apps = NA_real_, pop, firms_haz, firms_all = NA_integer_, legacy_haz = NA_integer_, dist_km = NA_real_,
                             p_laborers = pct_laborers, p_fb_mexico = pct_fb_mexico)) }
    d <- den_pan[den_pan$census == y, ]
    tr <- if (input$pan_area == "core") den_tr[den_tr$core, ] else den_tr
    tr |> left_join(d |> select(-dist_km, -area_km2), by = "GEOID") })
  output$pan_avail <- renderUI({   # which variables the chosen census has
    y <- as.integer(input$pan_year)
    if (county_mode()) { d <- st_drop_geometry(co_cnty[co_cnty$census == y, ])
      return(HTML(sprintf("<small class='text-muted'>%s: %s counties (%s with full-count totals) · IPUMS full count: Black, foreign born, Mexican-born, Hispanic (inferred), laborers; no poverty</small>", y, nrow(d), sum(!is.na(d$pop))))) }
    d <- den_pan[den_pan$census == y, ]
    ok <- sapply(c("p_black", "p_hisp", "p_fb", "p_pov", "p_owner", "mval_2020", "mrent_2020"), function(v) any(!is.na(d[[v]])))
    HTML(sprintf("<small class='text-muted'>%s: %s tracts with data · %s</small>", y, format(sum(!is.na(d$pop) & d$pop > 0), big.mark = ","),
                 paste(ifelse(ok, "<span style='color:#1b7837'>&#10003;</span>", "<span style='color:#b2182b'>&#10007;</span>"), c("Black", "Hispanic", "foreign born", "poverty", "ownership", "home value", "rent"), collapse = " "))) })
  observe({ if (input$pan_area == "core" && !county_mode()) leafletProxy("map_den") |> setView(-104.97, 39.74, 11) else leafletProxy("map_den") |> setView(-105.3, 39.2, 7) })
  output$pan_title <- renderText(sprintf("Who lived in the industrial tracts? Mean composition of %s tracts with and without an active hazardous firm (1940\u20132020)", if (input$pan_area == "core") "Denver-core" else "Colorado"))
  pan_firms <- reactive({   # hazardous firms of the sidebar's sectors active in the decade ending in the census year
    y <- as.integer(input$pan_year); a <- if (y <= 1960) c(y - 9, y) else if (y == 1970) c(1961, 1970) else if (y >= 2000) c(1983, 1992) else c(y - 9, y)
    if (y <= 1960) { h <- sel_hist(); if (is.null(h)) return(NULL)
      h <- h |> filter(if (county_mode()) TRUE else precision != "town", first_year <= a[2], last_year >= a[1]); data.frame(lon = h$lon, lat = h$lat, lab = sprintf("%s (%s)", h$name, h$years))
    } else { s <- sites |> filter(radar %in% input$st, confidence %in% input$cf); sy <- site_yr |> filter(year >= a[1], year <= a[2])
      if (length(input$sec)) sy <- sy |> filter(grepl(paste(gsub("([&+()])", "\\\\\\1", input$sec), collapse = "|"), sectors)) else return(NULL)
      s <- s |> filter(site_id %in% sy$site_id); data.frame(lon = s$lon, lat = s$lat, lab = sprintf("%s, %s (%s)", s$address, s$city, s$hazard_firms)) } })
  output$map_den <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}",
               attribution = "Tiles &copy; Esri &mdash; Esri, HERE, Garmin, &copy; OpenStreetMap contributors") |>
      setView(-105.3, 39.2, 7) |> addMapPane("tr", zIndex = 380) |> addMapPane("haz", zIndex = 460) })
  observe({
    req(input$map_den_zoom)                                   # wait until the map exists (the tab may not have been opened yet)
    v <- input$pan_var; d <- pan_year(); x <- d[[v]]; lab <- names(PAN_VARS)[PAN_VARS == v]; cm <- county_mode()
    pal <- if (all(is.na(x))) function(z) "#c7c7c7" else colorBin(if (v %in% c("firms_haz", "legacy_haz")) "PuRd" else "YlGnBu", domain = x, bins = 7, pretty = TRUE, na.color = "#f0f0f0")
    px <- leafletProxy("map_den") |> clearGroup("tracts") |> clearGroup("firms") |> removeControl("panlegend") |> removeControl("pannote") |> removeControl("unitnote") |>
      addControl(sprintf("<div style='background:#ffffffdd;padding:4px 10px;border-radius:4px'><b>%s census · %s</b></div>", input$pan_year, if (cm) "counties on that census's boundaries (IPUMS full count; no tracts before 1940)" else "2010 census tracts (NHGIS, harmonised)"), position = "topleft", layerId = "unitnote") |>
      addPolygons(data = d, fillColor = pal(x), fillOpacity = 0.7, color = if (cm) "#666666" else "#ffffff", weight = if (cm) 0.8 else 0.6, group = "tracts", options = pathOptions(pane = "tr"), label = if (cm) sprintf("%s County, %s", d$GEOID, input$pan_year) else NULL,
                  popup = if (cm) sprintf("<b>%s County</b>, %s census (full count)<br>%s: <b>%s</b><br>Population %s · Black %s%% · foreign born %s%% (Mexican-born %s%%) · Hispanic %s%% · laborers %s%%<br>Pre-1960 hazardous-trade firms listed in the decade: %s",
                                  d$GEOID, input$pan_year, lab, ifelse(is.na(x), "no data", round(x, 1)), ifelse(is.na(d$pop), "–", format(d$pop, big.mark = ",")), esc(d$p_black), esc(d$p_fb), esc(d$p_fb_mexico), esc(d$p_hisp), esc(d$p_laborers), esc(d$firms_haz))
                          else sprintf("<b>Tract %s</b>, %s census<br>%s: <b>%s</b><br>Population %s · Black %s%% · Hispanic %s%% · Foreign born %s%% · Poverty %s%%<br>Hazardous firms active in decade: %s (all manufacturers: %s) · legacy hazardous firms: %s<br><small>%s km from downtown</small>",
                                  d$GEOID, input$pan_year, lab, ifelse(is.na(x), "no data", round(x, 1)), ifelse(is.na(d$pop), "–", format(d$pop, big.mark = ",")), esc(d$p_black), esc(d$p_hisp), esc(d$p_fb), esc(d$p_pov),
                                  esc(d$firms_haz), ifelse(is.na(d$firms_all), "–", d$firms_all), esc(d$legacy_haz), d$dist_km))
    if (!all(is.na(x))) px <- px |> addLegend("bottomright", pal = pal, values = x, title = paste0(lab, "<br><small>", input$pan_year, " census</small>"), layerId = "panlegend", opacity = 0.8)
    else px <- px |> addControl(sprintf("<div style='background:#fff3cd;padding:6px 10px;border-radius:4px;max-width:260px'><b>%s: no %s data</b><br><small>%s</small></div>", lab, input$pan_year,
        if (v == "p_hisp") "The census had no Hispanic measure before 1960 (Spanish surname)." else if (v == "p_pov") "Poverty was first measured in the 1970 census; 2010 and 2020 use ACS 5-year estimates." else if (cm) "Not in the full-count county series."
        else if (v == "p_fb") "Foreign born comes from the long-form/ACS tables (1990 STF3, 2000 SF3, ACS 2008-12 and 2016-20); if missing, re-run R/fetch_census.R to fetch them."
        else if (v %in% c("p_owner", "mval_2020", "mrent_2020")) "Tenure, median value and median rent come from the housing tables (NHGIS extract H); re-run R/fetch_census.R to fetch them. Dollars are 2020 dollars (CPI-U); rent is contract rent before 2000 and gross rent after."
        else if (grepl("^hmda", v)) "HMDA mortgage data (2018-21 home-purchase applications, CFPB) are shown on the 2020 census only; run R/fetch_hmda.R to fetch them." else "Not in the tract tables for this census."),
        position = "topright", layerId = "pannote")
    if (isTRUE(input$pan_firms)) { f <- pan_firms()
      if (!is.null(f) && nrow(f)) px <- px |> addCircleMarkers(data = f, ~lon, ~lat, radius = 3.5, color = "#ffffff", weight = 0.7, fillColor = "#d1491f", fillOpacity = 0.95,
                                                               label = ~lab, group = "firms", options = pathOptions(pane = "haz")) }
    px })
  output$p_pan <- renderPlotly({
    v <- input$pan_var; lab <- names(PAN_VARS)[PAN_VARS == v]
    validate(need(v %in% c("p_black", "p_white", "p_hisp", "p_fb", "p_pov", "p_owner", "mval_2020", "mrent_2020"), paste0("'", lab, "' is observed once (HMDA 2018-21, shown on the 2020 map), so there is no series to plot; choose a census measure.")),
             need(v %in% names(den_pan) && any(!is.na(den_pan[[v]])), paste0("'", lab, "' is not in the tract panel yet (rerun R/fetch_census.R and R/app_census_layers.R).")))
    d <- den_pan |> filter(!is.na(.data[[v]]), !is.na(pop), pop > 0, if (input$pan_area == "core") core else TRUE) |>
      mutate(group = case_when(firms_haz > 0 ~ "Active hazardous firm in tract", legacy_haz > 0 ~ "Legacy only (firms gone)", TRUE ~ "Never a hazardous firm")) |>
      group_by(census, group) |> summarise(val = weighted.mean(.data[[v]], pop), tracts = n(), .groups = "drop")
    if (!nrow(d)) return(NULL)
    ggplotly(ggplot(d, aes(census, val, colour = group, group = group, text = sprintf("%s, %s: %s (%s tracts)", group, census, round(val, 1), tracts))) + geom_line() + geom_point(size = 2) +
               scale_colour_manual(values = c("Active hazardous firm in tract" = "#d1491f", "Legacy only (firms gone)" = "#7a4aa8", "Never a hazardous firm" = "#7f8c8d")) +
               scale_x_continuous(breaks = seq(1940, 2020, 10)) + labs(x = "Census", y = lab, colour = NULL) + theme_minimal(), tooltip = "text") |> hleg() })
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
    HTML(paste0("<p><b>Who moves in after industry arrives?</b> Pooled over all five censuses 1970\u20132010 (898 tract-years): effect on the outcome (percentage points; log points for value and rent) per log-unit of hazardous-firm density; (SE); ** p&lt;0.01, * p&lt;0.05, † p&lt;0.1. Outcomes appear when the census panel provides them for 1970\u20132010 (White, ownership, value and rent after rerunning fetch_census.R and ej_panel.R).</p>",
                "<table class='table table-sm' style='font-size:12px'><tr><th>Predictor</th>", paste0("<th>", names(h)[-1], "</th>", collapse = ""), "</tr>",
                paste0("<tr><td>", h$term, "</td>", apply(h[, -1], 1, function(z) paste0("<td>", z, "</td>", collapse = "")), "</tr>", collapse = ""), "</table>",
                if (!is.null(r)) paste0("<p><b>Does the population predict where industry goes next?</b> Change in a tract's active firms by the next edition, per percentage point of the predictor (tract density, population, distance and year controlled): ",
                                        paste(sprintf("%s %s", OUT[r$predictor], r$cell), collapse = "; "), ".</p>") else "",
                dec, "<p><small>Reading: Hispanic share rose in tracts as industry densified (within) and was higher where industry was dense (between); poverty followed the between pattern; Black share was unrelated at the tract scale; ",
                "foreign-born share was higher where firms had already left (legacy). In reverse, a higher foreign-born share predicted fewer new firms and higher poverty more.</small></p>")) })
  DL_FILES <- c(dl_zon_geo = "zoning_1929.geojson", dl_zon_holc = "zoning_shares_holc.csv", dl_zon_tr = "zoning_shares_tracts.csv", dl_zon_g = "holc_zoning_by_grade.csv", dl_holc_bd = "holc_boundary.csv", dl_holc_m = "holc_tract_models.csv",
                dl_sf1 = "site_fate_denver.csv", dl_sf2 = "site_fate_denver_pre1960.csv", dl_sf3 = "site_fate_summary.csv")
  DL_LAB <- c(dl_zon_geo = "1925 zoning districts, 1929 map (GeoJSON)", dl_zon_holc = "Zoning share by HOLC area (CSV)", dl_zon_tr = "Zoning share by 2010 tract (CSV)", dl_zon_g = "Zoning by HOLC grade (CSV)", dl_holc_bd = "HOLC boundary gaps with rail and zoning controls (CSV)", dl_holc_m = "Change in tract outcomes by HOLC class (CSV)",
              dl_sf1 = "Site fate: 1965-92 Denver sites on today's parcels (CSV)", dl_sf2 = "Site fate: pre-1960 Denver trades on today's parcels (CSV)", dl_sf3 = "Site fate: summary by decade of last listing (CSV)")
  for (k in names(DL_FILES)) local({ kk <- k; output[[kk]] <- downloadHandler(filename = function() DL_FILES[[kk]], content = function(f) file.copy(dd(DL_FILES[[kk]]), f)) })
  output$dl_zoning_btns <- renderUI({ have <- names(DL_FILES)[file.exists(dd(DL_FILES))]; if (!length(have)) return(tags$small(class = "text-muted", "Run R/zoning_1925.R, R/holc_covenants.R and R/site_fate.R to add these files."))
    do.call(tagList, lapply(have, function(k) tagList(downloadButton(k, DL_LAB[[k]], class = "btn-sm mb-1"), br()))) })
  output$dl_panel <- downloadHandler(filename = function() "colorado_tract_panel_1940_2020.csv", content = function(f) write.csv(den_pan, f, row.names = FALSE))

  # ---- Denver 1880-1940: reconstructed enumeration districts (R/grf_eds.R + R/denver_eds_analysis.R) with the IPUMS full count
  output$map_1880 <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addTiles("https://server.arcgisonline.com/ArcGis/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}",
               attribution = "Tiles &copy; Esri; districts reconstructed from Brown University GRF addresses; composition IPUMS USA full count; firms: Colorado State Business Directories") |>
      setView(-104.99, 39.74, 12) |> addMapPane("tr", zIndex = 380) |> addMapPane("haz", zIndex = 460) })
  output$ed_unit <- renderUI({ y <- as.integer(input$ed_year); if (is.na(y)) return(NULL)
    if (y >= 1950) tags$div(class = "alert alert-warning py-1 px-2 mb-2", tags$small(tags$b("Unit: census tracts"), " (Denver core, 2010 boundaries; interpolated before 2010). Microdata end at 1940, so the measures are the tract tables'.")) else tags$div(class = "alert alert-light py-1 px-2 mb-2", tags$small(tags$b("Unit: enumeration districts"), " reconstructed from the full count.")) })
  observeEvent(input$ed_year, { y <- as.integer(input$ed_year); if (is.na(y)) return()
    ch <- if (y >= 1950) TR_VARS else ED_VARS; cur <- input$ed_var
    map <- c(pct_black = "p_black", pct_hisp = "p_hisp", pct_fb = "p_fb", pct_owner_hh = "p_owner", median_rent = "mrent_2020", median_value = "mval_2020", p_black = "pct_black", p_hisp = "pct_hisp", p_fb = "pct_fb", p_owner = "pct_owner_hh", mrent_2020 = "median_rent", mval_2020 = "median_value")
    sel <- if (cur %in% ch) cur else if (!is.null(cur) && cur %in% names(map) && map[[cur]] %in% ch) map[[cur]] else ch[[1]]
    updateSelectInput(session, "ed_var", label = if (y >= 1950) "Tracts shaded by" else "Districts shaded by", choices = ch, selected = sel) }, ignoreInit = TRUE)
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
  output$edg_title <- renderText({ y <- as.integer(input$ed_year); sprintf("%s: %s with vs. without a hazardous firm of the preceding decade", y, if (!is.na(y) && y >= 1950) "census tracts" else "enumeration districts") })
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
      pivot_longer(-census) |> mutate(panel = ifelse(grepl("Dissim", name), "Segregation across EDs (0–1)", "Share of population (%)"))
    ggplotly(ggplot(d, aes(census, value, colour = name, group = name, text = sprintf("%s, %s: %s", name, census, value))) + geom_line() + geom_point() + facet_wrap(~panel, scales = "free_y", ncol = 1) +
               scale_x_continuous(breaks = c(1880, 1900, 1910, 1920, 1930, 1940)) + labs(x = NULL, y = NULL, colour = NULL) + theme_minimal(), tooltip = "text") |> hleg() })
  output$dl_cells <- downloadHandler(filename = function() "industrial_corridor_cells_500m.csv", content = function(f) write.csv(cells, f, row.names = FALSE))
  output$dl_1880 <- downloadHandler(filename = function() "denver_1880_eds_and_firms.zip", content = function(f) {
    td <- tempfile(); dir.create(td); file.copy(Filter(file.exists, c(dd("denver_1880_eds.csv"), dd("denver_1880_firms.csv"), dd("denver_1880_distance.csv"), dd("denver_1880_models.csv"), dd("denver_eds.geojson"), dd("denver_eds_firms.csv"), dd("ed_year_groups.csv"), dd("ed_distance_models.csv"))), td)
    old <- setwd(td); on.exit(setwd(old)); zip(f, list.files(td)) })

  # ---- Redlining & covenants (R/holc_covenants.R)
  output$map_rl <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
      addTiles("https://server.arcgisonline.com/ArcGis/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}",
               attribution = "Tiles &copy; Esri; HOLC areas &copy; Mapping Inequality (U. Richmond DSL, CC-BY-NC); covenants: Denver Public Library, Mapping Prejudice (public domain)") |>
      setView(-104.97, 39.73, 12) |> addMapPane("ed", zIndex = 370) |> addMapPane("holcp", zIndex = 390) |> addMapPane("pts", zIndex = 460) })
  observe({
    req(input$map_rl_zoom); if (is.null(holc)) return()
    px <- leafletProxy("map_rl") |> clearGroup("holc") |> clearGroup("cov") |> clearGroup("firms") |> clearGroup("ed30") |> clearGroup("zon") |> removeControl("rllegend") |> removeControl("zonlegend")
    L <- input$rl_layers
    px <- px |> removeControl("edlegend30")
    if ("ed30" %in% L && !is.null(eds_holc)) { e <- eds_holc; v <- input$rl_edvar; x <- e[[v]]
      if (v == "grade") { fc <- unname(HOLC_COL6[x]); fc[is.na(fc)] <- "#eeeeee"; px <- px |> addLegend("bottomleft", colors = unname(HOLC_COL6), labels = names(HOLC_COL6), title = "HOLC class of 1930 district", opacity = 0.7, layerId = "edlegend30") }
      else { pe <- colorBin(if (v %in% c("covenants", "firms_pre1938", "firms_1938_1956", "firms_1961_2002")) "Purples" else "Greys", domain = x, bins = 6, pretty = TRUE, na.color = "#f0f0f0"); fc <- pe(x)
        px <- px |> addLegend("bottomleft", pal = pe, values = x, title = paste0("1930 districts: ", names(c("Black (%)" = "pct_black", "Hispanic (%)" = "pct_hisp", "Foreign born (%)" = "pct_fb", "Laborers (%)" = "pct_laborers", "Racial covenants 1931-35" = "covenants", "Firms to 1937" = "firms_pre1938", "Firms 1938-56" = "firms_1938_1956", "Sites 1961-2002" = "firms_1961_2002"))[c("pct_black", "pct_hisp", "pct_fb", "pct_laborers", "covenants", "firms_pre1938", "firms_1938_1956", "firms_1961_2002") == v]), opacity = 0.8, layerId = "edlegend30") }
      px <- px |> addPolygons(data = e, fillColor = fc, fillOpacity = 0.7, color = "#999999", weight = 0.4, group = "ed30", options = pathOptions(pane = "ed"),
                              label = sprintf("ED %s (1930): HOLC %s · %s covenants · %s%% Black, %s%% Hispanic, %s%% foreign born, %s%% laborers · firms to 1937: %s, 1938-56: %s, sites 1961-2002: %s", e$ED, e$grade, e$covenants, e$pct_black, e$pct_hisp, e$pct_fb, e$pct_laborers, e$firms_pre1938, e$firms_1938_1956, e$firms_1961_2002)) }
    if ("holc" %in% L) { h <- holc; hcls <- ifelse(h$grade %in% names(HOLC_COL), h$grade, ifelse(grepl("Industrial", h$cat), "Industrial", ifelse(grepl("Commercial", h$cat), "Commercial", "ungraded"))); gcol <- unname(HOLC_COL6[hcls])
      px <- px |> addPolygons(data = h, fillColor = gcol, fillOpacity = ifelse("ed30" %in% L, 0.25, 0.45), color = gcol, weight = 2, group = "holc", options = pathOptions(pane = "holcp"),
        label = sprintf("%s (%s): %s", h$label, ifelse(hcls %in% c("Industrial", "Commercial"), paste(hcls, "zone, not graded"), paste("grade", h$grade)), esc(h$cat)),
        popupOptions = popupOptions(maxWidth = 520),
        popup = sprintf("<b>HOLC area %s \u2014 grade %s (%s)</b><br><b>Detrimental influences:</b> %s<br><b>Favorable:</b> %s<br><b>Occupation:</b> %s · <b>income:</b> %s<br><b>Foreign-born families:</b> %s · <b>Negro:</b> %s · <b>infiltration of:</b> %s · <b>relief families:</b> %s · <b>population:</b> %s<br><b>Remarks:</b> <small>%s</small><hr style='margin:4px 0'>Hazardous-trade firms inside: <b>%s</b> before the map (1871\u201337), %s in 1921\u201337, %s after (1938\u201356) · racial covenants 1931\u201335: <b>%s</b><br>1930 full count (reconstructed EDs): %s residents, Black %s%%, foreign born %s%%, Hispanic %s%%, laborers %s%% · 1940: Black %s%%, Hispanic %s%%",
                        h$label, h$grade, esc(h$cat), esc(h$detrimental), esc(h$favorable), esc(h$occupation), esc(h$income), esc(h$holc_foreign_born), esc(h$holc_negro), esc(h$infiltration), esc(h$relief), esc(h$pop_trend), esc(h$remarks),
                        h$firms_pre1938, h$firms_1921_1937, h$firms_1938_1956, h$covenants_1931_35, esc(h$pop_1930), esc(h$pct_black_1930), esc(h$pct_fb_1930), esc(h$pct_hisp_1930), esc(h$pct_laborers_1930), esc(h$pct_black_1940), esc(h$pct_hisp_1940))) |>
        addLegend("bottomright", colors = unname(HOLC_COL6[1:6]), labels = c("A \u2018best\u2019", "B \u2018still desirable\u2019", "C \u2018definitely declining\u2019", "D \u2018hazardous\u2019", "Industrial zone (not graded)", "Commercial zone (not graded)"), title = "HOLC 1938", opacity = 0.7, layerId = "rllegend") }
    if ("zon" %in% L && !is.null(zon)) { zc <- unname(ZON_COL[zon$zone]); zc[is.na(zc)] <- "#999999"
      px <- px |> addPolygons(data = zon, fillColor = zc, fillOpacity = 0.55, color = zc, weight = 1, group = "zon", options = pathOptions(pane = "holcp"), label = sprintf("1925 zoning (1929 map): %s district, %s km² in all", zon$zone, zon$km2)) |>
        addLegend("topleft", colors = unname(ZON_COL), labels = paste(names(ZON_COL), "district"), title = "1925 zoning (1929 map)", opacity = 0.7, layerId = "zonlegend") }
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
               scale_fill_manual(values = c(A = "#4d8a3a", B = "#3b8fa0", C = "#c9a800", D = "#c0392b", Industrial = "#7f7f7f", Commercial = "#b07cb0")) + labs(x = "Share (%)", y = NULL, fill = "HOLC class") + theme_minimal(), tooltip = "text") |> hleg() })
  output$t_hmda <- renderTable({ if (is.null(hmda_g)) return(data.frame(Note = "Run R/fetch_hmda.R to add HMDA 2018-21 lending by grade."))
    hmda_g |> transmute(Grade = grade, Tracts = tracts, Applications = apps, `Denial rate %` = denial_rate, `Black denial %` = black_denial_rate, `Hispanic denial %` = hisp_denial_rate, `Hispanic share of applicants %` = pct_apps_hisp, `Black share %` = pct_apps_black, `Median loan $k` = median_loan_k, `Median income $k` = median_income_k) }, striped = TRUE, spacing = "xs")
  output$hmda_note <- renderUI({ if (is.null(hmda_m)) return(NULL)
    HTML(paste0("<small>Denial rate vs grade A, applicant income controlled (tracts with 30+ applications, weighted by applications): ", paste(sprintf("%s %+.1f pts (p = %.3f)", hmda_m$term, hmda_m$b, hmda_m$p), collapse = "; "), ".</small>")) })
  output$t_edcls <- renderTable({ if (is.null(ed_cls)) return(NULL)
    ed_cls |> filter(census == 1930) |> transmute(`HOLC class` = grade, `Covenants 1931-35` = ifelse(has_covenant, "yes", "none"), EDs, Population = population, `Black % 1930` = pct_black, `Hispanic % 1930` = pct_hisp, `Foreign born %` = pct_fb, `Laborers %` = pct_laborers,
                                                 `Firms to 1937 (per 10k)` = sprintf("%d (%.1f)", firms_pre1938, firms_per_10k_pre1938), `Firms 1938-56 (per 10k)` = sprintf("%d (%.1f)", firms_1938_1956, firms_per_10k_1938_56), `Sites 1961-2002 (per 10k)` = sprintf("%d (%.1f)", firms_1961_2002, firms_per_10k_1961_2002)) }, striped = TRUE, spacing = "xs")
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
               scale_colour_manual(values = c(A = "#4d8a3a", B = "#3b8fa0", C = "#c9a800", D = "#c0392b")) + scale_linetype_manual(values = c("HOLC areas (districts area-weighted)" = "dashed", "2010 tracts by dominant grade" = "solid"), guide = "none") + scale_x_continuous(breaks = xb) + labs(x = NULL, y = lab, colour = "HOLC grade") + theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1)), tooltip = "text") |> gradeleg() |> plotly::layout(legend = list(orientation = "h", x = 0, y = 1.12, yanchor = "bottom"), margin = list(t = 60)) })
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
      addTiles("https://server.arcgisonline.com/ArcGis/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", attribution = "Tiles &copy; Esri; parcels: City and County of Denver open data") |> setView(-104.99, 39.75, 12) |>
      addLegend("bottomright", colors = unname(USE_COL[1:6]), labels = names(USE_COL)[1:6], title = "Parcel use today", opacity = 0.9) })
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
  output$t_sf_zone <- renderTable({ if (is.null(sf_zone)) return(NULL); sf_zone |> transmute(Series = ifelse(grepl("Manufact", series), "1965-92 sites", "1891-1956 trades"), Sites = n, `Zoned industrial %` = pct_zone_industrial, `Rebuilt %` = pct_redeveloped, `Median year built` = as.integer(median_year_built)) }, striped = TRUE, spacing = "xs")
  output$t_sf_dec <- renderTable({ if (is.null(sf_sum)) return(NULL); ser <- if (identical(input$sf_series, "H")) "Business" else "Manufact"
    d <- sf_sum |> filter(grepl(ser, series), use_now %in% names(USE_COL)[1:6]) |> group_by(last_decade) |> mutate(sites = sum(n)) |> ungroup() |> transmute(`Last listed` = last_decade, sites, use_now, pct) |> tidyr::pivot_wider(names_from = use_now, values_from = pct, values_fill = 0) |> arrange(`Last listed`)
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
    "The ratio follows 'pages scanned' (about 40 listings per page in every edition): the twelve editions held only in part (see the Data & downloads tab) are the thin years, and listings without an industry code (1993: 37%) drop out of the sector counts. Edition-to-edition swings are therefore scan coverage, not industrial change."))
  output$p_bm_cty <- renderPlotly({ if (is.null(bm_cty) || is.null(input$bm_year) || input$bm_year == "") return(NULL); h <- isTRUE(input$bm_haz)
    d <- bm_cty |> filter(year == as.integer(input$bm_year)) |> mutate(dir = if (h) dir_haz else dir_mfg, cbp = if (h) cbp_haz else cbp_mfg)
    ggplotly(ggplot(d, aes(cbp, dir, text = sprintf("%s: CBP %d, directory %d (%d at a street address)", county_name, cbp, dir, dir_street))) + geom_abline(slope = 1, intercept = 0, colour = "grey60", linetype = "dashed") + geom_point(colour = "#d1491f", alpha = 0.8, size = 2.5) +
               scale_x_log10() + scale_y_log10() + labs(x = "CBP establishments (log scale)", y = "Directory establishments (log scale)") + theme_minimal(), tooltip = "text") })
  output$t_bm_cty <- renderTable({ if (is.null(bm_cty) || is.null(input$bm_year) || input$bm_year == "") return(NULL); h <- isTRUE(input$bm_haz)
    bm_cty |> filter(year == as.integer(input$bm_year)) |> arrange(desc(cbp_mfg)) |> head(12) |> transmute(County = county_name, CBP = if (h) cbp_haz else cbp_mfg, Directory = if (h) dir_haz else dir_mfg, `Street-level` = dir_street, Ratio = round(Directory / pmax(CBP, 1), 2)) }, striped = TRUE, spacing = "xs")
  output$t_bm_at <- renderTable({ if (is.null(bm_at)) return(NULL); bm_at |> filter(year == 1880) |> transmute(Sector = ifelse(hazardous, paste0(sector, " *"), sector), Establishments = as.integer(establishments), Workers = as.integer(workers), `Capital ($)` = format(round(capital), big.mark = ",")) }, striped = TRUE, spacing = "xs")
  output$bm_nh <- renderUI({ if (is.null(bm_nh)) return(tags$small(class = "text-muted", "Not yet built: run Rscript R/benchmarks.R with an NHGIS key to add the 1880-1940 comparison."))
    d <- bm_nh |> group_by(Census = as.integer(census)) |> summarise(Counties = n(), `Census mfg. establishments` = sum(mfg_estab, na.rm = TRUE), `Directory hazardous trades` = sum(dir_haz), `r (log)` = round(cor(log1p(mfg_estab), log1p(dir_haz)), 2), .groups = "drop")
    renderTable(d, striped = TRUE, spacing = "xs")() })
  output$t_holc_m <- renderTable({ if (is.null(holc_m)) return(NULL)
    holc_m |> filter(outcome == input$rl_mvar) |> mutate(star = ifelse(p < 0.01, "**", ifelse(p < 0.05, "*", "")), Outcome = c(p_black = "Black %", p_hisp = "Hispanic %", p_pov = "Poverty %", p_owner = "Owner-occupied %", lmval = "log median home value (2020 $)")[outcome]) |>
      transmute(Outcome, Period = period, `Class (vs A)` = grade, Change = sprintf("%+.1f%s", b, star), SE = round(se, 1), Tracts = n,
                `Net of 1925 zoning` = if ("b_zone" %in% names(holc_m)) ifelse(is.na(b_zone), "", sprintf("%+.1f%s", b_zone, ifelse(p_zone < 0.01, "**", ifelse(p_zone < 0.05, "*", "")))) else NULL) }, striped = TRUE, spacing = "xs")
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
    "Where a pre-1960 firm reappears in the 1961–2002 directory with an address, that address is used.</p>")))
  output$valid <- renderTable(validation)
}

shinyApp(ui, server)
