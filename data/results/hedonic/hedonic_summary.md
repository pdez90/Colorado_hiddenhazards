# Hedonic model: Denver residential sales and historical hazardous sites

153,661 arm's-length residential sales, 2015-2026. Effects are percentage differences in sale price (95% CI) relative to sales more than 800 m from any site of that kind.

## Models

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 0.17 | -2.49 | 2.90 | 0.9010 | 0.0017 | 0.0137 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | -0.34 | -2.57 | 1.94 | 0.7670 | -0.0034 | 0.0116 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | 0.52 | -1.37 | 2.45 | 0.5910 | 0.0052 | 0.0097 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -2.60 | -5.65 | 0.54 | 0.1060 | -0.0264 | 0.0162 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -1.08 | -3.21 | 1.10 | 0.3320 | -0.0108 | 0.0111 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -1.42 | -3.39 | 0.59 | 0.1670 | -0.0143 | 0.0103 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 0.59 | -2.74 | 4.04 | 0.7310 | 0.0059 | 0.0172 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.83 | -0.61 | 4.33 | 0.1460 | 0.0181 | 0.0124 | 153599 |
| M1 base: neighbourhood x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.59 | -1.56 | 2.79 | 0.5950 | 0.0059 | 0.0110 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 0-200 m | 0.25 | -2.40 | 2.97 | 0.8570 | 0.0025 | 0.0137 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 200-400 m | -0.35 | -2.58 | 1.94 | 0.7650 | -0.0035 | 0.0116 | 153599 |
| M2 + present-day hazards | All residential sales | Hidden (no current inventory) | 400-800 m | 0.47 | -1.41 | 2.39 | 0.6250 | 0.0047 | 0.0096 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 0-200 m | -2.52 | -5.62 | 0.68 | 0.1240 | -0.0255 | 0.0165 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 200-400 m | -1.09 | -3.17 | 1.04 | 0.3160 | -0.0109 | 0.0109 | 153599 |
| M2 + present-day hazards | All residential sales | Known (on a current inventory) | 400-800 m | -1.40 | -3.33 | 0.57 | 0.1650 | -0.0141 | 0.0101 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 0-200 m | 0.66 | -2.69 | 4.12 | 0.7050 | 0.0065 | 0.0173 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 200-400 m | 1.74 | -0.68 | 4.22 | 0.1620 | 0.0173 | 0.0123 | 153599 |
| M2 + present-day hazards | All residential sales | Pre-1960 hazardous trade | 400-800 m | 0.51 | -1.56 | 2.63 | 0.6310 | 0.0051 | 0.0106 | 153599 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 0-200 m | 0.61 | -2.44 | 3.75 | 0.7000 | 0.0061 | 0.0157 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 200-400 m | 0.31 | -2.46 | 3.15 | 0.8300 | 0.0031 | 0.0142 | 153622 |
| M3 tract x year FE | All residential sales | Hidden (no current inventory) | 400-800 m | 1.38 | -0.98 | 3.80 | 0.2570 | 0.0137 | 0.0120 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 0-200 m | -1.64 | -5.63 | 2.51 | 0.4330 | -0.0166 | 0.0211 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 200-400 m | -1.04 | -3.97 | 1.99 | 0.4980 | -0.0104 | 0.0154 | 153622 |
| M3 tract x year FE | All residential sales | Known (on a current inventory) | 400-800 m | -2.20 | -4.16 | -0.19 | 0.0335 | -0.0222 | 0.0103 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 0-200 m | 4.49 | -1.51 | 10.85 | 0.1470 | 0.0439 | 0.0302 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 200-400 m | 2.75 | -1.48 | 7.16 | 0.2080 | 0.0271 | 0.0214 | 153622 |
| M3 tract x year FE | All residential sales | Pre-1960 hazardous trade | 400-800 m | 2.27 | -1.13 | 5.78 | 0.1950 | 0.0224 | 0.0172 | 153622 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 0-200 m | -0.99 | -2.70 | 0.75 | 0.2660 | -0.0099 | 0.0089 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 200-400 m | -0.93 | -2.33 | 0.50 | 0.2040 | -0.0093 | 0.0073 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Hidden (no current inventory) | 400-800 m | -0.47 | -1.53 | 0.60 | 0.3910 | -0.0047 | 0.0055 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 0-200 m | -1.41 | -3.38 | 0.61 | 0.1710 | -0.0142 | 0.0103 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 200-400 m | -0.91 | -2.73 | 0.93 | 0.3320 | -0.0092 | 0.0094 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Known (on a current inventory) | 400-800 m | -0.35 | -1.72 | 1.04 | 0.6200 | -0.0035 | 0.0071 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 0-200 m | 0.64 | -2.48 | 3.85 | 0.6930 | 0.0063 | 0.0160 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 200-400 m | 0.90 | -1.17 | 3.01 | 0.3980 | 0.0090 | 0.0106 | 90217 |
| M4 single-family homes (as M2) | Single-family homes | Pre-1960 hazardous trade | 400-800 m | 0.55 | -0.94 | 2.07 | 0.4710 | 0.0055 | 0.0076 | 90217 |
| M5 site counts within 400 m | All residential sales | Hidden (no current inventory) | per site within 400 m | 0.02 | -0.76 | 0.81 | 0.9550 | 0.0002 | 0.0040 | 153599 |
| M5 site counts within 400 m | All residential sales | Known (on a current inventory) | per site within 400 m | -0.37 | -0.94 | 0.21 | 0.2150 | -0.0037 | 0.0030 | 153599 |
| M5 site counts within 400 m | All residential sales | Pre-1960 hazardous trade | per site within 400 m | -0.02 | -0.61 | 0.58 | 0.9600 | -0.0002 | 0.0031 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden (no current inventory) | 0-400 m | -0.64 | -1.91 | 0.64 | 0.3260 | -0.0064 | 0.0065 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Known (on a current inventory) | 0-400 m | -0.20 | -1.51 | 1.11 | 0.7610 | -0.0020 | 0.0067 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Pre-1960 hazardous trade | 0-400 m | 1.04 | -0.43 | 2.53 | 0.1700 | 0.0103 | 0.0075 | 153599 |
| M6 within 400 m (pooled) | All residential sales | Hidden minus known | 0-400 m | -0.44 | -2.11 | 1.26 | 0.6110 | -0.0044 | 0.0086 | 153599 |

## Present-day controls (M2)

| model | sample | kind | distance | pct | lo | hi | p | estimate | se | n |
|---|---|---|---|---|---|---|---|---|---|---|
| M2 + present-day hazards | All residential sales | Present-day control | petro_100 | 0.74 | -1.13 | 2.64 | 0.44100 | 0.0074 | 0.0095 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | tri_500 | -2.33 | -7.33 | 2.93 | 0.38000 | -0.0236 | 0.0268 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | superfund | 2.87 | -13.33 | 22.10 | 0.74700 | 0.0283 | 0.0874 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | freeway_250 | -4.27 | -7.22 | -1.23 | 0.00699 | -0.0436 | 0.0160 | 153599 |
| M2 + present-day hazards | All residential sales | Present-day control | zoned_ind | -3.38 | -7.10 | 0.49 | 0.08780 | -0.0344 | 0.0200 | 153599 |

## Sales by distance band

| kind | distance | sales | median_price | median_area | median_year_built | pct_condo |
|---|---|---|---|---|---|---|
| hidden | over 800 m | 62112 | 420000 | 1364.0 | 1979 | 21.3 |
| hidden | 0-200 m | 15206 | 500000 | 1204.0 | 1964 | 33.8 |
| hidden | 200-400 m | 27816 | 500000 | 1184.0 | 1959 | 28.9 |
| hidden | 400-800 m | 48527 | 495000 | 1229.0 | 1957 | 20.9 |
| known | over 800 m | 75952 | 445000 | 1388.0 | 1973 | 19.8 |
| known | 0-200 m | 15342 | 480000 | 1158.5 | 1966 | 39.0 |
| known | 200-400 m | 23514 | 499900 | 1170.0 | 1956 | 28.9 |
| known | 400-800 m | 38853 | 465500 | 1156.0 | 1955 | 22.5 |
| pre1960 | over 800 m | 111022 | 439672 | 1297.0 | 1971 | 21.0 |
| pre1960 | 0-200 m | 7736 | 522500 | 1171.5 | 1981 | 58.3 |
| pre1960 | 200-400 m | 11788 | 535000 | 1177.0 | 1951 | 31.0 |
| pre1960 | 400-800 m | 23115 | 525000 | 1197.0 | 1947 | 22.1 |
