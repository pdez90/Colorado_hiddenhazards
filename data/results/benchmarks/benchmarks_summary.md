# Benchmarks: the Colorado directories against the public national manufacturing series

## 1975-2002: County Business Patterns (establishments) vs the Directory of Colorado Manufacturers

| year | CBP manufacturing estab. | directory manufacturers | ratio | CBP hazardous-sector estab. | directory hazardous | ratio |
|---|---|---|---|---|---|---|
| 1976 | 3,071 | 1,861 | 0.61 | 1,026 |   799 | 0.78 |
| 1977 | 3,438 | 3,366 | 0.98 | 1,146 | 1,271 | 1.11 |
| 1979 | 3,414 | 2,088 | 0.61 | 1,148 |   824 | 0.72 |
| 1980 | 3,453 | 3,808 | 1.10 | 1,175 | 1,398 | 1.19 |
| 1982 | 3,797 | 2,305 | 0.61 | 1,319 |   948 | 0.72 |
| 1983 | 4,159 | 4,258 | 1.02 | 1,417 | 1,609 | 1.14 |
| 1984 | 4,339 | 2,172 | 0.50 | 1,429 |   860 | 0.60 |
| 1985 | 4,388 | 1,708 | 0.39 | 1,411 |   637 | 0.45 |
| 1986 | 4,390 | 3,089 | 0.70 | 1,386 | 1,228 | 0.89 |
| 1988 | 4,551 | 3,569 | 0.78 | 1,436 | 1,346 | 0.94 |
| 1990 | 4,878 | 4,195 | 0.86 | 1,536 | 1,562 | 1.02 |
| 1992 | 5,226 | 3,311 | 0.63 | 1,630 | 1,220 | 0.75 |
| 1993 | 5,385 | 1,888 | 0.35 | 1,694 |   780 | 0.46 |
| 1999 | 5,425 | 2,280 | 0.42 | 1,749 |   910 | 0.52 |
| 2002 | 5,250 | 2,134 | 0.41 | 1,698 |   785 | 0.46 |

County-level agreement across 15 editions and 63 counties: r = 0.84 (log manufacturers), 0.88 (log hazardous sectors); median directory/CBP ratio 0.80 (Denver 0.96).

CBP counts every employer establishment with a payroll (from administrative records); the directory lists firms that answered the publisher's questionnaire or were
copied from other lists, so it undercounts the smallest establishments and the ratio is a coverage rate. CBP has no addresses: it cannot replace the directory for siting.
Raw county files from Eckert, Fort, Schott & Yang (2021), NBER WP 26632 (github.com/fpeckert/website, release cbp-data); 1975-85 from the National Archives, 1986+ from the Census Bureau.

## 1880-1940: census manufacturing establishments by county (NHGIS) vs the business directory's hazardous trades

| census | counties | census manufacturing establishments | directory hazardous trades (+/- 2 years) |
|---|---|---|---|
| 1880 | 31 |   599 | 278 |
| 1890 | 56 | 1,518 | 165 |
| 1920 | 60 | 2,626 | 232 |
| 1930 | 35 | 1,452 | 236 |
| 1940 | 59 | 1,298 | 291 |

Censuses with no directory edition within two years are left out (1900: none between 1892 and 1910). The business directory only lists the hazardous trades, so the ratio is a floor on its coverage of all manufacturing; the census counts every establishment above a small output threshold.

## 1870 and 1880: Atack-Bateman-Weiss Census of Manufactures samples

290 Colorado establishments in the state samples (1870: 0, 1880: 290); see atack_colorado.csv.
These are samples of surviving manuscript schedules (not a complete census) and give the county and industry of each establishment, its capital, workers and output, but no street address.
The Census Longitudinal Business Database (1976+) tracks individual establishments nationally but is restricted-access; it is the only national source at the establishment level for the directory era.
