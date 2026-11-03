# Archival follow-up worklist for hidden conversions: the cases the paper (Section 6) names for a records check.
#   Rscript R/archival_followup.R      (after R/site_fate.R)  -> data/results/site_fate/archival_followup_hidden_conversions.csv
# Rows:
#   manufacturers 1965-92: Denver hazardous-sector sites now in residential, civic/school/health or park use that match no record in the
#                          searched inventories (radar = "Not on any list");
#   business directory 1891-1956: street-located pre-1960 hazardous trades in Denver whose parcel is now residential.
# For each: the Sanborn edition to check and the Polk reverse-directory years (last listing and five years on); the last three columns
# are left empty for the archival reader to fill.
suppressPackageStartupMessages(library(data.table))
D <- "data/results/site_fate"
S <- fread(file.path(D, "site_fate_denver.csv"))
P <- fread(file.path(D, "site_fate_denver_pre1960.csv"))
a <- S[use_now %in% c("Residential", "Civic / school / health", "Park / open space") & radar == "Not on any list",
       .(series = "manufacturers 1965-92", id = site_id, name_or_address = address, sectors = fe_sectors, first_year, last_year,
         parcel_class_today = D_CLASS_CN, use_now, year_built, units = TOT_UNITS, lat, lon,
         sanborn_edition_to_check = "1950-51 (LoC listed, not online; DPL)")]
b <- P[use_now == "Residential",
       .(series = "business directory 1891-1956", id = hfirm, name_or_address = paste0(name, ", ", street), sectors, first_year, last_year,
         parcel_class_today = D_CLASS_CN, use_now, year_built, units = TOT_UNITS, lat, lon,
         sanborn_edition_to_check = ifelse(first_year <= 1910, "1904 (LoC online)", "1929-30 or 1950-51 (DPL)"))]
W <- rbind(a, b)
W[, directory_years_to_check := sprintf("Polk reverse directory %d and %d", last_year, last_year + 5L)]
W[, `:=`(sanborn_use = "", reverse_directory_occupants = "", notes = "")]
setorder(W, series, -last_year, id)
fwrite(W, file.path(D, "archival_followup_hidden_conversions.csv"))
message(sprintf("archival follow-up: %d later sites on no inventory now residential/civic/park (%s), %d pre-1960 trades now residential",
                nrow(a), paste(names(table(a$use_now)), table(a$use_now), sep = " ", collapse = ", "), nrow(b)))
