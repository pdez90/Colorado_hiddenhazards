# Industrial corridors: formation, clustering, succession, legacy

Located establishments in the 13 complete editions 1965-1992: 13,235 statewide, 7,786 in the Denver metro (25 km of downtown); 500 m cells with any manufacturer: 3333 (1509 metro).

## Persistence classes of 500 m cells (metro)

| class | cells | ever hazardous | with a pre-1960 street-level firm |
|---|---|---|---|
| emerging | 592 | 224 | 6 |
| intermittent | 305 | 211 | 16 |
| former (gone by 1980s) | 280 | 129 | 11 |
| persistent, sector turnover | 241 | 227 | 66 |
| persistent | 91 | 73 | 25 |

## Clustering (Ellison-Glaeser gamma vs. all manufacturing, 1 km cells; median over editions, share of editions with p < 0.05)

| sector | statewide gamma | sig. share | metro gamma | sig. share |
|---|---|---|---|---|
| Apparel | 0.001 | 0.46 | 0.002 | 0.42 |
| Chemicals | 0 | 0.15 | 0 | 0 |
| Electronics | 0.001 | 0.38 | 0 | 0 |
| Fabricated metals | 0 | 0.77 | 0.001 | 0.62 |
| Food | 0.001 | 0.85 | 0.002 | 0.69 |
| Furniture | 0.001 | 0.31 | 0.002 | 0.15 |
| Instruments | 0 | 0.31 | 0 | 0.08 |
| Leather | -0.002 | 0.08 | 0.002 | 0 |
| Lumber & wood | 0.001 | 0.23 | 0.001 | 0.15 |
| Machinery | 0.001 | 0.77 | 0.001 | 0.69 |
| Misc. manufacturing | 0.001 | 0.31 | 0.003 | 0.31 |
| Paper | 0.001 | 0.33 | 0 | 0.17 |
| Petroleum | 0.009 | 0.3 | 0.012 | 0.29 |
| Primary metals | 0.001 | 0.08 | 0.001 | 0 |
| Printing | 0.002 | 1 | 0.005 | 1 |
| Rubber & plastics | 0.001 | 0.54 | 0.001 | 0.23 |
| Stone, clay & glass | 0.001 | 0.46 | 0.002 | 0.08 |
| Textiles | -0.005 | 0.14 | 0.001 | 0.5 |
| Transportation eq. | 0.001 | 0.15 | 0.002 | 0.25 |

## Most common sector successions (dominant sector of a cell, one edition to the next, excluding no change)

* Food -> Printing: 141 cell-transitions (9% of transitions from Food)
* Printing -> Food: 98 cell-transitions (4% of transitions from Printing)
* Machinery -> Fabricated metals: 69 cell-transitions (9% of transitions from Machinery)
* Fabricated metals -> Printing: 67 cell-transitions (6% of transitions from Fabricated metals)
* Fabricated metals -> Machinery: 63 cell-transitions (6% of transitions from Fabricated metals)
* Machinery -> Printing: 62 cell-transitions (8% of transitions from Machinery)
* Printing -> Apparel: 60 cell-transitions (3% of transitions from Printing)
* Printing -> Fabricated metals: 53 cell-transitions (2% of transitions from Printing)
* Printing -> Machinery: 49 cell-transitions (2% of transitions from Printing)
* Misc. manufacturing -> Printing: 47 cell-transitions (11% of transitions from Misc. manufacturing)
* Apparel -> Printing: 46 cell-transitions (11% of transitions from Apparel)
* Furniture -> Printing: 45 cell-transitions (10% of transitions from Furniture)

## Do old industrial areas attract new industry? (metro, 500 m cells)

* Poisson, pooled (cell-years): log1p(stock_lag) = 0.952 (SE 0.019)
* Poisson, pooled (cell-years): log1p(nb_lag) = 0.294 (SE 0.016)
* Poisson, pooled (cell-years): dist_km = 0.004 (SE 0.003)
* within-cell (demeaned OLS): s_dm = 0.121 (SE 0.016)
* within-cell (demeaned OLS): n_dm = 0.109 (SE 0.013)

## Present-day legacy (tracts, spatial error models, + log density)

| outcome | predictor | b | SE | p |
|---|---|---|---|---|
| people_of_color | log1p(firm_years) | 0.802 | 0.251 | 0.00139 |
| people_of_color | log1p(haz_firm_years) | 1.121 | 0.306 | 0.00025 |
| people_of_color | log1p(hidden_sites) | 1.044 | 0.559 | 0.0621 |
| low_income | log1p(firm_years) | 1.799 | 0.246 | 2.71e-13 |
| low_income | log1p(haz_firm_years) | 1.764 | 0.303 | 5.85e-09 |
| low_income | log1p(hidden_sites) | 2.242 | 0.562 | 6.71e-05 |
| enviroscreen_pctl | log1p(firm_years) | 3.170 | 0.335 | 0 |
| enviroscreen_pctl | log1p(haz_firm_years) | 2.820 | 0.415 | 1.06e-11 |
| enviroscreen_pctl | log1p(hidden_sites) | 2.997 | 0.762 | 8.4e-05 |
| pollution_climate_pctl | log1p(firm_years) | 1.245 | 0.191 | 6.66e-11 |
| pollution_climate_pctl | log1p(haz_firm_years) | 1.006 | 0.235 | 1.88e-05 |
| pollution_climate_pctl | log1p(hidden_sites) | 1.566 | 0.425 | 0.00023 |
