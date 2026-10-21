# Hedonic model: Denver residential sales and historical hazardous sites

153,661 arm's-length residential sales, 2015-2026. Effects are percentage differences in sale price (95% CI) relative to sales more than 800 m from any site of that kind.

## Models

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | -0.19 | -3.20 | 2.91 | 0.9030 | -0.0019 | 0.0156 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -1.33 | -3.63 | 1.03 | 0.2700 | -0.0134 | 0.0121 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | -0.68 | -2.78 | 1.47 | 0.5350 | -0.0068 | 0.0109 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -0.37 | -4.39 | 3.82 | 0.8620 | -0.0037 | 0.0210 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -1.45 | -4.75 | 1.97 | 0.4020 | -0.0146 | 0.0174 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -0.39 | -2.46 | 1.72 | 0.7140 | -0.0039 | 0.0107 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | -1.71 | -4.51 | 1.17 | 0.2430 | -0.0173 | 0.0147 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | -0.81 | -2.97 | 1.40 | 0.4690 | -0.0082 | 0.0112 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | -0.84 | -2.61 | 0.96 | 0.3590 | -0.0084 | 0.0092 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 0-200 m | 0.16 | -2.85 | 3.27 | 0.9170 | 0.0016 | 0.0156 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 200-400 m | -1.22 | -3.52 | 1.14 | 0.3100 | -0.0122 | 0.0120 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 400-800 m | -0.62 | -2.71 | 1.52 | 0.5700 | -0.0062 | 0.0108 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 0-200 m | -0.30 | -4.26 | 3.83 | 0.8850 | -0.0030 | 0.0207 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 200-400 m | -1.50 | -4.69 | 1.79 | 0.3680 | -0.0151 | 0.0168 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 400-800 m | -0.39 | -2.46 | 1.71 | 0.7130 | -0.0039 | 0.0107 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 0-200 m | -1.76 | -4.54 | 1.11 | 0.2280 | -0.0177 | 0.0146 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 200-400 m | -0.86 | -3.00 | 1.31 | 0.4350 | -0.0087 | 0.0111 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 400-800 m | -0.89 | -2.63 | 0.88 | 0.3250 | -0.0089 | 0.0090 | 153599 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 1.11 | -2.73 | 5.10 | 0.5780 | 0.0110 | 0.0198 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -0.37 | -3.83 | 3.21 | 0.8360 | -0.0037 | 0.0180 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | -0.30 | -2.67 | 2.12 | 0.8040 | -0.0030 | 0.0123 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -0.86 | -4.89 | 3.34 | 0.6830 | -0.0087 | 0.0212 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -2.82 | -5.87 | 0.33 | 0.0806 | -0.0286 | 0.0163 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -1.41 | -3.42 | 0.64 | 0.1790 | -0.0142 | 0.0105 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 1.23 | -3.13 | 5.79 | 0.5870 | 0.0122 | 0.0225 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.51 | -1.41 | 4.50 | 0.3160 | 0.0149 | 0.0149 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.94 | -1.13 | 3.05 | 0.3760 | 0.0094 | 0.0106 | 153622 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 0-200 m | 0.47 | -1.35 | 2.32 | 0.6170 | 0.0047 | 0.0093 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 200-400 m | -0.21 | -1.68 | 1.28 | 0.7810 | -0.0021 | 0.0076 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 400-800 m | -0.19 | -1.18 | 0.81 | 0.7100 | -0.0019 | 0.0051 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 0-200 m | -2.12 | -4.14 | -0.06 | 0.0454 | -0.0214 | 0.0106 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 200-400 m | -1.60 | -3.49 | 0.33 | 0.1060 | -0.0161 | 0.0099 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 400-800 m | -1.31 | -2.66 | 0.06 | 0.0637 | -0.0131 | 0.0070 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 0-200 m | -0.16 | -2.52 | 2.26 | 0.8950 | -0.0016 | 0.0122 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 200-400 m | -0.01 | -1.89 | 1.90 | 0.9900 | -0.0001 | 0.0097 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 400-800 m | 0.20 | -1.12 | 1.54 | 0.7680 | 0.0020 | 0.0068 | 90217 |
| M5 site counts within 400 m | All residential sales | Hidden (no current inventory) | per site within 400 m | 0.30 | -0.65 | 1.27 | 0.5370 | 0.0030 | 0.0049 | 153599 |
| M5 site counts within 400 m | All residential sales | Known (on a current inventory) | per site within 400 m | -0.46 | -1.21 | 0.31 | 0.2430 | -0.0046 | 0.0039 | 153599 |
| M5 site counts within 400 m | All residential sales | Pre-1960 hazardous trade | per site within 400 m | -0.02 | -0.51 | 0.47 | 0.9310 | -0.0002 | 0.0025 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden (no current inventory) | 0-400 m | -0.44 | -1.94 | 1.08 | 0.5680 | -0.0044 | 0.0077 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Known (on a current inventory) | 0-400 m | -0.96 | -3.01 | 1.12 | 0.3630 | -0.0097 | 0.0106 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Pre-1960 hazardous trade | 0-400 m | -0.31 | -1.79 | 1.19 | 0.6840 | -0.0031 | 0.0076 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden minus known | 0-400 m | 0.53 | -2.44 | 3.59 | 0.7300 | 0.0053 | 0.0153 | 153599 |

## Present-day controls (M2)

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M2 + present-day hazards | All residential sales | Present-day control | petro_100 | 0.56 | -1.24 | 2.38 | 0.54700 | 0.0056 | 0.0092 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | tri_500 | -2.46 | -7.36 | 2.69 | 0.34400 | -0.0250 | 0.0263 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | superfund | 3.00 | -13.02 | 21.98 | 0.73200 | 0.0296 | 0.0863 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | freeway_250 | -4.47 | -7.29 | -1.56 | 0.00325 | -0.0458 | 0.0153 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | zoned_ind | -4.25 | -8.02 | -0.33 | 0.03540 | -0.0435 | 0.0205 | 153599 |

## Sales by distance band

| kind | distance | sales | median_price | median_area | median_year_built | pct_condo |
|---|---|---|---|---|---|---|
| hidden | over 800 m | 77572 | 435000.0 | 1338 | 1974 | 22.3 |
| hidden | 0-200 m | 11082 | 500000.0 | 1204 | 1959 | 34.0 |
| hidden | 200-400 m | 22295 | 490000.0 | 1180 | 1960 | 31.7 |
| hidden | 400-800 m | 42712 | 489999.5 | 1216 | 1956 | 19.7 |
| known | over 800 m | 71327 | 444955.0 | 1405 | 1976 | 21.6 |
| known | 0-200 m | 16307 | 490000.0 | 1173 | 1958 | 36.0 |
| known | 200-400 m | 24896 | 489925.0 | 1154 | 1955 | 26.2 |
| known | 400-800 m | 41131 | 467500.0 | 1175 | 1954 | 21.2 |
| pre1960 | over 800 m | 89981 | 430000.0 | 1323 | 1974 | 19.2 |
| pre1960 | 0-200 m | 12259 | 490000.0 | 1120 | 1962 | 51.8 |
| pre1960 | 200-400 m | 19828 | 511000.0 | 1154 | 1949 | 32.3 |
| pre1960 | 400-800 m | 31593 | 531000.0 | 1226 | 1950 | 20.6 |
