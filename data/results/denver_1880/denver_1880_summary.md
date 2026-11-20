# Denver 1880: residents of the hazardous-trade neighbourhoods

Brown's 1880 HGIS gives 34,386 Denver residents at 4,534 geocoded buildings (17 EDs). The 1878-1885 business directories list 83 hazardous-trade firms in Denver with a street; 54 were placed on the 1880 map (48 at the building or within a few house numbers, 6 at the street only).

## Residents by distance to the nearest hazardous-trade firm (building-level placements)

| band | residents | % foreign born | % German | % Irish | % British | % Scandinavian | % Black | % Chinese | % laborers (employed adults) | mean SEI (employed adults) |
|---|---|---|---|---|---|---|---|---|---|---|
| < 100 m | 9929 | 27.8 | 5.5 | 5.7 | 4.8 | 1.3 | 2.3 | 1.8 | 11.1 | 31.9 |
| 100-250 m | 8386 | 24.1 | 4.6 | 5.1 | 4.8 | 1.7 | 4.9 | 0.4 | 11.5 | 30.7 |
| 250-500 m | 6808 | 23.4 | 3.8 | 5.3 | 5.4 | 1.9 | 2.2 | 0.0 | 10.5 | 32.1 |
| > 500 m | 9263 | 23.6 | 3.3 | 5.6 | 6.5 | 2.6 | 1.8 | 0.0 | 17.9 | 28.9 |

## Person-level models (odds ratio per log-metre of distance; building-clustered SE; > 1 = more common farther away)

| outcome | OR per log m | SE | p | n |
|---|---|---|---|---|
| fb | 0.929 | 0.026 | 0.0045 | 34386 |
| native_white | 1.085 | 0.026 | 0.0015 | 34386 |
| white | 1.311 | 0.082 | 0.00101 | 34386 |
| black | 0.915 | 0.061 | 0.142 | 34386 |
| chinese | 0.328 | 0.168 | 3.17e-11 | 34386 |
| german | 0.849 | 0.038 | 1.35e-05 | 34386 |
| irish | 1.003 | 0.043 | 0.946 | 34386 |
| british | 1.110 | 0.038 | 0.00671 | 34386 |
| scandinavian | 1.284 | 0.091 | 0.00613 | 34386 |
| canadian | 0.901 | 0.043 | 0.0156 | 34386 |
| other_fb | 0.871 | 0.033 | 2.84e-05 | 34386 |
| laborer | 1.170 | 0.058 | 0.00688 | 15391 |
| sei (employed adults, linear) | -0.736 | 0.343 | 0.0322 | 15391 |

## Enumeration districts: hazardous firms and composition

| ED | population | firms | % foreign born | % Black | % German | % Irish | mean SEI |
|---|---|---|---|---|---|---|---|
| 1 | 2516 | 5 | 31.0 | 1.0 | 21.3 | 12.2 | 27.0 |
| 2 | 2362 | 0 | 29.9 | 0.0 | 16.4 | 12.6 | 23.1 |
| 3 | 2376 | 1 | 24.1 | 1.0 | 9.1 | 10.6 | 28.9 |
| 4 | 1727 | 3 | 28.0 | 1.0 | 14.8 | 9.1 | 28.8 |
| 5 | 2289 | 11 | 22.5 | 1.0 | 13.1 | 7.4 | 39.6 |
| 6 | 2023 | 0 | 23.7 | 3.0 | 7.8 | 12.3 | 35.1 |
| 7 | 2106 | 0 | 20.0 | 2.0 | 6.9 | 13.8 | 34.8 |
| 8 | 1930 | 0 | 18.4 | 2.0 | 6.2 | 8.3 | 33.8 |
| 9 | 1314 | 4 | 39.1 | 7.0 | 10.0 | 18.5 | 25.0 |
| 10 | 1749 | 15 | 25.7 | 7.0 | 9.7 | 9.0 | 30.3 |
| 11 | 2299 | 2 | 21.1 | 3.0 | 10.7 | 8.5 | 37.0 |
| 12 | 1523 | 0 | 16.4 | 8.0 | 6.7 | 7.6 | 36.5 |
| 13 | 2134 | 3 | 24.5 | 10.0 | 13.3 | 10.4 | 23.8 |
| 14 | 1877 | 1 | 21.3 | 3.0 | 5.6 | 4.5 | 32.0 |
| 15 | 2431 | 0 | 17.1 | 1.0 | 7.7 | 6.0 | 35.3 |
| 16 | 1358 | 0 | 23.5 | 3.0 | 7.4 | 13.8 | 27.7 |
| 17 | 2392 | 3 | 38.3 | 0.0 | 16.7 | 16.2 | 23.1 |
