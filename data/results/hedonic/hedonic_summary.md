# Hedonic model: Denver residential sales and historical hazardous sites

153,661 arm's-length residential sales, 2015-2026. Effects are percentage differences in sale price (95% CI) relative to sales more than 800 m from any site of that kind.

## Models

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | -0.03 | -2.47 | 2.48 | 0.9830 | -0.0003 | 0.0126 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -0.19 | -2.30 | 1.98 | 0.8660 | -0.0019 | 0.0109 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | 1.01 | -0.79 | 2.85 | 0.2730 | 0.0101 | 0.0092 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -2.65 | -5.60 | 0.40 | 0.0902 | -0.0268 | 0.0157 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -0.99 | -3.14 | 1.22 | 0.3790 | -0.0099 | 0.0112 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -1.41 | -3.33 | 0.56 | 0.1610 | -0.0142 | 0.0101 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 1.19 | -1.94 | 4.42 | 0.4620 | 0.0118 | 0.0160 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.41 | -1.10 | 3.98 | 0.2750 | 0.0140 | 0.0128 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.31 | -2.04 | 2.71 | 0.8010 | 0.0031 | 0.0121 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 0-200 m | -0.01 | -2.46 | 2.50 | 0.9930 | -0.0001 | 0.0127 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 200-400 m | -0.22 | -2.34 | 1.95 | 0.8430 | -0.0022 | 0.0110 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 400-800 m | 0.93 | -0.87 | 2.77 | 0.3140 | 0.0093 | 0.0092 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 0-200 m | -2.53 | -5.57 | 0.61 | 0.1160 | -0.0256 | 0.0162 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 200-400 m | -0.95 | -3.08 | 1.22 | 0.3880 | -0.0096 | 0.0111 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 400-800 m | -1.38 | -3.26 | 0.54 | 0.1610 | -0.0139 | 0.0098 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 0-200 m | 1.24 | -1.95 | 4.53 | 0.4510 | 0.0123 | 0.0163 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.33 | -1.13 | 3.85 | 0.2920 | 0.0132 | 0.0125 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.22 | -2.03 | 2.51 | 0.8510 | 0.0022 | 0.0115 | 153599 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 1.12 | -1.92 | 4.27 | 0.4750 | 0.0112 | 0.0156 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | 0.85 | -1.83 | 3.62 | 0.5380 | 0.0085 | 0.0138 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | 2.00 | -0.29 | 4.33 | 0.0892 | 0.0198 | 0.0116 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -1.79 | -5.69 | 2.27 | 0.3830 | -0.0181 | 0.0207 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -1.23 | -4.22 | 1.86 | 0.4320 | -0.0124 | 0.0157 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -2.09 | -3.91 | -0.22 | 0.0299 | -0.0211 | 0.0096 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 4.35 | -1.43 | 10.48 | 0.1450 | 0.0426 | 0.0291 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 2.06 | -2.17 | 6.47 | 0.3480 | 0.0203 | 0.0216 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 1.91 | -1.76 | 5.71 | 0.3140 | 0.0189 | 0.0187 | 153622 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 0-200 m | -0.50 | -2.19 | 1.21 | 0.5660 | -0.0050 | 0.0087 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 200-400 m | -0.41 | -1.81 | 1.00 | 0.5670 | -0.0041 | 0.0072 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 400-800 m | 0.12 | -0.99 | 1.25 | 0.8340 | 0.0012 | 0.0057 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 0-200 m | -1.66 | -3.58 | 0.30 | 0.0993 | -0.0167 | 0.0101 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 200-400 m | -1.06 | -2.79 | 0.70 | 0.2370 | -0.0107 | 0.0090 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 400-800 m | -0.48 | -1.76 | 0.82 | 0.4660 | -0.0048 | 0.0066 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 0-200 m | 0.74 | -2.23 | 3.79 | 0.6310 | 0.0073 | 0.0153 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 200-400 m | 0.92 | -1.11 | 3.00 | 0.3770 | 0.0092 | 0.0104 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 400-800 m | 0.50 | -1.01 | 2.04 | 0.5190 | 0.0050 | 0.0077 | 90217 |
| M5 site counts within 400 m | All residential sales | Hidden (no current inventory) | per site within 400 m | -0.10 | -0.88 | 0.70 | 0.8130 | -0.0010 | 0.0040 | 153599 |
| M5 site counts within 400 m | All residential sales | Known (on a current inventory) | per site within 400 m | -0.37 | -0.82 | 0.09 | 0.1130 | -0.0037 | 0.0023 | 153599 |
| M5 site counts within 400 m | All residential sales | Pre-1960 hazardous trade | per site within 400 m | -0.01 | -0.52 | 0.50 | 0.9610 | -0.0001 | 0.0026 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden (no current inventory) | 0-400 m | -0.99 | -2.25 | 0.28 | 0.1290 | -0.0100 | 0.0065 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Known (on a current inventory) | 0-400 m | -0.10 | -1.50 | 1.32 | 0.8890 | -0.0010 | 0.0072 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Pre-1960 hazardous trade | 0-400 m | 1.13 | -0.14 | 2.40 | 0.0829 | 0.0112 | 0.0064 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden minus known | 0-400 m | -0.89 | -2.51 | 0.76 | 0.2870 | -0.0090 | 0.0084 | 153599 |

## Present-day controls (M2)

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M2 + present-day hazards | All residential sales | Present-day control | petro_100 | 0.74 | -1.12 | 2.63 | 0.44000 | 0.0073 | 0.0095 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | tri_500 | -2.43 | -7.47 | 2.89 | 0.36600 | -0.0246 | 0.0271 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | superfund | 2.72 | -13.31 | 21.73 | 0.75700 | 0.0269 | 0.0866 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | freeway_250 | -4.20 | -7.15 | -1.17 | 0.00775 | -0.0429 | 0.0159 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | zoned_ind | -1.17 | -6.44 | 4.40 | 0.67500 | -0.0118 | 0.0280 | 153599 |

## Sales by distance band

| kind | distance | sales | median_price | median_area | median_year_built | pct_condo |
|---|---|---|---|---|---|---|
| hidden | over 800 m | 60372 | 415000.0 | 1353.0 | 1980 | 22.2 |
| hidden | 0-200 m | 15259 | 499000.0 | 1205.0 | 1961 | 32.5 |
| hidden | 200-400 m | 28018 | 500000.0 | 1201.0 | 1958 | 26.9 |
| hidden | 400-800 m | 50012 | 500000.0 | 1232.0 | 1956 | 21.3 |
| known | over 800 m | 76559 | 445000.0 | 1381.0 | 1973 | 20.0 |
| known | 0-200 m | 15272 | 480200.0 | 1162.0 | 1964 | 39.5 |
| known | 200-400 m | 23564 | 497000.0 | 1161.0 | 1956 | 29.7 |
| known | 400-800 m | 38266 | 470000.0 | 1165.0 | 1955 | 21.5 |
| pre1960 | over 800 m | 107436 | 436748.5 | 1300.5 | 1972 | 20.5 |
| pre1960 | 0-200 m | 9092 | 519000.0 | 1160.0 | 1980 | 57.1 |
| pre1960 | 200-400 m | 13270 | 530250.0 | 1170.0 | 1949 | 31.0 |
| pre1960 | 400-800 m | 23863 | 526500.0 | 1188.0 | 1947 | 22.0 |
