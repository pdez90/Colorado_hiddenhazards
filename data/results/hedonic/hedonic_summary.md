# Hedonic model: Denver residential sales and historical hazardous sites

153,713 arm's-length residential sales, 2015-2026. Effects are percentage differences in sale price (95% CI) relative to sales more than 800 m from any site of that kind.

## Models

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | -1.26 | -4.51 | 2.11 | 0.4610 | -0.0126 | 0.0171 | 153651 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -2.63 | -5.45 | 0.27 | 0.0766 | -0.0267 | 0.0150 | 153651 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | -0.87 | -3.22 | 1.53 | 0.4740 | -0.0088 | 0.0122 | 153651 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -0.18 | -3.32 | 3.06 | 0.9120 | -0.0018 | 0.0163 | 153651 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 200-400 m | 0.96 | -1.28 | 3.25 | 0.4050 | 0.0096 | 0.0115 | 153651 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -0.49 | -2.22 | 1.26 | 0.5810 | -0.0049 | 0.0089 | 153651 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 0.58 | -2.35 | 3.61 | 0.7000 | 0.0058 | 0.0151 | 153651 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.20 | -1.16 | 3.62 | 0.3220 | 0.0120 | 0.0120 | 153651 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.12 | -2.11 | 2.41 | 0.9160 | 0.0012 | 0.0115 | 153651 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 0-200 m | -1.16 | -4.42 | 2.21 | 0.4980 | -0.0116 | 0.0171 | 153651 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 200-400 m | -2.55 | -5.36 | 0.35 | 0.0860 | -0.0258 | 0.0149 | 153651 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 400-800 m | -0.82 | -3.11 | 1.54 | 0.4940 | -0.0082 | 0.0120 | 153651 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 0-200 m | -0.07 | -3.34 | 3.32 | 0.9690 | -0.0007 | 0.0170 | 153651 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 200-400 m | 0.92 | -1.34 | 3.23 | 0.4300 | 0.0092 | 0.0116 | 153651 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 400-800 m | -0.51 | -2.21 | 1.23 | 0.5660 | -0.0051 | 0.0088 | 153651 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 0-200 m | 0.65 | -2.33 | 3.72 | 0.6750 | 0.0064 | 0.0153 | 153651 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.14 | -1.16 | 3.49 | 0.3360 | 0.0113 | 0.0117 | 153651 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.04 | -2.10 | 2.22 | 0.9710 | 0.0004 | 0.0110 | 153651 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | -0.51 | -4.30 | 3.44 | 0.7980 | -0.0051 | 0.0199 | 153682 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -2.03 | -5.21 | 1.26 | 0.2260 | -0.0205 | 0.0168 | 153682 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | -0.06 | -2.51 | 2.45 | 0.9620 | -0.0006 | 0.0127 | 153682 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 0-200 m | 1.52 | -3.35 | 6.63 | 0.5490 | 0.0151 | 0.0251 | 153682 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 200-400 m | 1.47 | -2.85 | 5.97 | 0.5120 | 0.0146 | 0.0222 | 153682 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -0.96 | -3.13 | 1.25 | 0.3910 | -0.0097 | 0.0113 | 153682 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 3.40 | -1.90 | 8.99 | 0.2150 | 0.0334 | 0.0269 | 153682 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.58 | -2.29 | 5.60 | 0.4310 | 0.0156 | 0.0198 | 153682 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 1.56 | -1.79 | 5.03 | 0.3660 | 0.0155 | 0.0171 | 153682 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 0-200 m | -0.84 | -2.72 | 1.08 | 0.3900 | -0.0084 | 0.0098 | 90241 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 200-400 m | -1.10 | -2.68 | 0.52 | 0.1840 | -0.0110 | 0.0083 | 90241 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 400-800 m | -0.72 | -1.83 | 0.41 | 0.2130 | -0.0072 | 0.0058 | 90241 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 0-200 m | -0.50 | -2.59 | 1.63 | 0.6430 | -0.0050 | 0.0108 | 90241 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 200-400 m | -0.60 | -2.41 | 1.25 | 0.5250 | -0.0060 | 0.0094 | 90241 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 400-800 m | -0.24 | -1.67 | 1.21 | 0.7450 | -0.0024 | 0.0074 | 90241 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 0-200 m | 0.43 | -2.57 | 3.51 | 0.7820 | 0.0043 | 0.0154 | 90241 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 200-400 m | 0.81 | -1.24 | 2.89 | 0.4440 | 0.0080 | 0.0105 | 90241 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 400-800 m | 0.37 | -1.15 | 1.91 | 0.6370 | 0.0037 | 0.0078 | 90241 |
| M5 site counts within 400 m | All residential sales | Hidden (no current inventory) | per site within 400 m | -0.48 | -1.51 | 0.55 | 0.3620 | -0.0048 | 0.0053 | 153651 |
| M5 site counts within 400 m | All residential sales | Known (on a current inventory) | per site within 400 m | -0.03 | -0.42 | 0.36 | 0.8630 | -0.0003 | 0.0020 | 153651 |
| M5 site counts within 400 m | All residential sales | Pre-1960 hazardous trade | per site within 400 m | -0.07 | -0.63 | 0.49 | 0.7950 | -0.0007 | 0.0029 | 153651 |
| M6 within 400 m (pooled) | All residential sales | Hidden (no current inventory) | 0-400 m | -1.67 | -3.33 | 0.02 | 0.0540 | -0.0169 | 0.0087 | 153651 |
| M6 within 400 m (pooled) | All residential sales | Known (on a current inventory) | 0-400 m | 1.04 | -0.57 | 2.68 | 0.2090 | 0.0104 | 0.0082 | 153651 |
| M6 within 400 m (pooled) | All residential sales | Pre-1960 hazardous trade | 0-400 m | 0.92 | -0.32 | 2.17 | 0.1490 | 0.0091 | 0.0063 | 153651 |
| M6 within 400 m (pooled) | All residential sales | Hidden minus known | 0-400 m | -2.69 | -4.95 | -0.37 | 0.0232 | -0.0272 | 0.0120 | 153651 |

## Present-day controls (M2)

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M2 + present-day hazards | All residential sales | Present-day control | petro_100 | 0.66 | -1.20 | 2.56 | 0.49100 | 0.0066 | 0.0095 | 153651 |
| M2 + present-day hazards | All residential sales | Present-day control | tri_500 | -2.48 | -7.44 | 2.75 | 0.34700 | -0.0251 | 0.0266 | 153651 |
| M2 + present-day hazards | All residential sales | Present-day control | superfund | 2.61 | -13.51 | 21.74 | 0.76800 | 0.0258 | 0.0872 | 153651 |
| M2 + present-day hazards | All residential sales | Present-day control | freeway_250 | -4.15 | -7.06 | -1.15 | 0.00787 | -0.0424 | 0.0157 | 153651 |
| M2 + present-day hazards | All residential sales | Present-day control | zoned_ind | -1.50 | -6.81 | 4.12 | 0.59400 | -0.0151 | 0.0283 | 153651 |

## Sales by distance band

| kind | distance | sales | median_price | median_area | median_year_built | pct_condo |
|---|---|---|---|---|---|---|
| hidden | over 800 m | 77593 | 445000 | 1378.0 | 1979 | 21.6 |
| hidden | 0-200 m | 10206 | 485300 | 1204.5 | 1961 | 35.6 |
| hidden | 200-400 m | 21307 | 470000 | 1142.0 | 1959 | 30.3 |
| hidden | 400-800 m | 44607 | 484999 | 1200.0 | 1955 | 21.9 |
| known | over 800 m | 83675 | 445000 | 1355.0 | 1972 | 22.0 |
| known | 0-200 m | 13325 | 485000 | 1173.0 | 1967 | 39.7 |
| known | 200-400 m | 19703 | 508000 | 1169.0 | 1955 | 25.3 |
| known | 400-800 m | 37010 | 467500 | 1172.0 | 1955 | 21.2 |
| pre1960 | over 800 m | 107028 | 436800 | 1302.0 | 1972 | 20.6 |
| pre1960 | 0-200 m | 9426 | 511000 | 1143.0 | 1979 | 57.9 |
| pre1960 | 200-400 m | 14012 | 520000 | 1151.0 | 1952 | 33.5 |
| pre1960 | 400-800 m | 23247 | 535600 | 1211.0 | 1946 | 19.0 |
