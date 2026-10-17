# Denver 1880: residents of the hazardous-trade neighbourhoods

Brown's 1880 HGIS gives 34,386 Denver residents at 4,534 geocoded buildings (17 EDs). The 1878-1885 business directories list 108 hazardous-trade firms in Denver with a street; 69 were placed on the 1880 map (60 at the building or within a few house numbers, 9 at the street only).

## Residents by distance to the nearest hazardous-trade firm (building-level placements)

| band | residents | % foreign born | % German | % Irish | % British | % Scandinavian | % Black | % Chinese | % laborers (employed adults) | mean SEI (employed adults) |
|---|---|---|---|---|---|---|---|---|---|---|
| < 100 m | 10726 | 27.1 | 4.0 | 5.5 | 4.7 | 1.3 | 2.9 | 1.6 | 10.8 | 31.8 |
| 100-250 m | 8985 | 23.7 | 2.8 | 5.1 | 4.6 | 1.7 | 4.6 | 0.4 | 11.3 | 31.3 |
| 250-500 m | 6199 | 24.1 | 2.6 | 5.2 | 5.7 | 2.2 | 1.5 | 0.0 | 10.9 | 31.8 |
| > 500 m | 8476 | 23.9 | 2.0 | 5.9 | 6.7 | 2.4 | 1.8 | 0.0 | 18.9 | 28.3 |

## Person-level models (odds ratio per log-metre of distance; building-clustered SE; > 1 = more common farther away)

| outcome | OR per log m | SE | p | n |
|---|---|---|---|---|
| fb | 0.945 | 0.025 | 0.0259 | 34386 |
| black | 0.883 | 0.056 | 0.0273 | 34386 |
| chinese | 0.331 | 0.165 | 2.1e-11 | 34386 |
| german | 0.800 | 0.046 | 1.36e-06 | 34386 |
| irish | 1.022 | 0.043 | 0.607 | 34386 |
| laborer | 1.201 | 0.058 | 0.00149 | 15391 |
| sei (employed adults, linear) | -1.040 | 0.344 | 0.00247 | 15391 |

## Enumeration districts: hazardous firms and composition

| ED | population | firms | % foreign born | % Black | % German | % Irish | mean SEI |
|---|---|---|---|---|---|---|---|
| 1 | 2516 | 5 | 31.0 | 1.0 | 21.3 | 12.2 | 27.0 |
| 2 | 2362 | 0 | 29.9 | 0.0 | 16.4 | 12.6 | 23.1 |
| 3 | 2376 | 1 | 24.1 | 1.0 | 9.1 | 10.6 | 28.9 |
| 4 | 1727 | 5 | 28.0 | 1.0 | 14.8 | 9.1 | 28.8 |
| 5 | 2289 | 12 | 22.5 | 1.0 | 13.1 | 7.4 | 39.6 |
| 6 | 2023 | 0 | 23.7 | 3.0 | 7.8 | 12.3 | 35.1 |
| 7 | 2106 | 0 | 20.0 | 2.0 | 6.9 | 13.8 | 34.8 |
| 8 | 1930 | 0 | 18.4 | 2.0 | 6.2 | 8.3 | 33.8 |
| 9 | 1314 | 4 | 39.1 | 7.0 | 10.0 | 18.5 | 25.0 |
| 10 | 1749 | 22 | 25.7 | 7.0 | 9.7 | 9.0 | 30.3 |
| 11 | 2299 | 4 | 21.1 | 3.0 | 10.7 | 8.5 | 37.0 |
| 12 | 1523 | 0 | 16.4 | 8.0 | 6.7 | 7.6 | 36.5 |
| 13 | 2134 | 3 | 24.5 | 10.0 | 13.3 | 10.4 | 23.8 |
| 14 | 1877 | 1 | 21.3 | 3.0 | 5.6 | 4.5 | 32.0 |
| 15 | 2431 | 0 | 17.1 | 1.0 | 7.7 | 6.0 | 35.3 |
| 16 | 1358 | 0 | 23.5 | 3.0 | 7.4 | 13.8 | 27.7 |
| 17 | 2392 | 3 | 38.3 | 0.0 | 16.7 | 16.2 | 23.1 |
