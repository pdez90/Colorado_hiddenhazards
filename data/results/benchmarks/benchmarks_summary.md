# Benchmarks: the Colorado directories against the public national manufacturing series

## 1975-2002: County Business Patterns (establishments) vs the Directory of Colorado Manufacturers

| year | CBP manufacturing estab. | directory manufacturers | ratio | CBP hazardous-sector estab. | directory hazardous | ratio |
|---|---|---|---|---|---|---|
| 1976 | 3,071 | 1,672 | 0.54 | 1,026 |   732 | 0.71 |
| 1977 | 3,438 | 2,237 | 0.65 | 1,146 |   886 | 0.77 |
| 1979 | 3,414 | 1,560 | 0.46 | 1,148 |   643 | 0.56 |
| 1980 | 3,453 | 3,633 | 1.05 | 1,175 | 1,358 | 1.16 |
| 1982 | 3,797 | 2,098 | 0.55 | 1,319 |   874 | 0.66 |
| 1983 | 4,159 | 3,921 | 0.94 | 1,417 | 1,511 | 1.07 |
| 1984 | 4,339 | 1,651 | 0.38 | 1,429 |   704 | 0.49 |
| 1985 | 4,388 | 1,348 | 0.31 | 1,411 |   544 | 0.39 |
| 1986 | 4,390 | 2,986 | 0.68 | 1,386 | 1,200 | 0.87 |
| 1988 | 4,551 | 3,547 | 0.78 | 1,436 | 1,405 | 0.98 |
| 1990 | 4,878 | 4,064 | 0.83 | 1,536 | 1,523 | 0.99 |
| 1992 | 5,226 | 2,512 | 0.48 | 1,630 |   987 | 0.61 |
| 1993 | 5,385 | 1,873 | 0.35 | 1,694 |   777 | 0.46 |
| 1999 | 5,425 | 2,260 | 0.42 | 1,749 |   904 | 0.52 |
| 2002 | 5,250 | 2,130 | 0.41 | 1,698 |   783 | 0.46 |

County-level agreement across 15 editions and 63 counties: r = 0.85 (log manufacturers), 0.88 (log hazardous sectors); median directory/CBP ratio NA (Denver 0.77).

CBP counts every employer establishment with a payroll (from administrative records); the directory lists firms that answered the publisher's questionnaire or were
copied from other lists, so it undercounts the smallest establishments and the ratio is a coverage rate. CBP has no addresses: it cannot replace the directory for siting.
Raw county files from Eckert, Fort, Schott & Yang (2021), NBER WP 26632 (github.com/fpeckert/website, release cbp-data); 1975-85 from the National Archives, 1986+ from the Census Bureau.

## 1880-1940: census manufacturing establishments by county (NHGIS) vs the business directory's hazardous trades

| census | counties | census manufacturing establishments | directory hazardous trades (+/- 2 years) |
|---|---|---|---|

The business directory only lists the hazardous trades, so the ratio is a floor on its coverage of all manufacturing; the census counts every establishment above a small output threshold.

## 1870 and 1880: Atack-Bateman-Weiss Census of Manufactures samples

290 Colorado establishments in the state samples (1870: 0, 1880: 290); see atack_colorado.csv.
These are samples of surviving manuscript schedules (not a complete census) and give the county and industry of each establishment, its capital, workers and output, but no street address.
The Census Longitudinal Business Database (1976+) tracks individual establishments nationally but is restricted-access; it is the only national source at the establishment level for the directory era.
