# tests/stages — one suite per pipeline stage (review 4, 12–13 November 2026)

Each file checks one group of stages: row conservation between a stage's input and output, key uniqueness, references to the
previous stage, ranges and units, sums and shares, and results recomputed a second way from the committed files. They read only
committed files; tests that need `work/` or the restricted inputs (death records, person-level census and CenSoc files) skip
when those are absent, so more of them run on the analyst's machine than in CI.

```bash
python3 -m pytest tests/stages -p no:cacheprovider      # ~50 s; also part of tests/run_tests.sh
```

`stages.yml` declares every stage with its script, inputs and outputs; a test fails if a committed file under `data/results`,
`data/historical`, `data/by_year` or `app/data` is not the declared output of exactly one stage (or a declared copy).
`new_claims.yml` adds claims (same format as `tests/outputs/claims.yml`) for README, app and manuscript numbers that had none.

## Known defects (strict xfail)

A test marked `xfail(strict=True)` documents a defect found in review 4: it fails against the current files, and it starts
failing the suite the moment the defect is fixed, at which point the marker is removed. Do not weaken these tests.

### A. 1961–2002 directory: OCR, parsing, SIC codes, linking — `test_stage_A_digitize.py`

- `test_listing_csv_has_no_formula_leading_cells_and_same_names_as_by_year`: FINDING E5: export_by_year.py strips leading = + @ - from firm names and streets, export.py does not, so 122 firm names differ between the tw
- `test_edition_without_printed_codes_has_no_directory_codes`: FINDING R2: 27 listings of the 1966 edition (which prints no codes) carry sic_source='directory': a house number read as a SIC code with the street as its 
- `test_no_naics_codes_in_sic_era_editions`: FINDING R2: three 1990/1992 listings carry a 'NAICS code' that is their house number or ZIP (11705 Teller St -> naics 11705; ZIP 81230 -> naics 81230); parse_para's NAICS ru
- `test_printed_codes_are_mining_or_manufacturing_codes`: FINDING E3: 2.6% of the printed codes of 1965 fall in major groups that no manufacturers' directory uses (44xx, 49xx, 84xx...): unvalidated OCR digit errors / s
- `test_classifier_normalises_training_and_query_text_the_same_way`: FINDING R8: training text keeps ' AND ' (sic_classifier.norm), query text drops it (sic_classifier_norm.norm)
- `test_no_listing_printed_in_two_volumes_of_one_edition`: FINDING E1: the scans of part 1 and part 2 overlap by one or two pages in 1966, 1970, 1977 and 1983 (e.g. DCM_1977_part1 p52-53 = DCM_1977_part2 p2-3); both co
- `test_every_listing_has_a_firm_name`: FINDING E4: 807 published listings have no firm name (record fragments split off by the block parser; 288 of them flagged F&E hazardous), 281 in 1970 alone
- `test_no_town_holds_many_listings_in_one_edition_only`: FINDING E2: town headings mis-carried: 1965 files 107 listings under AIR FORCE ACADEMY, 101 under ALLENSPARK, 57 WOODLAND PARK, 40 LA PLATA, 36 TIMNATH and none
- `test_readme_counts_of_code_corrections_match_the_log_columns`: FINDING E6: README says 795 codes corrected and 382 listings' hazardous codes removed; the current records.pkl logs 929 corrected codes (914 listings) a

### B. Geocoding, sites, inventory matching (known / hidden) — `test_stage_B_geocode_sites.py`

- `test_addresspoint_sample_is_drawn_from_the_published_editions`: FINDING 5: 555 of the 1,000 sampled rows in geocoding_validation_addresspoints.csv are listings from editions outside the published 13 (sample dra
- `test_addresspoint_recheck_site_ids_are_current`: FINDING 5: site ids in geocoding_validation_addresspoints_recheck.csv are from an earlier build; 66 of 400 no longer exist and none of the other 334 is the same 
- `test_no_inventory_record_is_dropped_for_bad_coordinates`: FINDING 2: build_reg.py drops 275 inventory records whose coordinates are (0,0) or outside Colorado (121 CDPHE voluntary-cleanup sites, 69 CDPHE RCRA ha
- `test_zip_centroids_lie_in_their_zip`: FINDING 6: ZIP "centroids" are medians of inventory coordinates with no minimum count (103 rest on one record); several lie 50-460 km from the ZIP's own TIGER streets (8106
- `test_no_hidden_site_has_a_same_name_record_without_coordinates`: FINDING 3: 9 hidden F&E sites have an inventory record of the same firm in the same town or ZIP that has no coordinates (528 FRS cleanup-tier and

### C. Pre-1960 business-directory layer — `test_stage_C_pre1960.py`

- `test_no_extracted_entry_is_dropped_without_a_verdict`: FINDING 1: 2,860 of 10,387 extracted entries have no town, received no review verdict and are dropped at geocoding (precision 'none'); a sample of 40 suggests ab
- `test_every_review_row_matches_an_entry`: FINDING 8: 48 street_review.csv rows (39 not_works, 6 doubtful, 3 ok) match no entry of the current parse and are skipped silently by apply_review (`if i is None: continue`)
- `test_homonym_towns_are_in_the_county_the_directory_names`: FINDING 4: homonym towns take the wrong gazetteer point: COLORADO CITY (El Paso Co. until 1917) is put at today's Colorado City in Pueblo Co.; GOLD HILL 1879
- `test_readme_unplaced_count`: FINDING 7: README says 87 listings are left unplaced; the review files send 86 rows to towns without a gazetteer point, which are 79 listings after de-duplication, 22 of them from 1911-19
- `test_identical_name_in_one_town_is_one_firm_location`: FINDING 3: firms whose name is made of trade/place words (nk empty: Vulcan Iron Works Co, Trinidad Sheet Metal Works, American Smelting & Refining Co ...) are ne
- `test_same_name_at_the_same_point_is_one_firm_location`: FINDING 3: 416 street-level firm-locations occupy 360 distinct points (Denver F&E: 266 on 235); e.g. Trinidad Sheet Metal Works at 116 E Plum is three firm-loca
- `test_linked_sites_exist_in_the_published_site_file`: FINDING 6: 4 of the 159 linked 'later sites' (S00263, S01259, S01297, S01453) are not in app/data/sites.csv, the published site file: name links take site_id from 
- `test_radium_firms_match_the_reviewed_layer`: FINDING 2: app/data/radium_firms.csv (written 1 Nov) predates the 3 Nov review: it lists 53 business-directory firm-places, the reviewed layer has 18 radium firm-locations

### D. Census layers: 1880 Denver, districts, counties, tracts — `test_stage_D_census.py`

- `test_readme_1880_firm_count_matches_listings`: FINDING 6: README says 108 firms in the 1878-85 directories; the listings file has 135 Denver listings (113 firms), 71 with a street (the number the script's own summary 
- `test_1880_firm_placed_at_its_own_printed_address`: FINDING 5: 3 of the 1878-79 firms carry their own address in the name (404 Lawrence, 377 Larimer, 433 Blake) but are placed at a neighbouring entry's address (443 Hol
- `test_ed_firm_count_same_in_models_and_shares`: FINDING 2: ed_distance_models.csv counts every firm of the window (98 in 1920, 24 in 1930), ed_firm_shares.csv only those inside a district (97, 23): HF04293 (4950 Jackso
- `test_ed_firms_of_the_decade_are_listed_in_the_decade`: FINDING 3: 6 of the 24 firms of 1930 and 2 of the 44 of 1940 have no directory listing in the ten years ending at the census; they are carried by first_year <= ce
- `test_ed_model_n_is_the_number_of_districts_in_the_model`: FINDING 4: the EDs column of the per-census rows is the number of districts with population, not the model's n: 6 rows (owner households 1920/1930/1940, hazard
- `test_tract_pooled_se_allows_for_repeated_tracts`: FINDING 8: the pooled 1950-2020 tract rows use HC1 although each of the 147 tracts enters up to 8 times; tract-clustered SEs are 1.4-2.1 times the published ones (p_hi
- `test_tract_models_firm_count_is_the_study_area_count`: FINDING 7: the firms column of denver_tracts_models.csv is the statewide count of the window (139 in 1950, 2,357 in 2000), not the firms in the 147 study tracts (
- `test_tract_firms_of_the_decade_have_a_hazardous_listing_in_the_decade`: FINDING 1: sites are taken by first_year <= end & last_year >= start of ALL their listings: 10-17% of the 'hazardous firms of the decade' 1970-20
- `test_benchmark_county_ratios_are_finite`: FINDING 12: ratio_mfg is dir_mfg / cbp_mfg with no guard, so 10 county rows with no CBP manufacturer hold 'Inf' (ratio_haz uses pmax(cbp_haz, 1))
- `test_nhgis_benchmark_one_row_per_county_and_census`: FINDING 11: nhgis_mfg_vs_directory.csv has two 1890 rows keyed county 049 'Grand' (4 and 0 establishments): cause not verifiable without the NHGIS extract; gisjoin_

### E. HOLC, zoning 1929–2023, rezoning, land use, highways, corridors, context — `test_stage_E_holc_zoning.py`

- `test_holc_dc_ratio_and_density_use_unrounded_area`: FINDING 4: holc_covenants.R:172/183/185 divides by km2 already rounded to 1 decimal; the 1965-80 D/C ratio is 13.9 (published 13.8) and four per_km2_per_edition
- `test_abc_land_total_is_rounded_after_summing`: FINDING 8: the manuscript's 'HOLC A, B and C land (54.0 km2)' is the sum of three rounded areas (5.7 + 13.3 + 35.0); the land itself is 54.06 km2, i.e. 54.1
- `test_no_denver_site_on_both_sheets_is_lost_at_a_tract_boundary`: FINDING 3: the simplified app tract layer (median 8 vertices per tract) leaves 91 sliver gaps inside Denver County; street-located points on tract 
- `test_denver_tract_polygons_tile_the_county`: FINDING 3: app/data/co_tracts_2010.geojson is used as an analysis geometry but its simplified tracts neither tile Denver County (91 interior slivers, 0.72 km2) nor avo
- `test_every_placed_rezoning_has_a_tract`: FINDING 3: 7 placed rezonings (all placed at street crossings, i.e. on tract boundaries) lie in no polygon of the simplified tract layer and so get no tract, no race count
- `test_corridors_tract_area_is_aligned_with_the_merged_table`: FINDING 1: corridors.R assigns st_area(tr) (file order) to TT after merge() has sorted TT by GEOID; the tract file is not in GEOID order, so the log-de
- `test_petroleum_by_use_now_uses_the_current_parcel_match`: FINDING 2: rerun_results.sh runs context_layers before site_fate, so context_layers read the previous run's site_fate_denver_pre1960.csv (old hfirm ids): 
- `test_rerun_order_runs_site_fate_before_context_layers`: FINDING 2: step order in rerun_results.sh (context_layers precedes site_fate, whose two output files it reads)
- `test_zoning_tract_paths_follow_the_same_tracts_in_every_census`: FINDING 7: zoning_tract_paths.csv compares 7 tracts in 1970 and 2020 with 6 in 1990 ('Industrial in 1929, not today'; 86/86/87 for 'Neither') becau

### F. Site fate, archival follow-up, hedonic, ownership, housing conditions — `test_stage_F_sitefate_property.py`

- `test_same_street_and_side_match_is_not_blocks_away`: FINDING 2: S07797 '267 W ALAMEDA AVE' sits on the parcel 3301 W ALAMEDA AVE (3,034 house numbers away, labelled 'same street and side'): the site's addre
- `test_m_imx_parcels_are_flagged_industrial`: FINDING 3: the M-IMX branch of the regex never fires on ZONE_ID (the service writes 'MIX'), so the M-IMX-5 parcel is not flagged industrial although the script an
- `test_manuscript_dwelling_units_count_each_parcel_once`: FINDING 1: '171 ... residential parcels holding 5,637 dwelling units' sums TOT_UNITS over sites; the 171 sites stand on 168 parcels (one 260-unit buil

### G. Health, mortality, CenSoc, enlistment, linked residential histories — `test_stage_G_health_censoc.py`

- `test_block_models_keep_the_share_of_deaths_the_text_states`: FINDING 1: the block models keep 132,051 of the 167,049 natural-cause deaths (79.0%; block groups keep 95.0%) but the text gives only the 95% block m
- `test_redevelopment_summary_names_its_sample_correctly`: FINDING 6: mortality_redevelopment_summary.md is headed 'Denver study area' but R/mortality_redevelopment.R models the City and County of Denver only (the
- `test_nearest_neighbour_cap_does_not_truncate_the_kernel_redevelopment`: FINDING 5: R/mortality_redevelopment.R asks RANN::nn2 for at most 400 neighbours within 2 km, but up to 433 of the 1,378 Denver sites lie 
- `test_python_health_scripts_define_the_placebo_as_the_R_scripts_do`: FINDING 3: pipeline/health/build_exposures.py and mortality_bg.py build the placebo without the SIC 20-39 filter that the three R scripts appl

### H. Paper, supplement, app, README claims, run scripts, stage manifest — `test_stage_H_publication.py`

- `test_new_claim[h_readme_pre1960_placement_location_errors]`: FINDING 4: the check file has 11 'wrong address' + 2 'out of town' = 13 location errors (22%); 20 is reached only by adding the 7 'doubtful' rows, whic
- `test_new_claim[h_readme_mortality_bg_natural_reaches_threshold]`: FINDING 6: the natural-cause M4 hidden-site p is 0.051 (no star in the table two paragraphs above); only the all-cause ratio (p = 0.0499) reaches 
- `test_new_claim[h_readme_r_vs_python_address_keys]`: FINDING 8: the committed key file has 37,468 keys and data/results/r_vs_python.md (9,848 sites, 4,312 hazardous) does not state a key count; the comparison pred
- `test_new_claim[h_app_dc_ratio_before_the_map]`: FINDING 1: the data (and README, manuscript, SI) give 8.3 for 1921-37; the app text still says 5.3
- `test_new_claim[h_app_enlistment_schooling_hazardous_trade]`: FINDING 2: enlistment_models.csv gives -0.340 (-0.501 to -0.180) after the 3 November rerun
- `test_about_90pct_claim_measures_entries_not_firm_locations`: FINDING 9: readme_pre1960_town_share checks firm-locations (87.8% at town level) for a sentence about entries (90.0%) and passes only through tol: 5
- `test_si_and_manuscript_name_the_same_source_for_the_business_directory_scans`: FINDING 10: the SI (a paragraph reused from the 18 October base) says the Denver Public Library scanned the 34 business-directory edi
- `test_every_app_card_with_a_plot_or_table_states_its_spatial_unit`: FINDING 7: two table cards carry no unit_note (the nearby-schools table `t_recv`, app.R:723, and 'How reliable are the locations?', app.R:896)
- `test_address_only_name_check_is_rerun_with_the_results`: FINDING 5: README says address_only_name_check.py follows rerun_results.sh, but no orchestrator runs it; its csv feeds two claims
- `test_rerun_results_runs_every_writer_before_its_reader`: FINDING 3: rerun_results.sh runs context_layers before site_fate (whose parcel uses it reads), known_hidden_sensitivity before holc_covenants and loc_sanbo
- `test_context_tables_were_built_from_the_committed_site_fate`: FINDING 3 (observed effect): data/results/context/petroleum_by_use_now.csv lists all 255 pre-1960 Denver trades as 'not matched to a parcel' and 556/2
- `test_r_vs_python_report_describes_the_committed_inventory`: FINDING 8: data/results/r_vs_python.md is from an older inventory (4,312 hazardous-sector sites; the all-editions run now has 4,669)
