# Industrial corridors: formation, clustering, succession, legacy

Located establishments 1961-2002: 12,686 statewide, 7,403 in the Denver metro (25 km of downtown); 500 m cells with any manufacturer: 3217 (1455 metro).

## Persistence classes of 500 m cells (metro)

| class | cells | ever hazardous | with a pre-1960 street-level firm |
|---|---|---|---|
| emerging | 632 | 208 | 8 |
| intermittent | 289 | 196 | 15 |
| former (gone by 1980s) | 244 | 107 | 11 |
| persistent, sector turnover | 234 | 217 | 73 |
| persistent | 56 | 41 | 16 |

## Clustering (Ellison-Glaeser gamma vs. all manufacturing, 1 km cells; median over editions, share of editions with p < 0.05)

| sector | statewide gamma | sig. share | metro gamma | sig. share |
|---|---|---|---|---|
| Apparel | 0.001 | 0.42 | 0.002 | 0.33 |
| Chemicals | 0 | 0.08 | 0 | 0.08 |
| Electronics | 0.002 | 0.23 | 0 | 0 |
| Fabricated metals | 0 | 0.46 | 0 | 0.38 |
| Food | 0.001 | 0.62 | 0.002 | 0.46 |
| Furniture | 0.001 | 0.23 | 0.001 | 0.08 |
| Instruments | 0 | 0.23 | -0.002 | 0 |
| Leather | 0.003 | 0.12 | 0.006 | 0 |
| Lumber & wood | 0.001 | 0.23 | 0 | 0.15 |
| Machinery | 0.001 | 0.54 | 0 | 0.46 |
| Misc. manufacturing | 0 | 0.15 | 0.001 | 0.25 |
| Paper | 0.002 | 0.17 | 0.001 | 0.08 |
| Petroleum | 0.011 | 0.6 | 0.011 | 0.5 |
| Primary metals | 0.001 | 0.08 | 0.001 | 0 |
| Printing | 0.002 | 1 | 0.004 | 1 |
| Rubber & plastics | 0.001 | 0.42 | 0 | 0.17 |
| Stone, clay & glass | 0.001 | 0.38 | 0.003 | 0.15 |
| Textiles | -0.003 | 0.2 | 0.036 | 1 |
| Transportation eq. | 0.001 | 0.15 | 0.004 | 0.09 |

## Most common sector successions (dominant sector of a cell, one edition to the next, excluding no change)

* Food -> Printing: 116 cell-transitions (11% of transitions from Food)
* Printing -> Food: 87 cell-transitions (5% of transitions from Printing)
* Printing -> Apparel: 61 cell-transitions (3% of transitions from Printing)
* Fabricated metals -> Printing: 60 cell-transitions (8% of transitions from Fabricated metals)
* Machinery -> Fabricated metals: 57 cell-transitions (9% of transitions from Machinery)
* Machinery -> Printing: 52 cell-transitions (8% of transitions from Machinery)
* Printing -> Fabricated metals: 49 cell-transitions (3% of transitions from Printing)
* Misc. manufacturing -> Printing: 47 cell-transitions (13% of transitions from Misc. manufacturing)
* Furniture -> Printing: 47 cell-transitions (13% of transitions from Furniture)
* Fabricated metals -> Machinery: 43 cell-transitions (5% of transitions from Fabricated metals)
* Apparel -> Printing: 43 cell-transitions (12% of transitions from Apparel)
* Food -> Fabricated metals: 43 cell-transitions (4% of transitions from Food)

## Do old industrial areas attract new industry? (metro, 500 m cells)

* Poisson, pooled (cell-years): log1p(stock_lag) = 0.991 (SE 0.020)
* Poisson, pooled (cell-years): log1p(nb_lag) = 0.297 (SE 0.016)
* Poisson, pooled (cell-years): dist_km = -0.001 (SE 0.003)
* within-cell (demeaned OLS): s_dm = 0.122 (SE 0.016)
* within-cell (demeaned OLS): n_dm = 0.086 (SE 0.012)

## Present-day legacy (tracts, spatial error models, + log density)

| outcome | predictor | b | SE | p |
|---|---|---|---|---|
| people_of_color | log1p(firm_years) | 0.893 | 0.258 | 0.000551 |
| people_of_color | log1p(haz_firm_years) | 1.241 | 0.334 | 0.000198 |
| people_of_color | log1p(hidden_sites) | 0.981 | 0.637 | 0.124 |
| low_income | log1p(firm_years) | 1.932 | 0.254 | 2.66e-14 |
| low_income | log1p(haz_firm_years) | 1.799 | 0.331 | 5.27e-08 |
| low_income | log1p(hidden_sites) | 2.392 | 0.642 | 0.000195 |
| enviroscreen_pctl | log1p(firm_years) | 3.215 | 0.346 | 0 |
| enviroscreen_pctl | log1p(haz_firm_years) | 2.880 | 0.454 | 2.24e-10 |
| enviroscreen_pctl | log1p(hidden_sites) | 3.615 | 0.868 | 3.15e-05 |
| pollution_climate_pctl | log1p(firm_years) | 1.295 | 0.197 | 4.96e-11 |
| pollution_climate_pctl | log1p(haz_firm_years) | 1.003 | 0.257 | 9.73e-05 |
| pollution_climate_pctl | log1p(hidden_sites) | 1.637 | 0.485 | 0.000739 |
