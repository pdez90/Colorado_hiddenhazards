# Industrial corridors: formation, clustering, succession, legacy

Located establishments 1961-2002: 18,998 statewide, 10,966 in the Denver metro (25 km of downtown); 500 m cells with any manufacturer: 4078 (1765 metro).

## Persistence classes of 500 m cells (metro)

| class | cells | ever hazardous | with a pre-1960 street-level firm |
|---|---|---|---|
| emerging | 822 | 304 | 5 |
| intermittent | 496 | 348 | 28 |
| persistent, sector turnover | 225 | 216 | 74 |
| former (gone by 1980s) | 191 | 75 | 6 |
| persistent | 31 | 26 | 14 |

## Clustering (Ellison-Glaeser gamma vs. all manufacturing, 1 km cells; median over editions, share of editions with p < 0.05)

| sector | statewide gamma | sig. share | metro gamma | sig. share |
|---|---|---|---|---|
| Apparel | 0.001 | 0.3 | 0.002 | 0.24 |
| Chemicals | 0.001 | 0.12 | 0 | 0.09 |
| Electronics | 0.001 | 0.32 | 0.001 | 0.09 |
| Fabricated metals | 0 | 0.48 | 0 | 0.28 |
| Food | 0.001 | 0.58 | 0.002 | 0.43 |
| Furniture | 0.001 | 0.21 | 0.001 | 0.17 |
| Instruments | 0.001 | 0.29 | 0 | 0 |
| Leather | 0.005 | 0.15 | 0.006 | 0 |
| Lumber & wood | 0.001 | 0.17 | 0 | 0.08 |
| Machinery | 0.001 | 0.6 | 0.001 | 0.52 |
| Misc. manufacturing | 0 | 0.17 | 0 | 0.14 |
| Paper | 0.001 | 0.1 | 0 | 0.06 |
| Petroleum | 0.011 | 0.62 | 0.018 | 0.57 |
| Primary metals | 0.002 | 0.08 | 0.001 | 0 |
| Printing | 0.002 | 0.92 | 0.004 | 0.92 |
| Rubber & plastics | 0.001 | 0.3 | 0 | 0.14 |
| Stone, clay & glass | 0.001 | 0.33 | 0 | 0.09 |
| Textiles | -0.003 | 0.14 | 0.032 | 1 |
| Transportation eq. | 0.001 | 0.12 | 0.003 | 0.05 |

## Most common sector successions (dominant sector of a cell, one edition to the next, excluding no change)

* Food -> Printing: 179 cell-transitions (10% of transitions from Food)
* Printing -> Food: 130 cell-transitions (4% of transitions from Printing)
* Machinery -> Fabricated metals: 103 cell-transitions (9% of transitions from Machinery)
* Fabricated metals -> Printing: 86 cell-transitions (6% of transitions from Fabricated metals)
* Printing -> Fabricated metals: 86 cell-transitions (3% of transitions from Printing)
* Fabricated metals -> Machinery: 82 cell-transitions (6% of transitions from Fabricated metals)
* Printing -> Apparel: 81 cell-transitions (2% of transitions from Printing)
* Machinery -> Printing: 80 cell-transitions (7% of transitions from Machinery)
* Printing -> Machinery: 78 cell-transitions (2% of transitions from Printing)
* Misc. manufacturing -> Printing: 76 cell-transitions (12% of transitions from Misc. manufacturing)
* Food -> Fabricated metals: 72 cell-transitions (4% of transitions from Food)
* Fabricated metals -> Food: 59 cell-transitions (4% of transitions from Fabricated metals)

## Do old industrial areas attract new industry? (metro, 500 m cells)

* Poisson, pooled (cell-years): log1p(stock_lag) = 0.957 (SE 0.017)
* Poisson, pooled (cell-years): log1p(nb_lag) = 0.261 (SE 0.013)
* Poisson, pooled (cell-years): dist_km = -0.033 (SE 0.002)
* within-cell (demeaned OLS): s_dm = 0.069 (SE 0.010)
* within-cell (demeaned OLS): n_dm = 0.010 (SE 0.007)

## Present-day legacy (tracts, spatial error models, + log density)

| outcome | predictor | b | SE | p |
|---|---|---|---|---|
| people_of_color | log1p(firm_years) | 0.711 | 0.242 | 0.00325 |
| people_of_color | log1p(haz_firm_years) | 0.943 | 0.295 | 0.00137 |
| people_of_color | log1p(hidden_sites) | 0.608 | 0.550 | 0.269 |
| low_income | log1p(firm_years) | 1.687 | 0.237 | 1.18e-12 |
| low_income | log1p(haz_firm_years) | 1.453 | 0.292 | 6.71e-07 |
| low_income | log1p(hidden_sites) | 2.160 | 0.554 | 9.79e-05 |
| enviroscreen_pctl | log1p(firm_years) | 2.859 | 0.324 | 0 |
| enviroscreen_pctl | log1p(haz_firm_years) | 2.483 | 0.401 | 5.85e-10 |
| enviroscreen_pctl | log1p(hidden_sites) | 3.267 | 0.749 | 1.3e-05 |
| pollution_climate_pctl | log1p(firm_years) | 1.309 | 0.184 | 1.05e-12 |
| pollution_climate_pctl | log1p(haz_firm_years) | 1.034 | 0.227 | 5.04e-06 |
| pollution_climate_pctl | log1p(hidden_sites) | 1.550 | 0.418 | 0.00021 |
