# Colorado Hidden Hazards — explore historical hazardous manufacturing sites (Colorado Directory of Manufacturers,
# 1961–2002, and hazardous trades in Colorado State Business Directories, 1877–1950), current EPA TRI facilities, cleanup sites, schools and health facilities, and CDPHE EnviroScreen 2.0.
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
tracts  <- st_read(dd("enviroscreen_tracts.geojson"), quiet = TRUE) |> mutate(GEOID = as.character(GEOID))
by_year_dir <- if (dir.exists(dd("by_year"))) dd("by_year") else file.path("..", "data", "by_year")
validation  <- local({ f <- c(dd("geocoding_validation_frs.csv"), "../data/results/geocoding_validation_frs.csv"); f <- f[file.exists(f)]
                       if (length(f)) read.csv(f[1]) else NULL })

STATUS <- c("Not on any list", "Cleanup / contamination list", "TRI reporter", "RCRA hazardous-waste handler",
            "Solid waste facility", "Other EPA permit only")
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

# ---------------------------------------------------------------- UI
filters <- list(
  sliderInput("yrs", "Listed in a directory between", min = 1877, max = 2002, value = c(1877, 2002), sep = "", step = 1),
  helpText("1877–1950: hazardous trades in the Colorado State Business Directory (brown). 1961–2002: Directory of Colorado Manufacturers."),
  checkboxGroupInput("sec", "Sector (Frickel & Elliott)", SECTORS, selected = SECTORS[1:7]),
  checkboxGroupInput("st", "Current regulatory status", STATUS, selected = STATUS),
  radioButtons("colby", "Colour sites by", c("Regulatory status" = "status", "Persistence (years listed)" = "span"), inline = FALSE),
  sliderInput("minspan", "Persisted at least (years between first and last listing)", 0, 125, 0, step = 1),
  checkboxInput("htown", "Include pre-1960 listings placed only at the town centre", TRUE),
  checkboxGroupInput("cf", "Confidence (location + industry)", c("High" = "high", "Medium" = "medium", "Low" = "low"),
                     selected = c("high", "medium", "low"), inline = TRUE),
  helpText("High = street-level geocode and an industry code printed in the directory. ",
           "'Not on any list' = no match in EPA FRS, TRI, RCRA, Superfund, brownfield or CDPHE cleanup inventories.")
)

ui <- page_navbar(
  title = "Colorado Hidden Hazards",
  theme = bs_theme(version = 5, bootswatch = "flatly", primary = "#24589e", base_font = font_google("Public Sans", local = FALSE)),
  sidebar = do.call(sidebar, c(list(width = 300), filters)),
  nav_panel("Map",
    layout_columns(col_widths = c(9, 3),
      card(full_screen = TRUE, card_body(padding = 0, leafletOutput("map", height = "78vh"))),
      card(card_header("EnviroScreen layer"),
           selectInput("esvar", "Shade census tracts by", VARS, selected = "enviroscreen_pctl"),
           sliderInput("esop", "Opacity", 0, 1, 0.45, step = 0.05),
           hr(),
           tags$b("Sites shown"), textOutput("nsites"),
           tags$small(class = "text-muted",
             "Use the layer control (top right of the map) to add TRI facilities, schools, hospitals, clinics, ",
             "residential care, brownfields and other cleanup sites. Click any point for details.")))),
  nav_panel("Trends",
    layout_columns(col_widths = c(6, 6),
      card(card_header("Hazardous-sector sites listed per directory edition, by sector"), plotlyOutput("p_sector", height = 420)),
      card(card_header("…by current regulatory status"), plotlyOutput("p_status", height = 420))),
    card(card_header("Share of listed sites on no current inventory"), plotlyOutput("p_share", height = 300)),
    tags$small(class = "text-muted", "Editions are irregular (25 between 1961 and 2002); 1971, 1985, 1992 and 2002 volumes are partial."),
    card(card_header("Before 1960: hazardous-trade firms listed per Colorado State Business Directory edition"), plotlyOutput("p_hist", height = 360),
         tags$small(class = "text-muted", "Counts come from searchable text of the scanned directories and are not comparable to the manufacturers' directory: ",
                    "the business directories list every trade and their OCR quality varies by edition. 1891 and 1910–1939 include large Denver sections.")),
    ),
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
             "Tract groups use the sites selected in the sidebar. A tract 'has' a site if the site's geocode falls inside it. ",
             "Tract-level comparisons describe places, not the people living next to a given site (ecological fallacy).")),
      card(card_header(textOutput("cmp_title")), plotlyOutput("p_cmp", height = 380),
           card_header("All indicators: medians, means and Wilcoxon rank-sum test"), DTOutput("t_cmp")))),
  nav_panel("Nearby schools & health care",
    layout_columns(col_widths = c(3, 9),
      card(card_header("Sensitive places near potentially unknown sites"),
           sliderInput("buf", "Distance (m)", 100, 2000, 500, step = 100),
           checkboxGroupInput("recv", "Include", c("Public school", "Non-public school", "Hospital", "Clinic", "Residential & long-term care"),
                              selected = c("Public school", "Non-public school", "Hospital", "Clinic", "Residential & long-term care")),
           tags$small(class = "text-muted", "Uses sites with status 'Not on any list' among those selected in the sidebar."),
           hr(), tableOutput("recv_sum")),
      card(DTOutput("t_recv")))),
  nav_panel("Data & downloads",
    layout_columns(col_widths = c(4, 8),
      card(card_header("Geocoded directory listings by edition"),
           selectInput("dl_year", "Edition", sort(as.integer(sub("CO_DCM_(\\d+)_geocoded.csv", "\\1", list.files(by_year_dir, "CO_DCM_.*csv"))))),
           downloadButton("dl_one", "Download edition CSV"), br(), br(),
           downloadButton("dl_sites", "Download sites matching current filters"), br(), br(),
           downloadButton("dl_hist", "Download pre-1960 hazardous-trade firms (1877–1950)"),
           hr(), tags$small("Each edition file lists every manufacturer with its OCR'd name and address, SIC/NAICS codes, ",
                            "sector flags, establishment and site IDs, coordinates and geocode level.")),
      card(card_header("How reliable are the locations?"), uiOutput("geo_note"), tableOutput("valid"))))
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
            popup = sprintf("<b>%s</b><br>%s %s<br>%s<br><i>%s</i>", esc(d$name), esc(d$address), esc(d$city), k, esc(d$source)),
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
    m |> addLayersControl(baseGroups = c("Light grey", "OpenStreetMap", "Satellite"),
          overlayGroups = c("Historical hazardous sites", "Pre-1960 hazardous trades", "EnviroScreen tracts", "EPA TRI facilities", "Schools", "Hospitals", "Clinics",
                            "Residential & long-term care", CLEAN_LAYERS),
          options = layersControlOptions(collapsed = FALSE)) |>
      hideGroup(c("Schools", "Hospitals", "Clinics", "Residential & long-term care", "Environmental covenants / land-use controls",
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
    pop <- sprintf("<b>%s, %s</b><br><b>%s</b> · %s confidence<br>Hazardous use in %s editions, %s–%s (%s years)<br>Listed %s–%s (in range: %s)<br><b>Hazardous firms:</b><br>%s<br><b>Sectors:</b> %s %s%s<br><b>Nearest inventory record:</b> %s<br><small>%s · %.5f, %.5f</small>",
                   esc(s$address), esc(s$city), esc(s$radar), esc(s$confidence), s$n_editions, s$haz_first, s$haz_last, s$span_years,
                   s$first_year, s$last_year, esc(s$years_in_range),
                   gsub(" \\| ", "<br>", esc(s$hazard_firms)), esc(s$fe_sectors), esc(s$ext_sectors),
                   ifelse(is.na(s$hist_first_year), "", sprintf("<br><b>Pre-1960 precursor (since %s):</b> %s", s$hist_first_year, esc(s$hist_names))),
                   ifelse(s$known_match == "" | is.na(s$known_match), "none", esc(s$known_match)), s$site_id, s$lat, s$lon)
    if (input$colby == "span") {
      cls <- cut(s$span_years, SPAN_BREAKS, SPAN_LABELS)
      fill <- SPAN_COL[as.integer(cls)]; rad <- 3 + 1.2 * sqrt(s$n_editions)
      ring <- ifelse(s$radar == "Not on any list", "#d1491f", "#ffffff"); ringw <- ifelse(s$radar == "Not on any list", 1.6, 0.8)
      leg <- list(colors = SPAN_COL, labels = SPAN_LABELS, title = "Persistence of hazardous use<br><small>size = editions listed; orange ring = on no list</small>")
    } else {
      fill <- unname(STATUS_COL[s$radar]); rad <- ifelse(s$radar == "Not on any list", 5, 4); ring <- "#ffffff"; ringw <- 1
      leg <- list(colors = unname(STATUS_COL), labels = names(STATUS_COL), title = "Historical site status")
    }
    n <- nrow(s); rad <- rep_len(rad, n); ring <- rep_len(ring, n); ringw <- rep_len(ringw, n); fill <- rep_len(fill, n)
    o <- order(s$span_years)
    leafletProxy("map") |> clearGroup("Historical hazardous sites") |> removeControl("sitelegend") |>
      addCircleMarkers(lng = s$lon[o], lat = s$lat[o], radius = rad[o], stroke = TRUE, weight = ringw[o], color = ring[o],
                       fillColor = fill[o], fillOpacity = 0.9, popup = pop[o], group = "Historical hazardous sites",
                       options = pathOptions(pane = "haz")) |>
      addLegend("bottomleft", colors = leg$colors, labels = leg$labels, title = leg$title, opacity = 1, layerId = "sitelegend")
  })

  # ---- pre-1960 layer
  sel_hist <- reactive({
    if (is.null(hist)) return(NULL)
    h <- hist |> filter(last_year >= input$yrs[1], first_year <= input$yrs[2], (last_year - first_year) >= input$minspan)
    if (!isTRUE(input$htown)) h <- h |> filter(precision != "town")
    if (length(input$sec)) h <- h[sapply(strsplit(h$app_sectors, ";"), function(x) any(x %in% input$sec)), ] else h <- h[0, ]
    h
  })
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
    if (nrow(tw)) px <- px |> addCircleMarkers(data = tw, ~lon, ~lat, radius = 4, color = ring(tw), weight = ifelse(tw$persists_to_1961plus, 2, 0.8),
                    fillColor = HIST_COL, fillOpacity = 0.55, popup = pop(tw), group = "Pre-1960 hazardous trades",
                    clusterOptions = markerClusterOptions(maxClusterRadius = 25, spiderfyOnMaxZoom = TRUE), options = pathOptions(pane = "haz"))
    if (nrow(st)) px <- px |> addCircleMarkers(data = st, ~lon, ~lat, radius = 3 + 1.2 * sqrt(st$editions), color = ring(st),
                    weight = ifelse(st$persists_to_1961plus, 2, 0.8), fillColor = HIST_COL, fillOpacity = 0.95, popup = pop(st),
                    group = "Pre-1960 hazardous trades", options = pathOptions(pane = "haz"))
    px |> addLegend("bottomleft", colors = c(HIST_COL, HIST_COL), labels = c("Street address (Denver 1891+, larger cities 1910+)", "Town centre only (clustered)"),
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
  output$p_status <- renderPlotly({
    d <- sy_sel() |> count(year, radar) |> mutate(radar = factor(radar, STATUS))
    ggplotly(ggplot(d, aes(year, n, fill = radar)) + geom_col(width = 0.8) + scale_fill_manual(values = STATUS_COL) +
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
    w <- if (isTRUE(input$popw)) d$population else NULL
    cols <- c("#d1491f", "#24589e", "#7a4aa8", "#7f8c8d"); names(cols) <- unique(d$group)
    p <- if (input$ptype == "dens")
      ggplot(d, aes(val, fill = group, colour = group, weight = if (is.null(w)) 1 else population)) + geom_density(alpha = 0.25, adjust = 0.9)
    else ggplot(d, aes(group, val, fill = group, weight = if (is.null(w)) 1 else population)) + geom_boxplot(alpha = 0.5, outlier.size = 0.6)
    ggplotly(p + scale_fill_manual(values = cols) + scale_colour_manual(values = cols) +
               labs(x = if (input$ptype == "dens") names(VARS)[VARS == input$nvar] else NULL, y = NULL, fill = NULL, colour = NULL) +
               theme_minimal() + theme(legend.position = "bottom"))
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

  # ---- downloads
  output$dl_one <- downloadHandler(filename = function() sprintf("CO_DCM_%s_geocoded.csv", input$dl_year),
                                   content = function(f) file.copy(file.path(by_year_dir, sprintf("CO_DCM_%s_geocoded.csv", input$dl_year)), f))
  output$dl_sites <- downloadHandler(filename = function() "CO_hazardous_sites_filtered.csv",
                                     content = function(f) write.csv(sel_sites(), f, row.names = FALSE))
  output$dl_hist <- downloadHandler(filename = function() "CO_pre1960_hazardous_sites.csv",
                                    content = function(f) write.csv(if (is.null(hist)) data.frame() else hist, f, row.names = FALSE))
  output$geo_note <- renderUI(HTML(paste0(
    "<p>Addresses were OCR'd from scanned directories and geocoded offline against US Census TIGER/Line 2023 address ranges. ",
    "<b>address</b> = house number interpolated on the matching street segment; <b>address_approx</b> = street found only after OCR correction, ",
    "in a neighbouring ZIP, or at the nearest segment end (check before field work). Listings that could only be placed at a ZIP or city ",
    "centroid are in the edition CSVs but not on the map.</p>",
    "<p>Check against independent coordinates: for directory addresses that also appear in EPA's Facility Registry, the distance between ",
    "the two coordinates is summarised below. Street renumbering since the 1960s and OCR errors in house numbers are the main error sources.</p>",
    "<p><b>Pre-1960 layer.</b> Business-directory entries are placed at a street address only for Denver from 1891 (after the city's 1887 ",
    "renumbering) and for larger cities from 1910, and only when the house number falls inside a current TIGER address range; old street names ",
    "(e.g. Holladay → Market) are translated. Everything else sits at the USGS GNIS point for the town and is drawn as a cluster. ",
    "Where a pre-1960 firm reappears in the 1961–2002 directory with an address, that address is used.</p>")))
  output$valid <- renderTable(validation)
}

shinyApp(ui, server)
