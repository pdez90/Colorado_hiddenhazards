# Hedonic model: Denver residential sales and historical hazardous sites

153,661 arm's-length residential sales, 2015-2026. Effects are percentage differences in sale price (95% CI) relative to sales more than 800 m from any site of that kind.

## Models

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 0.22 | -2.41 | 2.92 | 0.8720 | 0.0022 | 0.0136 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -0.30 | -2.50 | 1.95 | 0.7920 | -0.0030 | 0.0114 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | 0.55 | -1.34 | 2.47 | 0.5730 | 0.0054 | 0.0096 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -2.57 | -5.65 | 0.62 | 0.1150 | -0.0260 | 0.0164 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -1.05 | -3.23 | 1.18 | 0.3560 | -0.0105 | 0.0114 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -1.40 | -3.38 | 0.62 | 0.1740 | -0.0141 | 0.0103 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 0.05 | -2.73 | 2.92 | 0.9710 | 0.0005 | 0.0144 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.00 | -1.39 | 3.44 | 0.4170 | 0.0099 | 0.0122 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.05 | -1.91 | 2.04 | 0.9640 | 0.0005 | 0.0101 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 0-200 m | 0.29 | -2.33 | 2.99 | 0.8310 | 0.0029 | 0.0135 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 200-400 m | -0.31 | -2.53 | 1.95 | 0.7850 | -0.0031 | 0.0115 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 400-800 m | 0.49 | -1.39 | 2.40 | 0.6110 | 0.0049 | 0.0096 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 0-200 m | -2.49 | -5.64 | 0.77 | 0.1350 | -0.0252 | 0.0168 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 200-400 m | -1.06 | -3.21 | 1.13 | 0.3400 | -0.0107 | 0.0112 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 400-800 m | -1.38 | -3.33 | 0.60 | 0.1720 | -0.0139 | 0.0102 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 0-200 m | 0.03 | -2.75 | 2.90 | 0.9820 | 0.0003 | 0.0144 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 200-400 m | 0.98 | -1.39 | 3.40 | 0.4230 | 0.0097 | 0.0121 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.01 | -1.94 | 2.00 | 0.9930 | 0.0001 | 0.0100 | 153599 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 0.64 | -2.38 | 3.76 | 0.6810 | 0.0064 | 0.0155 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | 0.28 | -2.42 | 3.06 | 0.8410 | 0.0028 | 0.0140 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | 1.35 | -0.96 | 3.71 | 0.2570 | 0.0134 | 0.0118 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -1.57 | -5.60 | 2.63 | 0.4580 | -0.0159 | 0.0213 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -1.07 | -4.02 | 1.97 | 0.4880 | -0.0107 | 0.0155 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -2.24 | -4.21 | -0.22 | 0.0313 | -0.0226 | 0.0104 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 3.49 | -1.58 | 8.82 | 0.1830 | 0.0343 | 0.0256 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 2.59 | -1.32 | 6.66 | 0.1990 | 0.0256 | 0.0198 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 2.46 | -0.83 | 5.87 | 0.1470 | 0.0243 | 0.0167 | 153622 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 0-200 m | -0.98 | -2.67 | 0.74 | 0.2630 | -0.0099 | 0.0088 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 200-400 m | -0.93 | -2.32 | 0.48 | 0.1990 | -0.0093 | 0.0072 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 400-800 m | -0.48 | -1.54 | 0.59 | 0.3770 | -0.0048 | 0.0055 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 0-200 m | -1.42 | -3.41 | 0.61 | 0.1700 | -0.0143 | 0.0104 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 200-400 m | -0.91 | -2.75 | 0.96 | 0.3400 | -0.0091 | 0.0095 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 400-800 m | -0.36 | -1.75 | 1.04 | 0.6100 | -0.0036 | 0.0071 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 0-200 m | 0.85 | -1.55 | 3.31 | 0.4920 | 0.0085 | 0.0123 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 200-400 m | 0.64 | -1.30 | 2.61 | 0.5230 | 0.0064 | 0.0099 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 400-800 m | 0.42 | -0.89 | 1.74 | 0.5360 | 0.0042 | 0.0067 | 90217 |
| M5 site counts within 400 m | All residential sales | Hidden (no current inventory) | per site within 400 m | 0.03 | -0.71 | 0.78 | 0.9290 | 0.0003 | 0.0038 | 153599 |
| M5 site counts within 400 m | All residential sales | Known (on a current inventory) | per site within 400 m | -0.35 | -0.85 | 0.15 | 0.1740 | -0.0035 | 0.0026 | 153599 |
| M5 site counts within 400 m | All residential sales | Pre-1960 hazardous trade | per site within 400 m | -0.04 | -0.65 | 0.58 | 0.9020 | -0.0004 | 0.0031 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden (no current inventory) | 0-400 m | -0.65 | -1.89 | 0.61 | 0.3150 | -0.0065 | 0.0064 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Known (on a current inventory) | 0-400 m | -0.22 | -1.51 | 1.07 | 0.7340 | -0.0022 | 0.0066 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Pre-1960 hazardous trade | 0-400 m | 0.65 | -0.75 | 2.07 | 0.3650 | 0.0065 | 0.0071 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden minus known | 0-400 m | -0.42 | -2.09 | 1.27 | 0.6210 | -0.0042 | 0.0086 | 153599 |

## Present-day controls (M2)

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M2 + present-day hazards | All residential sales | Present-day control | petro_100 | 0.74 | -1.13 | 2.65 | 0.44100 | 0.0074 | 0.0096 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | tri_500 | -2.31 | -7.36 | 3.00 | 0.38800 | -0.0234 | 0.0270 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | superfund | 3.08 | -13.11 | 22.27 | 0.72900 | 0.0303 | 0.0871 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | freeway_250 | -4.32 | -7.23 | -1.32 | 0.00574 | -0.0442 | 0.0158 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | zoned_ind | -3.39 | -7.10 | 0.46 | 0.08570 | -0.0345 | 0.0200 | 153599 |

## Sales by distance band

| kind | distance | sales | median_price | median_area | median_year_built | pct_condo |
|---|---|---|---|---|---|---|
| hidden | over 800 m | 62148 | 420000 | 1364 | 1979 | 21.3 |
| hidden | 0-200 m | 15206 | 500000 | 1204 | 1964 | 33.8 |
| hidden | 200-400 m | 27808 | 500000 | 1184 | 1959 | 28.9 |
| hidden | 400-800 m | 48499 | 495000 | 1230 | 1957 | 20.9 |
| known | over 800 m | 75952 | 445000 | 1388 | 1973 | 19.8 |
| known | 0-200 m | 15351 | 480000 | 1157 | 1966 | 39.0 |
| known | 200-400 m | 23505 | 499900 | 1170 | 1956 | 28.9 |
| known | 400-800 m | 38853 | 465500 | 1156 | 1955 | 22.5 |
| pre1960 | over 800 m | 92491 | 435000 | 1331 | 1974 | 19.7 |
| pre1960 | 0-200 m | 12224 | 500000 | 1139 | 1964 | 53.1 |
| pre1960 | 200-400 m | 18634 | 506516 | 1135 | 1948 | 31.7 |
| pre1960 | 400-800 m | 30312 | 521000 | 1205 | 1948 | 19.5 |
