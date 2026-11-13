# Industrial corridors: formation, clustering, succession, legacy

Located establishments in the 13 complete editions 1965-1992: 13,592 statewide, 7,988 in the Denver metro (25 km of downtown); 500 m cells with any manufacturer: 3391 (1539 metro).

## Persistence classes of 500 m cells (metro)

| class | cells | ever hazardous | with a pre-1960 street-level firm |
|---|---|---|---|
| emerging | 593 | 228 | 3 |
| intermittent | 313 | 218 | 13 |
| former (gone by 1980s) | 301 | 139 | 6 |
| persistent, sector turnover | 236 | 226 | 54 |
| persistent | 96 | 76 | 22 |

## Clustering (Ellison-Glaeser gamma vs. all manufacturing, 1 km cells; median over editions, share of editions with p < 0.05)

| sector | statewide gamma | sig. share | metro gamma | sig. share |
|---|---|---|---|---|
| Apparel | 0.001 | 0.54 | 0.001 | 0.46 |
| Chemicals | 0.001 | 0.15 | 0.001 | 0 |
| Electronics | 0.002 | 0.38 | 0.001 | 0.08 |
| Fabricated metals | 0 | 0.69 | 0.001 | 0.54 |
| Food | 0.001 | 0.92 | 0.003 | 0.85 |
| Furniture | 0.001 | 0.38 | 0.002 | 0.31 |
| Instruments | 0.001 | 0.31 | 0 | 0.08 |
| Leather | -0.001 | 0.17 | 0.002 | 0 |
| Lumber & wood | 0 | 0.31 | 0.001 | 0.15 |
| Machinery | 0.001 | 0.69 | 0.001 | 0.62 |
| Misc. manufacturing | 0 | 0.31 | 0.002 | 0.33 |
| Paper | 0.002 | 0.33 | 0.002 | 0.08 |
| Petroleum | 0.011 | 0.6 | 0.019 | 0.62 |
| Primary metals | 0.001 | 0.08 | 0.001 | 0 |
| Printing | 0.002 | 1 | 0.005 | 1 |
| Rubber & plastics | 0.001 | 0.38 | 0.002 | 0.08 |
| Stone, clay & glass | 0.001 | 0.54 | 0.001 | 0.15 |
| Textiles | -0.005 | 0.11 | 0.007 | 0.5 |
| Transportation eq. | 0.001 | 0.15 | 0.002 | 0.25 |

## Most common sector successions (dominant sector of a cell, one edition to the next, excluding no change)

* Food -> Printing: 147 cell-transitions (8% of transitions from Food)
* Printing -> Food: 95 cell-transitions (4% of transitions from Printing)
* Machinery -> Fabricated metals: 74 cell-transitions (9% of transitions from Machinery)
* Fabricated metals -> Printing: 74 cell-transitions (7% of transitions from Fabricated metals)
* Fabricated metals -> Machinery: 66 cell-transitions (6% of transitions from Fabricated metals)
* Machinery -> Printing: 64 cell-transitions (8% of transitions from Machinery)
* Printing -> Apparel: 62 cell-transitions (3% of transitions from Printing)
* Printing -> Fabricated metals: 56 cell-transitions (2% of transitions from Printing)
* Printing -> Machinery: 49 cell-transitions (2% of transitions from Printing)
* Apparel -> Printing: 48 cell-transitions (11% of transitions from Apparel)
* Furniture -> Printing: 48 cell-transitions (10% of transitions from Furniture)
* Misc. manufacturing -> Printing: 47 cell-transitions (10% of transitions from Misc. manufacturing)

## Do old industrial areas attract new industry? (metro, 500 m cells)

* Poisson, pooled (cell-years): log1p(stock_lag) = 0.957 (SE 0.019)
* Poisson, pooled (cell-years): log1p(nb_lag) = 0.273 (SE 0.016)
* Poisson, pooled (cell-years): dist_km = 0.005 (SE 0.003)
* within-cell (demeaned OLS): s_dm = 0.160 (SE 0.015)
* within-cell (demeaned OLS): n_dm = 0.114 (SE 0.012)

## Present-day legacy (tracts, spatial error models, + log density)

| outcome | predictor | b | SE | p |
|---|---|---|---|---|
| people_of_color | log1p(firm_years) | 0.742 | 0.241 | 0.00206 |
| people_of_color | log1p(haz_firm_years) | 1.226 | 0.293 | 2.84e-05 |
| people_of_color | log1p(hidden_sites) | 1.393 | 0.539 | 0.00984 |
| low_income | log1p(firm_years) | 1.781 | 0.241 | 1.39e-13 |
| low_income | log1p(haz_firm_years) | 1.817 | 0.295 | 7.7e-10 |
| low_income | log1p(hidden_sites) | 2.518 | 0.551 | 4.87e-06 |
| enviroscreen_pctl | log1p(firm_years) | 3.073 | 0.315 | 0 |
| enviroscreen_pctl | log1p(haz_firm_years) | 3.075 | 0.389 | 2.66e-15 |
| enviroscreen_pctl | log1p(hidden_sites) | 3.655 | 0.722 | 4.17e-07 |
| pollution_climate_pctl | log1p(firm_years) | 1.128 | 0.184 | 9.14e-10 |
| pollution_climate_pctl | log1p(haz_firm_years) | 1.017 | 0.226 | 6.88e-06 |
| pollution_climate_pctl | log1p(hidden_sites) | 1.643 | 0.411 | 6.45e-05 |
