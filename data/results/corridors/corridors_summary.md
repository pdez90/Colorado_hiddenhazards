# Industrial corridors: formation, clustering, succession, legacy

Located establishments in the 13 complete editions 1965-1992: 13,090 statewide, 7,680 in the Denver metro (25 km of downtown); 500 m cells with any manufacturer: 3325 (1494 metro).

## Persistence classes of 500 m cells (metro)

| class | cells | ever hazardous | with a pre-1960 street-level firm |
|---|---|---|---|
| emerging | 570 | 184 | 3 |
| intermittent | 305 | 198 | 13 |
| former (gone by 1980s) | 286 | 99 | 6 |
| persistent, sector turnover | 234 | 215 | 56 |
| persistent | 99 | 73 | 22 |

## Clustering (Ellison-Glaeser gamma vs. all manufacturing, 1 km cells; median over editions, share of editions with p < 0.05)

| sector | statewide gamma | sig. share | metro gamma | sig. share |
|---|---|---|---|---|
| Apparel | 0.001 | 0.54 | 0.001 | 0.46 |
| Chemicals | 0.001 | 0.23 | 0.002 | 0.23 |
| Electronics | 0.002 | 0.38 | 0.001 | 0 |
| Fabricated metals | 0 | 0.85 | 0.001 | 0.69 |
| Food | 0.001 | 0.92 | 0.002 | 0.85 |
| Furniture | 0.001 | 0.38 | 0.002 | 0.31 |
| Instruments | 0.001 | 0.38 | -0.001 | 0 |
| Leather | -0.001 | 0.08 | 0.003 | 0.14 |
| Lumber & wood | 0 | 0.31 | 0.001 | 0.08 |
| Machinery | 0.001 | 0.92 | 0.001 | 0.92 |
| Misc. manufacturing | 0 | 0.23 | 0.002 | 0.23 |
| Paper | 0.002 | 0.17 | 0.001 | 0.08 |
| Petroleum | 0.011 | 0.67 | 0.019 | 0.62 |
| Primary metals | 0.001 | 0.08 | 0 | 0 |
| Printing | 0.002 | 1 | 0.005 | 1 |
| Rubber & plastics | 0.001 | 0.38 | 0.001 | 0.15 |
| Stone, clay & glass | 0.001 | 0.62 | 0.002 | 0.15 |
| Textiles | -0.005 | 0.11 | 0.007 | 0.5 |
| Transportation eq. | 0 | 0.08 | 0.001 | 0.08 |

## Most common sector successions (dominant sector of a cell, one edition to the next, excluding no change)

* Food -> Printing: 146 cell-transitions (8% of transitions from Food)
* Printing -> Food: 97 cell-transitions (4% of transitions from Printing)
* Machinery -> Fabricated metals: 67 cell-transitions (8% of transitions from Machinery)
* Fabricated metals -> Printing: 66 cell-transitions (6% of transitions from Fabricated metals)
* Printing -> Apparel: 60 cell-transitions (3% of transitions from Printing)
* Fabricated metals -> Machinery: 59 cell-transitions (5% of transitions from Fabricated metals)
* Machinery -> Printing: 59 cell-transitions (7% of transitions from Machinery)
* Printing -> Fabricated metals: 55 cell-transitions (2% of transitions from Printing)
* Misc. manufacturing -> Printing: 52 cell-transitions (11% of transitions from Misc. manufacturing)
* Furniture -> Printing: 50 cell-transitions (11% of transitions from Furniture)
* Apparel -> Printing: 48 cell-transitions (11% of transitions from Apparel)
* Printing -> Misc. manufacturing: 46 cell-transitions (2% of transitions from Printing)

## Do old industrial areas attract new industry? (metro, 500 m cells)

* Poisson, pooled (cell-years): log1p(stock_lag) = 0.944 (SE 0.019)
* Poisson, pooled (cell-years): log1p(nb_lag) = 0.271 (SE 0.016)
* Poisson, pooled (cell-years): dist_km = 0.006 (SE 0.003)
* within-cell (demeaned OLS): s_dm = 0.142 (SE 0.015)
* within-cell (demeaned OLS): n_dm = 0.122 (SE 0.012)

## Present-day legacy (tracts, spatial error models, + log density)

| outcome | predictor | b | SE | p |
|---|---|---|---|---|
| people_of_color | log1p(firm_years) | 0.738 | 0.240 | 0.00207 |
| people_of_color | log1p(haz_firm_years) | 1.239 | 0.291 | 2.03e-05 |
| people_of_color | log1p(hidden_sites) | 1.970 | 0.586 | 0.000779 |
| low_income | log1p(firm_years) | 1.773 | 0.240 | 1.41e-13 |
| low_income | log1p(haz_firm_years) | 1.696 | 0.294 | 7.89e-09 |
| low_income | log1p(hidden_sites) | 2.526 | 0.601 | 2.66e-05 |
| enviroscreen_pctl | log1p(firm_years) | 3.058 | 0.314 | 0 |
| enviroscreen_pctl | log1p(haz_firm_years) | 2.963 | 0.387 | 1.8e-14 |
| enviroscreen_pctl | log1p(hidden_sites) | 4.087 | 0.786 | 1.98e-07 |
| pollution_climate_pctl | log1p(firm_years) | 1.132 | 0.183 | 6.52e-10 |
| pollution_climate_pctl | log1p(haz_firm_years) | 0.980 | 0.224 | 1.24e-05 |
| pollution_climate_pctl | log1p(hidden_sites) | 1.815 | 0.447 | 4.93e-05 |
