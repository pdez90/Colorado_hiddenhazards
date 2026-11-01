# Benchmarks: the Colorado directories against the public national manufacturing series

## 1975-2002: County Business Patterns (establishments) vs the Directory of Colorado Manufacturers

| year | CBP manufacturing estab. | directory manufacturers | ratio | CBP hazardous-sector estab. | directory hazardous | ratio |
|---|---|---|---|---|---|---|
| 1976 | 3,071 | 1,862 | 0.61 | 1,026 |   803 | 0.78 |
| 1977 | 3,438 | 3,358 | 0.98 | 1,146 | 1,279 | 1.12 |
| 1979 | 3,414 | 2,106 | 0.62 | 1,148 |   826 | 0.72 |
| 1980 | 3,453 | 3,813 | 1.10 | 1,175 | 1,407 | 1.20 |
| 1982 | 3,797 | 2,306 | 0.61 | 1,319 |   949 | 0.72 |
| 1983 | 4,159 | 4,276 | 1.03 | 1,417 | 1,622 | 1.14 |
| 1984 | 4,339 | 2,179 | 0.50 | 1,429 |   868 | 0.61 |
| 1985 | 4,388 | 1,729 | 0.39 | 1,411 |   655 | 0.46 |
| 1986 | 4,390 | 3,092 | 0.70 | 1,386 | 1,231 | 0.89 |
| 1988 | 4,551 | 3,567 | 0.78 | 1,436 | 1,412 | 0.98 |
| 1990 | 4,878 | 4,100 | 0.84 | 1,536 | 1,535 | 1.00 |
| 1992 | 5,226 | 2,970 | 0.57 | 1,630 | 1,124 | 0.69 |
| 1993 | 5,385 | 1,887 | 0.35 | 1,694 |   779 | 0.46 |
| 1999 | 5,425 | 2,279 | 0.42 | 1,749 |   911 | 0.52 |
| 2002 | 5,250 | 2,134 | 0.41 | 1,698 |   785 | 0.46 |

County-level agreement across 15 editions and 63 counties: r = 0.84 (log manufacturers), 0.88 (log hazardous sectors); median directory/CBP ratio 0.81 (Denver 0.94).

CBP counts every employer establishment with a payroll (from administrative records); the directory lists firms that answered the publisher's questionnaire or were
copied from other lists, so it undercounts the smallest establishments and the ratio is a coverage rate. CBP has no addresses: it cannot replace the directory for siting.
Raw county files from Eckert, Fort, Schott & Yang (2021), NBER WP 26632 (github.com/fpeckert/website, release cbp-data); 1975-85 from the National Archives, 1986+ from the Census Bureau.

## 1880-1940: census manufacturing establishments by county (NHGIS) vs the business directory's hazardous trades

| census | counties | census manufacturing establishments | directory hazardous trades (+/- 2 years) |
|---|---|---|---|
| 1880 | 31 |   599 | 463 |
| 1890 | 56 | 1,518 | 282 |
| 1920 | 60 | 2,626 | 323 |
| 1930 | 35 | 1,452 | 236 |
| 1940 | 59 | 1,298 | 391 |

Censuses with no directory edition within two years are left out (1900: none between 1892 and 1910). The business directory only lists the hazardous trades, so the ratio is a floor on its coverage of all manufacturing; the census counts every establishment above a small output threshold.

## 1870 and 1880: Atack-Bateman-Weiss Census of Manufactures samples

290 Colorado establishments in the state samples (1870: 0, 1880: 290); see atack_colorado.csv.
These are samples of surviving manuscript schedules (not a complete census) and give the county and industry of each establishment, its capital, workers and output, but no street address.
The Census Longitudinal Business Database (1976+) tracks individual establishments nationally but is restricted-access; it is the only national source at the establishment level for the directory era.
