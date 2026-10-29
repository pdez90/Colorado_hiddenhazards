# Hedonic model: Denver residential sales and historical hazardous sites

153,661 arm's-length residential sales, 2015-2026. Effects are percentage differences in sale price (95% CI) relative to sales more than 800 m from any site of that kind.

## Models

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 0.23 | -2.92 | 3.48 | 0.8890 | 0.0023 | 0.0163 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -1.21 | -3.55 | 1.20 | 0.3240 | -0.0121 | 0.0123 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | -0.58 | -2.70 | 1.59 | 0.5990 | -0.0058 | 0.0110 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -0.38 | -4.40 | 3.82 | 0.8570 | -0.0038 | 0.0210 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -1.46 | -4.76 | 1.96 | 0.3990 | -0.0147 | 0.0174 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -0.41 | -2.48 | 1.70 | 0.7010 | -0.0041 | 0.0107 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | -1.77 | -4.54 | 1.08 | 0.2220 | -0.0179 | 0.0146 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | -0.83 | -2.99 | 1.37 | 0.4550 | -0.0084 | 0.0112 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | -0.84 | -2.61 | 0.95 | 0.3560 | -0.0085 | 0.0092 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 0-200 m | 0.52 | -2.60 | 3.75 | 0.7460 | 0.0052 | 0.0161 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 200-400 m | -1.09 | -3.43 | 1.31 | 0.3740 | -0.0109 | 0.0122 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 400-800 m | -0.51 | -2.62 | 1.64 | 0.6390 | -0.0051 | 0.0109 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 0-200 m | -0.31 | -4.27 | 3.82 | 0.8820 | -0.0031 | 0.0207 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 200-400 m | -1.51 | -4.70 | 1.78 | 0.3650 | -0.0152 | 0.0168 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 400-800 m | -0.41 | -2.48 | 1.70 | 0.7010 | -0.0041 | 0.0107 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 0-200 m | -1.81 | -4.57 | 1.03 | 0.2110 | -0.0183 | 0.0145 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 200-400 m | -0.89 | -3.01 | 1.28 | 0.4210 | -0.0089 | 0.0110 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 400-800 m | -0.89 | -2.63 | 0.88 | 0.3220 | -0.0090 | 0.0090 | 153599 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 1.58 | -2.43 | 5.76 | 0.4470 | 0.0157 | 0.0206 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -0.22 | -3.77 | 3.46 | 0.9030 | -0.0022 | 0.0185 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | -0.27 | -2.65 | 2.16 | 0.8250 | -0.0027 | 0.0123 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -0.88 | -4.92 | 3.33 | 0.6760 | -0.0089 | 0.0212 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -2.82 | -5.88 | 0.34 | 0.0814 | -0.0286 | 0.0163 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -1.41 | -3.42 | 0.64 | 0.1790 | -0.0142 | 0.0105 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 1.15 | -3.21 | 5.70 | 0.6130 | 0.0114 | 0.0225 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.47 | -1.44 | 4.47 | 0.3260 | 0.0146 | 0.0149 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.95 | -1.12 | 3.06 | 0.3710 | 0.0095 | 0.0106 | 153622 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 0-200 m | 0.76 | -1.15 | 2.71 | 0.4390 | 0.0076 | 0.0098 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 200-400 m | -0.07 | -1.59 | 1.47 | 0.9280 | -0.0007 | 0.0078 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 400-800 m | -0.06 | -1.10 | 0.98 | 0.9080 | -0.0006 | 0.0053 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 0-200 m | -2.15 | -4.17 | -0.08 | 0.0437 | -0.0217 | 0.0107 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 200-400 m | -1.62 | -3.52 | 0.31 | 0.1020 | -0.0163 | 0.0099 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 400-800 m | -1.33 | -2.68 | 0.04 | 0.0592 | -0.0134 | 0.0070 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 0-200 m | -0.19 | -2.54 | 2.22 | 0.8780 | -0.0019 | 0.0122 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 200-400 m | -0.02 | -1.89 | 1.88 | 0.9800 | -0.0002 | 0.0096 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 400-800 m | 0.20 | -1.13 | 1.54 | 0.7710 | 0.0020 | 0.0068 | 90217 |
| M5 site counts within 400 m | All residential sales | Hidden (no current inventory) | per site within 400 m | 0.37 | -0.62 | 1.36 | 0.4680 | 0.0036 | 0.0050 | 153599 |
| M5 site counts within 400 m | All residential sales | Known (on a current inventory) | per site within 400 m | -0.46 | -1.22 | 0.30 | 0.2380 | -0.0046 | 0.0039 | 153599 |
| M5 site counts within 400 m | All residential sales | Pre-1960 hazardous trade | per site within 400 m | -0.03 | -0.51 | 0.46 | 0.9150 | -0.0003 | 0.0025 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden (no current inventory) | 0-400 m | -0.33 | -1.85 | 1.21 | 0.6700 | -0.0033 | 0.0078 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Known (on a current inventory) | 0-400 m | -0.97 | -3.01 | 1.12 | 0.3610 | -0.0098 | 0.0106 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Pre-1960 hazardous trade | 0-400 m | -0.31 | -1.79 | 1.18 | 0.6800 | -0.0031 | 0.0076 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden minus known | 0-400 m | 0.64 | -2.35 | 3.72 | 0.6770 | 0.0064 | 0.0154 | 153599 |

## Present-day controls (M2)

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M2 + present-day hazards | All residential sales | Present-day control | petro_100 | 0.55 | -1.24 | 2.37 | 0.55100 | 0.0055 | 0.0092 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | tri_500 | -2.50 | -7.36 | 2.62 | 0.33400 | -0.0253 | 0.0261 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | superfund | 2.99 | -13.13 | 22.10 | 0.73500 | 0.0295 | 0.0868 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | freeway_250 | -4.46 | -7.29 | -1.54 | 0.00342 | -0.0456 | 0.0154 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | zoned_ind | -4.07 | -7.86 | -0.12 | 0.04520 | -0.0415 | 0.0206 | 153599 |

## Sales by distance band

| kind | distance | sales | median_price | median_area | median_year_built | pct_condo |
|---|---|---|---|---|---|---|
| hidden | over 800 m | 77913 | 435280 | 1338 | 1974 | 22.2 |
| hidden | 0-200 m | 10750 | 500000 | 1203 | 1959 | 34.8 |
| hidden | 200-400 m | 22097 | 490000 | 1180 | 1961 | 32.0 |
| hidden | 400-800 m | 42901 | 490000 | 1216 | 1956 | 19.7 |
| known | over 800 m | 71327 | 444955 | 1405 | 1976 | 21.6 |
| known | 0-200 m | 16307 | 490000 | 1173 | 1958 | 36.0 |
| known | 200-400 m | 24896 | 489925 | 1154 | 1955 | 26.2 |
| known | 400-800 m | 41131 | 467500 | 1175 | 1954 | 21.2 |
| pre1960 | over 800 m | 89981 | 430000 | 1323 | 1974 | 19.2 |
| pre1960 | 0-200 m | 12259 | 490000 | 1120 | 1962 | 51.8 |
| pre1960 | 200-400 m | 19828 | 511000 | 1154 | 1949 | 32.3 |
| pre1960 | 400-800 m | 31593 | 531000 | 1226 | 1950 | 20.6 |
