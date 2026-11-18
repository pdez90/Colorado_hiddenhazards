# Hedonic model: Denver residential sales and historical hazardous sites

153,661 arm's-length residential sales, 2015-2026. Effects are percentage differences in sale price (95% CI) relative to sales more than 800 m from any site of that kind.

## Models

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | -1.19 | -4.44 | 2.17 | 0.4830 | -0.0120 | 0.0170 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -2.64 | -5.45 | 0.26 | 0.0757 | -0.0267 | 0.0149 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | -0.89 | -3.23 | 1.52 | 0.4690 | -0.0089 | 0.0122 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -0.18 | -3.31 | 3.06 | 0.9140 | -0.0018 | 0.0163 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 200-400 m | 0.96 | -1.28 | 3.25 | 0.4040 | 0.0096 | 0.0115 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -0.48 | -2.20 | 1.28 | 0.5920 | -0.0048 | 0.0089 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 0.59 | -2.35 | 3.61 | 0.6990 | 0.0059 | 0.0151 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.20 | -1.17 | 3.62 | 0.3250 | 0.0119 | 0.0121 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.12 | -2.12 | 2.41 | 0.9160 | 0.0012 | 0.0115 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 0-200 m | -1.08 | -4.33 | 2.27 | 0.5240 | -0.0109 | 0.0170 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 200-400 m | -2.56 | -5.37 | 0.33 | 0.0843 | -0.0259 | 0.0149 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 400-800 m | -0.83 | -3.13 | 1.53 | 0.4880 | -0.0083 | 0.0120 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 0-200 m | -0.05 | -3.31 | 3.33 | 0.9780 | -0.0005 | 0.0170 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 200-400 m | 0.94 | -1.33 | 3.25 | 0.4220 | 0.0093 | 0.0116 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 400-800 m | -0.49 | -2.20 | 1.24 | 0.5770 | -0.0049 | 0.0088 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 0-200 m | 0.67 | -2.31 | 3.74 | 0.6640 | 0.0067 | 0.0153 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.14 | -1.16 | 3.49 | 0.3370 | 0.0113 | 0.0117 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.04 | -2.10 | 2.21 | 0.9740 | 0.0004 | 0.0110 | 153599 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | -0.30 | -4.08 | 3.63 | 0.8800 | -0.0030 | 0.0197 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -2.05 | -5.23 | 1.25 | 0.2220 | -0.0207 | 0.0169 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | -0.07 | -2.52 | 2.44 | 0.9560 | -0.0007 | 0.0127 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 0-200 m | 1.51 | -3.36 | 6.63 | 0.5510 | 0.0150 | 0.0251 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 200-400 m | 1.47 | -2.84 | 5.98 | 0.5110 | 0.0146 | 0.0222 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -0.96 | -3.13 | 1.25 | 0.3920 | -0.0097 | 0.0113 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 3.43 | -1.88 | 9.02 | 0.2120 | 0.0337 | 0.0269 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.59 | -2.27 | 5.61 | 0.4260 | 0.0158 | 0.0198 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 1.56 | -1.79 | 5.03 | 0.3670 | 0.0155 | 0.0171 | 153622 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 0-200 m | -0.81 | -2.70 | 1.11 | 0.4060 | -0.0082 | 0.0098 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 200-400 m | -1.09 | -2.68 | 0.53 | 0.1870 | -0.0109 | 0.0083 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 400-800 m | -0.72 | -1.84 | 0.40 | 0.2100 | -0.0073 | 0.0058 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 0-200 m | -0.50 | -2.59 | 1.64 | 0.6470 | -0.0050 | 0.0109 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 200-400 m | -0.59 | -2.41 | 1.27 | 0.5330 | -0.0059 | 0.0094 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 400-800 m | -0.22 | -1.66 | 1.24 | 0.7660 | -0.0022 | 0.0074 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 0-200 m | 0.42 | -2.58 | 3.51 | 0.7870 | 0.0042 | 0.0154 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 200-400 m | 0.80 | -1.25 | 2.89 | 0.4490 | 0.0079 | 0.0105 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 400-800 m | 0.36 | -1.16 | 1.91 | 0.6460 | 0.0036 | 0.0078 | 90217 |
| M5 site counts within 400 m | All residential sales | Hidden (no current inventory) | per site within 400 m | -0.40 | -1.38 | 0.58 | 0.4240 | -0.0040 | 0.0050 | 153599 |
| M5 site counts within 400 m | All residential sales | Known (on a current inventory) | per site within 400 m | -0.08 | -0.46 | 0.30 | 0.6900 | -0.0008 | 0.0019 | 153599 |
| M5 site counts within 400 m | All residential sales | Pre-1960 hazardous trade | per site within 400 m | -0.06 | -0.59 | 0.48 | 0.8270 | -0.0006 | 0.0027 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden (no current inventory) | 0-400 m | -1.65 | -3.30 | 0.02 | 0.0549 | -0.0167 | 0.0086 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Known (on a current inventory) | 0-400 m | 1.04 | -0.57 | 2.68 | 0.2070 | 0.0104 | 0.0082 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Pre-1960 hazardous trade | 0-400 m | 0.93 | -0.31 | 2.18 | 0.1450 | 0.0092 | 0.0063 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden minus known | 0-400 m | -2.67 | -4.92 | -0.36 | 0.0236 | -0.0271 | 0.0120 | 153599 |

## Present-day controls (M2)

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M2 + present-day hazards | All residential sales | Present-day control | petro_100 | 0.67 | -1.20 | 2.57 | 0.4870 | 0.0067 | 0.0096 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | tri_500 | -2.66 | -7.66 | 2.60 | 0.3170 | -0.0270 | 0.0269 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | superfund | 2.62 | -13.64 | 21.93 | 0.7700 | 0.0258 | 0.0880 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | freeway_250 | -4.14 | -7.05 | -1.15 | 0.0078 | -0.0423 | 0.0157 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | zoned_ind | -1.51 | -6.83 | 4.11 | 0.5920 | -0.0152 | 0.0283 | 153599 |

## Sales by distance band

| kind | distance | sales | median_price | median_area | median_year_built | pct_condo |
|---|---|---|---|---|---|---|
| hidden | over 800 m | 77581 | 445000.0 | 1377.0 | 1979 | 21.6 |
| hidden | 0-200 m | 10252 | 487000.0 | 1205.0 | 1961 | 35.8 |
| hidden | 200-400 m | 21281 | 470000.0 | 1142.0 | 1959 | 30.2 |
| hidden | 400-800 m | 44547 | 484950.0 | 1200.0 | 1955 | 21.8 |
| known | over 800 m | 83683 | 445000.0 | 1355.0 | 1972 | 22.0 |
| known | 0-200 m | 13322 | 485000.0 | 1173.0 | 1967 | 39.7 |
| known | 200-400 m | 19704 | 507500.0 | 1168.5 | 1955 | 25.3 |
| known | 400-800 m | 36952 | 468000.0 | 1171.0 | 1955 | 21.2 |
| pre1960 | over 800 m | 106980 | 436945.5 | 1302.0 | 1972 | 20.6 |
| pre1960 | 0-200 m | 9426 | 511000.0 | 1143.0 | 1979 | 57.9 |
| pre1960 | 200-400 m | 14008 | 520000.0 | 1151.0 | 1952 | 33.5 |
| pre1960 | 400-800 m | 23247 | 535600.0 | 1211.0 | 1946 | 19.0 |
