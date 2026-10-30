# Hedonic model: Denver residential sales and historical hazardous sites

153,661 arm's-length residential sales, 2015-2026. Effects are percentage differences in sale price (95% CI) relative to sales more than 800 m from any site of that kind.

## Models

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 0.33 | -2.24 | 2.97 | 0.803 | 0.0033 | 0.0132 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -0.23 | -2.37 | 1.96 | 0.835 | -0.0023 | 0.0111 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | 0.45 | -1.38 | 2.31 | 0.635 | 0.0045 | 0.0094 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -2.40 | -5.56 | 0.86 | 0.150 | -0.0243 | 0.0168 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -0.89 | -3.15 | 1.42 | 0.448 | -0.0089 | 0.0118 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -1.34 | -3.40 | 0.76 | 0.212 | -0.0135 | 0.0108 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | -1.54 | -4.30 | 1.30 | 0.287 | -0.0155 | 0.0145 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | -0.77 | -2.88 | 1.38 | 0.479 | -0.0078 | 0.0109 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | -0.85 | -2.62 | 0.96 | 0.357 | -0.0085 | 0.0092 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 0-200 m | 0.41 | -2.16 | 3.04 | 0.758 | 0.0041 | 0.0132 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 200-400 m | -0.24 | -2.38 | 1.95 | 0.830 | -0.0024 | 0.0111 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 400-800 m | 0.40 | -1.41 | 2.24 | 0.668 | 0.0040 | 0.0093 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 0-200 m | -2.31 | -5.53 | 1.01 | 0.173 | -0.0234 | 0.0171 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 200-400 m | -0.91 | -3.12 | 1.36 | 0.431 | -0.0091 | 0.0115 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 400-800 m | -1.31 | -3.33 | 0.76 | 0.215 | -0.0131 | 0.0106 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 0-200 m | -1.57 | -4.32 | 1.25 | 0.274 | -0.0159 | 0.0144 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 200-400 m | -0.83 | -2.92 | 1.31 | 0.445 | -0.0083 | 0.0109 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 400-800 m | -0.89 | -2.66 | 0.91 | 0.331 | -0.0090 | 0.0092 | 153599 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 1.29 | -1.77 | 4.44 | 0.414 | 0.0128 | 0.0156 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | 1.12 | -1.75 | 4.08 | 0.451 | 0.0111 | 0.0147 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | 1.53 | -0.68 | 3.79 | 0.177 | 0.0152 | 0.0112 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -1.70 | -5.66 | 2.43 | 0.416 | -0.0171 | 0.0210 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -1.47 | -4.14 | 1.28 | 0.293 | -0.0148 | 0.0140 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -1.85 | -4.02 | 0.37 | 0.104 | -0.0187 | 0.0114 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 1.37 | -2.87 | 5.80 | 0.533 | 0.0136 | 0.0218 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.27 | -1.54 | 4.16 | 0.381 | 0.0126 | 0.0144 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.75 | -1.29 | 2.83 | 0.475 | 0.0075 | 0.0104 | 153622 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 0-200 m | -1.00 | -2.64 | 0.68 | 0.243 | -0.0100 | 0.0085 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 200-400 m | -0.94 | -2.31 | 0.45 | 0.187 | -0.0094 | 0.0071 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 400-800 m | -0.52 | -1.59 | 0.57 | 0.348 | -0.0052 | 0.0055 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 0-200 m | -1.28 | -3.32 | 0.79 | 0.226 | -0.0129 | 0.0106 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 200-400 m | -0.83 | -2.71 | 1.09 | 0.396 | -0.0083 | 0.0098 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 400-800 m | -0.33 | -1.73 | 1.08 | 0.642 | -0.0034 | 0.0072 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 0-200 m | -0.03 | -2.49 | 2.48 | 0.979 | -0.0003 | 0.0127 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 200-400 m | 0.02 | -1.91 | 1.99 | 0.980 | 0.0002 | 0.0099 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 400-800 m | 0.20 | -1.18 | 1.59 | 0.783 | 0.0020 | 0.0071 | 90217 |
| M5 site counts within 400 m | All residential sales | Hidden (no current inventory) | per site within 400 m | -0.01 | -0.67 | 0.66 | 0.984 | -0.0001 | 0.0034 | 153599 |
| M5 site counts within 400 m | All residential sales | Known (on a current inventory) | per site within 400 m | -0.35 | -0.93 | 0.23 | 0.239 | -0.0035 | 0.0030 | 153599 |
| M5 site counts within 400 m | All residential sales | Pre-1960 hazardous trade | per site within 400 m | -0.03 | -0.54 | 0.49 | 0.923 | -0.0003 | 0.0026 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden (no current inventory) | 0-400 m | -0.50 | -1.76 | 0.78 | 0.442 | -0.0050 | 0.0065 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Known (on a current inventory) | 0-400 m | -0.18 | -1.45 | 1.12 | 0.789 | -0.0018 | 0.0066 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Pre-1960 hazardous trade | 0-400 m | -0.37 | -1.79 | 1.08 | 0.618 | -0.0037 | 0.0073 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden minus known | 0-400 m | -0.33 | -2.01 | 1.39 | 0.708 | -0.0033 | 0.0087 | 153599 |

## Present-day controls (M2)

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M2 + present-day hazards | All residential sales | Present-day control | petro_100 | 0.71 | -1.16 | 2.62 | 0.45900 | 0.0071 | 0.0096 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | tri_500 | -2.31 | -7.37 | 3.03 | 0.39100 | -0.0233 | 0.0272 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | superfund | 3.20 | -13.08 | 22.53 | 0.71900 | 0.0315 | 0.0876 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | freeway_250 | -4.34 | -7.24 | -1.34 | 0.00545 | -0.0444 | 0.0157 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | zoned_ind | -3.44 | -7.13 | 0.39 | 0.07960 | -0.0350 | 0.0199 | 153599 |

## Sales by distance band

| kind | distance | sales | median_price | median_area | median_year_built | pct_condo |
|---|---|---|---|---|---|---|
| hidden | over 800 m | 60806 | 420000 | 1363 | 1979 | 20.9 |
| hidden | 0-200 m | 15261 | 500000 | 1205 | 1966 | 33.7 |
| hidden | 200-400 m | 28335 | 500000 | 1189 | 1959 | 29.4 |
| hidden | 400-800 m | 49259 | 491000 | 1228 | 1957 | 21.1 |
| known | over 800 m | 76642 | 445000 | 1383 | 1974 | 20.0 |
| known | 0-200 m | 15301 | 480000 | 1156 | 1964 | 39.1 |
| known | 200-400 m | 23072 | 499900 | 1161 | 1955 | 28.3 |
| known | 400-800 m | 38646 | 470000 | 1161 | 1954 | 22.5 |
| pre1960 | over 800 m | 89981 | 430000 | 1323 | 1974 | 19.2 |
| pre1960 | 0-200 m | 12259 | 490000 | 1120 | 1962 | 51.8 |
| pre1960 | 200-400 m | 19828 | 511000 | 1154 | 1949 | 32.3 |
| pre1960 | 400-800 m | 31593 | 531000 | 1226 | 1950 | 20.6 |
