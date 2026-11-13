# Benchmarks: the Colorado directories against the public national manufacturing series

## 1975-2002: County Business Patterns (establishments) vs the Directory of Colorado Manufacturers

| year | CBP manufacturing estab. | directory manufacturers | ratio | CBP hazardous-sector estab. | directory hazardous | ratio |
|---|---|---|---|---|---|---|
| 1976 | 3,071 | 1,860 | 0.61 | 1,026 |   799 | 0.78 |
| 1977 | 3,438 | 3,366 | 0.98 | 1,146 | 1,275 | 1.11 |
| 1979 | 3,414 | 2,087 | 0.61 | 1,148 |   824 | 0.72 |
| 1980 | 3,453 | 3,813 | 1.10 | 1,175 | 1,408 | 1.20 |
| 1982 | 3,797 | 2,304 | 0.61 | 1,319 |   948 | 0.72 |
| 1983 | 4,159 | 4,258 | 1.02 | 1,417 | 1,613 | 1.14 |
| 1984 | 4,339 | 2,173 | 0.50 | 1,429 |   860 | 0.60 |
| 1985 | 4,388 | 1,707 | 0.39 | 1,411 |   636 | 0.45 |
| 1986 | 4,390 | 3,089 | 0.70 | 1,386 | 1,228 | 0.89 |
| 1988 | 4,551 | 3,575 | 0.79 | 1,436 | 1,420 | 0.99 |
| 1990 | 4,878 | 4,192 | 0.86 | 1,536 | 1,566 | 1.02 |
| 1992 | 5,226 | 3,311 | 0.63 | 1,630 | 1,246 | 0.76 |
| 1993 | 5,385 | 1,887 | 0.35 | 1,694 |   779 | 0.46 |
| 1999 | 5,425 | 2,279 | 0.42 | 1,749 |   909 | 0.52 |
| 2002 | 5,250 | 2,134 | 0.41 | 1,698 |   785 | 0.46 |

County-level agreement across 15 editions and 63 counties: r = 0.84 (log manufacturers), 0.88 (log hazardous sectors); median directory/CBP ratio 0.80 (Denver 0.96).

CBP counts every employer establishment with a payroll (from administrative records); the directory lists firms that answered the publisher's questionnaire or were
copied from other lists, so it undercounts the smallest establishments and the ratio is a coverage rate. CBP has no addresses: it cannot replace the directory for siting.
Raw county files from Eckert, Fort, Schott & Yang (2021), NBER WP 26632 (github.com/fpeckert/website, release cbp-data); 1975-85 from the National Archives, 1986+ from the Census Bureau.

## 1880-1940: census manufacturing establishments by county (NHGIS) vs the business directory's hazardous trades

| census | counties | census manufacturing establishments | directory hazardous trades (+/- 2 years) |
|---|---|---|---|
| 1880 | 31 |   599 | 277 |
| 1890 | 56 | 1,518 | 164 |
| 1920 | 60 | 2,626 | 235 |
| 1930 | 35 | 1,452 | 247 |
| 1940 | 59 | 1,298 | 294 |

Censuses with no directory edition within two years are left out (1900: none between 1892 and 1910). The business directory only lists the hazardous trades, so the ratio is a floor on its coverage of all manufacturing; the census counts every establishment above a small output threshold.

## 1870 and 1880: Atack-Bateman-Weiss Census of Manufactures samples

290 Colorado establishments in the state samples (1870: 0, 1880: 290); see atack_colorado.csv.
These are samples of surviving manuscript schedules (not a complete census) and give the county and industry of each establishment, its capital, workers and output, but no street address.
The Census Longitudinal Business Database (1976+) tracks individual establishments nationally but is restricted-access; it is the only national source at the establishment level for the directory era.
