# Industrial corridors: formation, clustering, succession, legacy

Located establishments in the 13 complete editions 1965-1992: 13,254 statewide, 7,788 in the Denver metro (25 km of downtown); 500 m cells with any manufacturer: 3332 (1507 metro).

## Persistence classes of 500 m cells (metro)

| class | cells | ever hazardous | with a pre-1960 street-level firm |
|---|---|---|---|
| emerging | 591 | 224 | 2 |
| intermittent | 304 | 210 | 9 |
| former (gone by 1980s) | 279 | 129 | 5 |
| persistent, sector turnover | 242 | 228 | 48 |
| persistent | 91 | 73 | 20 |

## Clustering (Ellison-Glaeser gamma vs. all manufacturing, 1 km cells; median over editions, share of editions with p < 0.05)

| sector | statewide gamma | sig. share | metro gamma | sig. share |
|---|---|---|---|---|
| Apparel | 0.001 | 0.46 | 0.002 | 0.42 |
| Chemicals | 0 | 0.15 | 0 | 0 |
| Electronics | 0.001 | 0.38 | 0 | 0 |
| Fabricated metals | 0 | 0.85 | 0.001 | 0.62 |
| Food | 0.001 | 0.85 | 0.002 | 0.69 |
| Furniture | 0.001 | 0.31 | 0.002 | 0.15 |
| Instruments | 0.001 | 0.38 | 0 | 0.08 |
| Leather | -0.002 | 0.08 | 0.002 | 0 |
| Lumber & wood | 0.001 | 0.31 | 0.001 | 0.23 |
| Machinery | 0.001 | 0.77 | 0.001 | 0.69 |
| Misc. manufacturing | 0.001 | 0.15 | 0.003 | 0.23 |
| Paper | 0.001 | 0.33 | 0 | 0.25 |
| Petroleum | 0.009 | 0.5 | 0.012 | 0.29 |
| Primary metals | 0.001 | 0.17 | 0.001 | 0 |
| Printing | 0.002 | 1 | 0.005 | 1 |
| Rubber & plastics | 0.001 | 0.54 | 0.001 | 0.23 |
| Stone, clay & glass | 0.001 | 0.46 | 0.002 | 0.08 |
| Textiles | -0.005 | 0.12 | 0.001 | 0.5 |
| Transportation eq. | 0.001 | 0.15 | 0.002 | 0.25 |

## Most common sector successions (dominant sector of a cell, one edition to the next, excluding no change)

* Food -> Printing: 140 cell-transitions (9% of transitions from Food)
* Printing -> Food: 99 cell-transitions (5% of transitions from Printing)
* Machinery -> Fabricated metals: 70 cell-transitions (9% of transitions from Machinery)
* Fabricated metals -> Printing: 67 cell-transitions (6% of transitions from Fabricated metals)
* Fabricated metals -> Machinery: 63 cell-transitions (6% of transitions from Fabricated metals)
* Machinery -> Printing: 62 cell-transitions (8% of transitions from Machinery)
* Printing -> Apparel: 60 cell-transitions (3% of transitions from Printing)
* Printing -> Fabricated metals: 53 cell-transitions (2% of transitions from Printing)
* Misc. manufacturing -> Printing: 49 cell-transitions (11% of transitions from Misc. manufacturing)
* Printing -> Machinery: 49 cell-transitions (2% of transitions from Printing)
* Apparel -> Printing: 46 cell-transitions (11% of transitions from Apparel)
* Printing -> Misc. manufacturing: 46 cell-transitions (2% of transitions from Printing)

## Do old industrial areas attract new industry? (metro, 500 m cells)

* Poisson, pooled (cell-years): log1p(stock_lag) = 0.952 (SE 0.019)
* Poisson, pooled (cell-years): log1p(nb_lag) = 0.293 (SE 0.016)
* Poisson, pooled (cell-years): dist_km = 0.004 (SE 0.003)
* within-cell (demeaned OLS): s_dm = 0.121 (SE 0.016)
* within-cell (demeaned OLS): n_dm = 0.109 (SE 0.013)

## Present-day legacy (tracts, spatial error models, + log density)

| outcome | predictor | b | SE | p |
|---|---|---|---|---|
| people_of_color | log1p(firm_years) | 0.791 | 0.250 | 0.00157 |
| people_of_color | log1p(haz_firm_years) | 1.129 | 0.306 | 0.000223 |
| people_of_color | log1p(hidden_sites) | 1.182 | 0.564 | 0.036 |
| low_income | log1p(firm_years) | 1.813 | 0.246 | 1.61e-13 |
| low_income | log1p(haz_firm_years) | 1.778 | 0.303 | 4.28e-09 |
| low_income | log1p(hidden_sites) | 2.451 | 0.566 | 1.52e-05 |
| enviroscreen_pctl | log1p(firm_years) | 3.178 | 0.334 | 0 |
| enviroscreen_pctl | log1p(haz_firm_years) | 2.845 | 0.414 | 6.62e-12 |
| enviroscreen_pctl | log1p(hidden_sites) | 3.167 | 0.768 | 3.7e-05 |
| pollution_climate_pctl | log1p(firm_years) | 1.226 | 0.191 | 1.23e-10 |
| pollution_climate_pctl | log1p(haz_firm_years) | 1.011 | 0.235 | 1.66e-05 |
| pollution_climate_pctl | log1p(hidden_sites) | 1.590 | 0.428 | 0.000206 |
