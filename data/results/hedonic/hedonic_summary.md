# Hedonic model: Denver residential sales and historical hazardous sites

153,693 arm's-length residential sales, 2015-2026. Effects are percentage differences in sale price (95% CI) relative to sales more than 800 m from any site of that kind.

## Models

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | -0.16 | -3.19 | 2.96 | 0.9170 | -0.0016 | 0.0157 | 153631 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -1.32 | -3.63 | 1.05 | 0.2740 | -0.0133 | 0.0121 | 153631 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | -0.65 | -2.76 | 1.50 | 0.5510 | -0.0065 | 0.0109 | 153631 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -0.37 | -4.39 | 3.83 | 0.8610 | -0.0037 | 0.0210 | 153631 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -1.47 | -4.76 | 1.94 | 0.3950 | -0.0148 | 0.0173 | 153631 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -0.41 | -2.48 | 1.71 | 0.7040 | -0.0041 | 0.0107 | 153631 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | -1.75 | -4.55 | 1.13 | 0.2340 | -0.0177 | 0.0148 | 153631 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | -0.85 | -3.01 | 1.36 | 0.4480 | -0.0086 | 0.0112 | 153631 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | -0.85 | -2.62 | 0.95 | 0.3520 | -0.0086 | 0.0092 | 153631 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 0-200 m | 0.19 | -2.84 | 3.32 | 0.9040 | 0.0019 | 0.0157 | 153631 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 200-400 m | -1.21 | -3.52 | 1.15 | 0.3140 | -0.0122 | 0.0121 | 153631 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 400-800 m | -0.59 | -2.68 | 1.55 | 0.5860 | -0.0059 | 0.0109 | 153631 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 0-200 m | -0.31 | -4.27 | 3.82 | 0.8820 | -0.0031 | 0.0207 | 153631 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 200-400 m | -1.52 | -4.70 | 1.76 | 0.3600 | -0.0154 | 0.0167 | 153631 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 400-800 m | -0.41 | -2.47 | 1.70 | 0.7020 | -0.0041 | 0.0107 | 153631 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 0-200 m | -1.79 | -4.58 | 1.07 | 0.2190 | -0.0181 | 0.0147 | 153631 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 200-400 m | -0.90 | -3.03 | 1.28 | 0.4150 | -0.0091 | 0.0111 | 153631 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 400-800 m | -0.90 | -2.64 | 0.87 | 0.3190 | -0.0090 | 0.0090 | 153631 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 1.11 | -2.76 | 5.14 | 0.5800 | 0.0111 | 0.0199 | 153654 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -0.40 | -3.89 | 3.22 | 0.8270 | -0.0040 | 0.0182 | 153654 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | -0.29 | -2.67 | 2.15 | 0.8150 | -0.0029 | 0.0123 | 153654 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -0.88 | -4.91 | 3.33 | 0.6790 | -0.0088 | 0.0212 | 153654 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -2.83 | -5.89 | 0.32 | 0.0800 | -0.0287 | 0.0163 | 153654 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -1.44 | -3.46 | 0.63 | 0.1730 | -0.0145 | 0.0106 | 153654 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 1.23 | -3.17 | 5.82 | 0.5910 | 0.0122 | 0.0226 | 153654 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.48 | -1.44 | 4.49 | 0.3250 | 0.0147 | 0.0149 | 153654 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.94 | -1.13 | 3.06 | 0.3780 | 0.0094 | 0.0106 | 153654 |
| M2 + present-day hazards | Single-family homes | Hidden (no current inventory) | 0-200 m | 0.46 | -1.35 | 2.31 | 0.6200 | 0.0046 | 0.0093 | 90213 |
| M2 + present-day hazards | Single-family homes | Hidden (no current inventory) | 200-400 m | -0.20 | -1.67 | 1.28 | 0.7880 | -0.0020 | 0.0075 | 90213 |
| M2 + present-day hazards | Single-family homes | Hidden (no current inventory) | 400-800 m | -0.17 | -1.16 | 0.83 | 0.7350 | -0.0017 | 0.0051 | 90213 |
| M2 + present-day hazards | Single-family homes | Known (on a current inventory) | 0-200 m | -2.16 | -4.18 | -0.10 | 0.0415 | -0.0218 | 0.0106 | 90213 |
| M2 + present-day hazards | Single-family homes | Known (on a current inventory) | 200-400 m | -1.60 | -3.50 | 0.33 | 0.1050 | -0.0162 | 0.0099 | 90213 |
| M2 + present-day hazards | Single-family homes | Known (on a current inventory) | 400-800 m | -1.33 | -2.68 | 0.04 | 0.0592 | -0.0134 | 0.0070 | 90213 |
| M2 + present-day hazards | Single-family homes | Pre-1960 hazardous trade | 0-200 m | -0.20 | -2.56 | 2.23 | 0.8720 | -0.0020 | 0.0122 | 90213 |
| M2 + present-day hazards | Single-family homes | Pre-1960 hazardous trade | 200-400 m | -0.05 | -1.92 | 1.86 | 0.9610 | -0.0005 | 0.0097 | 90213 |
| M2 + present-day hazards | Single-family homes | Pre-1960 hazardous trade | 400-800 m | 0.19 | -1.14 | 1.53 | 0.7830 | 0.0019 | 0.0068 | 90213 |
| M5 site counts within 400 m | All residential sales | Hidden (no current inventory) | per site within 400 m | 0.30 | -0.66 | 1.26 | 0.5480 | 0.0030 | 0.0049 | 153631 |
| M5 site counts within 400 m | All residential sales | Known (on a current inventory) | per site within 400 m | -0.46 | -1.22 | 0.31 | 0.2390 | -0.0046 | 0.0039 | 153631 |
| M5 site counts within 400 m | All residential sales | Pre-1960 hazardous trade | per site within 400 m | 0.00 | -0.50 | 0.50 | 0.9980 | 0.0000 | 0.0026 | 153631 |
| M6 within 400 m (pooled) | All residential sales | Hidden (no current inventory) | 0-400 m | -0.45 | -1.94 | 1.07 | 0.5610 | -0.0045 | 0.0077 | 153631 |
| M6 within 400 m (pooled) | All residential sales | Known (on a current inventory) | 0-400 m | -0.97 | -3.01 | 1.11 | 0.3590 | -0.0098 | 0.0106 | 153631 |
| M6 within 400 m (pooled) | All residential sales | Pre-1960 hazardous trade | 0-400 m | -0.34 | -1.82 | 1.16 | 0.6560 | -0.0034 | 0.0076 | 153631 |
| M6 within 400 m (pooled) | All residential sales | Hidden minus known | 0-400 m | 0.53 | -2.47 | 3.52 | 0.7310 | 0.0053 | 0.0153 | 153631 |

## Present-day controls (M2)

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M2 + present-day hazards | All residential sales | Present-day control | petro_100 | 0.58 | -1.22 | 2.42 | 0.52800 | 0.0058 | 0.0092 | 153631 |
| M2 + present-day hazards | All residential sales | Present-day control | tri_500 | -2.44 | -7.33 | 2.70 | 0.34700 | -0.0247 | 0.0262 | 153631 |
| M2 + present-day hazards | All residential sales | Present-day control | superfund | 2.89 | -13.22 | 22.00 | 0.74300 | 0.0285 | 0.0869 | 153631 |
| M2 + present-day hazards | All residential sales | Present-day control | freeway_250 | -4.51 | -7.33 | -1.60 | 0.00301 | -0.0462 | 0.0153 | 153631 |
| M2 + present-day hazards | All residential sales | Present-day control | zoned_ind | -4.35 | -8.15 | -0.39 | 0.03320 | -0.0444 | 0.0207 | 153631 |

## Sales by distance band

| kind | distance | sales | median_price | median_area | median_year_built | pct_condo |
|---|---|---|---|---|---|---|
| hidden | over 800 m | 77588 | 435000 | 1338 | 1974 | 22.3 |
| hidden | 0-200 m | 11084 | 500000 | 1204 | 1959 | 34.0 |
| hidden | 200-400 m | 22305 | 490000 | 1180 | 1961 | 31.8 |
| hidden | 400-800 m | 42716 | 490000 | 1216 | 1956 | 19.7 |
| known | over 800 m | 71336 | 444900 | 1405 | 1976 | 21.7 |
| known | 0-200 m | 16314 | 490000 | 1173 | 1958 | 36.0 |
| known | 200-400 m | 24900 | 490000 | 1154 | 1955 | 26.2 |
| known | 400-800 m | 41143 | 467500 | 1175 | 1954 | 21.2 |
| pre1960 | over 800 m | 89997 | 430000 | 1323 | 1974 | 19.2 |
| pre1960 | 0-200 m | 12265 | 490000 | 1120 | 1962 | 51.9 |
| pre1960 | 200-400 m | 19832 | 511000 | 1154 | 1949 | 32.4 |
| pre1960 | 400-800 m | 31599 | 531250 | 1226 | 1950 | 20.6 |
