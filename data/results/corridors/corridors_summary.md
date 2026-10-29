# Industrial corridors: formation, clustering, succession, legacy

Located establishments in the 13 complete editions 1965-1992: 12,655 statewide, 7,372 in the Denver metro (25 km of downtown); 500 m cells with any manufacturer: 3215 (1453 metro).

## Persistence classes of 500 m cells (metro)

| class | cells | ever hazardous | with a pre-1960 street-level firm |
|---|---|---|---|
| emerging | 633 | 241 | 8 |
| intermittent | 288 | 200 | 15 |
| former (gone by 1980s) | 242 | 113 | 11 |
| persistent, sector turnover | 231 | 218 | 73 |
| persistent | 59 | 48 | 16 |

## Clustering (Ellison-Glaeser gamma vs. all manufacturing, 1 km cells; median over editions, share of editions with p < 0.05)

| sector | statewide gamma | sig. share | metro gamma | sig. share |
|---|---|---|---|---|
| Apparel | 0.001 | 0.42 | 0.002 | 0.33 |
| Chemicals | 0 | 0.08 | 0 | 0.08 |
| Electronics | 0.001 | 0.23 | 0 | 0 |
| Fabricated metals | 0 | 0.54 | 0 | 0.38 |
| Food | 0.001 | 0.62 | 0.003 | 0.46 |
| Furniture | 0.001 | 0.23 | 0.001 | 0.15 |
| Instruments | 0 | 0.23 | -0.001 | 0.08 |
| Leather | 0.003 | 0.12 | 0.006 | 0 |
| Lumber & wood | 0.001 | 0.31 | 0.001 | 0.15 |
| Machinery | 0.001 | 0.54 | 0 | 0.46 |
| Misc. manufacturing | 0 | 0.15 | 0.001 | 0.17 |
| Paper | 0.002 | 0.17 | 0.001 | 0 |
| Petroleum | 0.011 | 0.6 | 0.011 | 0.5 |
| Primary metals | 0.001 | 0.08 | 0.001 | 0 |
| Printing | 0.002 | 1 | 0.004 | 1 |
| Rubber & plastics | 0.001 | 0.42 | 0 | 0.17 |
| Stone, clay & glass | 0.001 | 0.38 | 0.003 | 0.08 |
| Textiles | -0.003 | 0.2 | 0.033 | 1 |
| Transportation eq. | 0.001 | 0.23 | 0.004 | 0.09 |

## Most common sector successions (dominant sector of a cell, one edition to the next, excluding no change)

* Food -> Printing: 116 cell-transitions (11% of transitions from Food)
* Printing -> Food: 87 cell-transitions (5% of transitions from Printing)
* Printing -> Apparel: 61 cell-transitions (3% of transitions from Printing)
* Fabricated metals -> Printing: 60 cell-transitions (8% of transitions from Fabricated metals)
* Machinery -> Fabricated metals: 57 cell-transitions (9% of transitions from Machinery)
* Machinery -> Printing: 51 cell-transitions (8% of transitions from Machinery)
* Printing -> Fabricated metals: 49 cell-transitions (3% of transitions from Printing)
* Misc. manufacturing -> Printing: 47 cell-transitions (13% of transitions from Misc. manufacturing)
* Furniture -> Printing: 47 cell-transitions (13% of transitions from Furniture)
* Fabricated metals -> Machinery: 43 cell-transitions (5% of transitions from Fabricated metals)
* Apparel -> Printing: 43 cell-transitions (12% of transitions from Apparel)
* Food -> Fabricated metals: 43 cell-transitions (4% of transitions from Food)

## Do old industrial areas attract new industry? (metro, 500 m cells)

* Poisson, pooled (cell-years): log1p(stock_lag) = 0.989 (SE 0.020)
* Poisson, pooled (cell-years): log1p(nb_lag) = 0.298 (SE 0.016)
* Poisson, pooled (cell-years): dist_km = -0.001 (SE 0.003)
* within-cell (demeaned OLS): s_dm = 0.121 (SE 0.016)
* within-cell (demeaned OLS): n_dm = 0.084 (SE 0.012)

## Present-day legacy (tracts, spatial error models, + log density)

| outcome | predictor | b | SE | p |
|---|---|---|---|---|
| people_of_color | log1p(firm_years) | 0.900 | 0.259 | 0.000508 |
| people_of_color | log1p(haz_firm_years) | 1.237 | 0.326 | 0.000151 |
| people_of_color | log1p(hidden_sites) | 1.011 | 0.638 | 0.113 |
| low_income | log1p(firm_years) | 1.937 | 0.254 | 2.4e-14 |
| low_income | log1p(haz_firm_years) | 1.813 | 0.323 | 2e-08 |
| low_income | log1p(hidden_sites) | 2.395 | 0.642 | 0.000193 |
| enviroscreen_pctl | log1p(firm_years) | 3.222 | 0.346 | 0 |
| enviroscreen_pctl | log1p(haz_firm_years) | 3.048 | 0.442 | 5.52e-12 |
| enviroscreen_pctl | log1p(hidden_sites) | 3.610 | 0.867 | 3.16e-05 |
| pollution_climate_pctl | log1p(firm_years) | 1.296 | 0.197 | 4.74e-11 |
| pollution_climate_pctl | log1p(haz_firm_years) | 1.067 | 0.251 | 2.12e-05 |
| pollution_climate_pctl | log1p(hidden_sites) | 1.623 | 0.485 | 0.000808 |
