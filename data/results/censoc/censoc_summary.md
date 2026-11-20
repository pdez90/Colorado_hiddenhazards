# Denver residents of 1940 and their age at death (CenSoc)

## Linkage

| file | linked | with_address_point | min_dyear | max_dyear | median_death_age | median_age_1940 |
|---|---|---|---|---|---|---|
| 1940 census, Denver residents | 322780 | 243055 |  |  |  |  |
| Numident (men and women, deaths 1988-2005) | 19105 | 14936 | 1988 | 2005 | 77 | 19 |
| DMF (men, deaths 1975 on) | 12610 | 9769 | 1975 | 2020 | 79 | 25 |

## Age at death (years) per unit of exposure at the 1940 address

| file | model | exposure | years | ci | p | n |
|---|---|---|---|---|---|---|
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Hazardous trades to 1940, kernel (per SD) | -0.057 | -0.20 to 0.09 | 4.47e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Hazardous trades to 1940, kernel (per SD) | -0.005 | -0.14 to 0.13 | 9.39e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Hazardous trades to 1940, kernel (per SD) | 0.093 | -0.62 to 0.81 | 7.99e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Hazardous trade within 500 m | -0.143 | -0.37 to 0.08 | 2.11e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Hazardous trade within 500 m | -0.034 | -0.27 to 0.20 | 7.78e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Hazardous trade within 500 m | 0.307 | -0.10 to 0.72 | 1.43e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Industrial land within 250 m, 1937 (per 10 points) | -0.058 | -0.14 to 0.03 | 1.69e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Industrial land within 250 m, 1937 (per 10 points) | -0.009 | -0.10 to 0.08 | 8.39e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Industrial land within 250 m, 1937 (per 10 points) | 0.069 | -0.13 to 0.26 | 4.88e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Placebo: commercial land within 250 m, 1937 (per 10 points) | -0.022 | -0.06 to 0.02 | 2.92e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Placebo: commercial land within 250 m, 1937 (per 10 points) | 0.004 | -0.04 to 0.04 | 8.66e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Placebo: commercial land within 250 m, 1937 (per 10 points) | -0.018 | -0.13 to 0.09 | 7.46e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | 1929 industrial district | -0.065 | -0.48 to 0.35 | 7.60e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | 1929 industrial district | 0.088 | -0.33 to 0.51 | 6.82e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.132 | -0.23 to -0.04 | 5.98e-03 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.059 | -0.16 to 0.04 | 2.67e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | 0.038 | -0.46 to 0.54 | 8.80e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.100 | -0.20 to -0.00 | 4.04e-02 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Later (1965-92) manufacturers on an inventory, kernel (per SD) | 0.004 | -0.11 to 0.12 | 9.43e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Later (1965-92) manufacturers on an inventory, kernel (per SD) | 0.283 | -0.17 to 0.73 | 2.19e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | HOLC grade D (vs A/B) | -0.460 | -0.75 to -0.17 | 1.69e-03 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | HOLC grade D (vs A/B) | -0.262 | -0.64 to 0.11 | 1.69e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2 joint | Hazardous trades kernel, with industrial and commercial land | -0.008 | -0.16 to 0.14 | 9.12e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2 joint | Industrial land, with hazardous trades and commercial land | -0.007 | -0.10 to 0.08 | 8.78e-01 | 13376 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Hazardous trades to 1940, kernel (per SD) | -0.025 | -0.31 to 0.26 | 8.64e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Hazardous trades to 1940, kernel (per SD) | 0.163 | -0.11 to 0.43 | 2.37e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Hazardous trades to 1940, kernel (per SD) | -0.040 | -0.79 to 0.71 | 9.17e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Hazardous trade within 500 m | -0.615 | -1.16 to -0.07 | 2.81e-02 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Hazardous trade within 500 m | -0.207 | -0.75 to 0.34 | 4.53e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Hazardous trade within 500 m | 0.082 | -0.80 to 0.96 | 8.56e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Industrial land within 250 m, 1937 (per 10 points) | -0.376 | -0.54 to -0.21 | 6.32e-06 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Industrial land within 250 m, 1937 (per 10 points) | -0.234 | -0.39 to -0.08 | 2.65e-03 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Industrial land within 250 m, 1937 (per 10 points) | -0.093 | -0.33 to 0.14 | 4.37e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Placebo: commercial land within 250 m, 1937 (per 10 points) | -0.008 | -0.11 to 0.09 | 8.82e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Placebo: commercial land within 250 m, 1937 (per 10 points) | 0.087 | -0.02 to 0.19 | 1.11e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Placebo: commercial land within 250 m, 1937 (per 10 points) | 0.027 | -0.21 to 0.27 | 8.26e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | 1929 industrial district | -1.289 | -2.14 to -0.43 | 3.15e-03 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | 1929 industrial district | -0.720 | -1.56 to 0.12 | 9.18e-02 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.344 | -0.69 to 0.00 | 5.21e-02 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.050 | -0.43 to 0.33 | 7.96e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.135 | -1.24 to 0.97 | 8.11e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.488 | -0.82 to -0.16 | 3.85e-03 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.184 | -0.58 to 0.21 | 3.62e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.235 | -1.02 to 0.55 | 5.59e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | HOLC grade D (vs A/B) | -1.294 | -2.01 to -0.58 | 4.08e-04 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | HOLC grade D (vs A/B) | -0.161 | -1.14 to 0.82 | 7.47e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2 joint | Hazardous trades kernel, with industrial and commercial land | 0.185 | -0.11 to 0.48 | 2.22e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2 joint | Industrial land, with hazardous trades and commercial land | -0.257 | -0.41 to -0.11 | 6.93e-04 | 8390 |

## Mean age at death, net of birth year and sex (groups of 20+)

| file | measure | group | n | adj_mean_age_at_death |
|---|---|---|---|---|
| DMF (men, deaths 1975 on) | 1929 zoning district | commercial | 365 | 80.13 |
| DMF (men, deaths 1975 on) | 1929 zoning district | industrial | 443 | 79.64 |
| DMF (men, deaths 1975 on) | 1929 zoning district | residence | 7582 | 80.93 |
| DMF (men, deaths 1975 on) | 1938 HOLC grade | A | 389 | 82.06 |
| DMF (men, deaths 1975 on) | 1938 HOLC grade | B | 1201 | 81.11 |
| DMF (men, deaths 1975 on) | 1938 HOLC grade | C | 3668 | 81.25 |
| DMF (men, deaths 1975 on) | 1938 HOLC grade | D | 2451 | 80.07 |
| DMF (men, deaths 1975 on) | 1938 HOLC grade | ungraded | 681 | 80.28 |
| DMF (men, deaths 1975 on) | Hazardous trades to 1940 | hazardous trade within 500 m | 2457 | 80.40 |
| DMF (men, deaths 1975 on) | Hazardous trades to 1940 | none within 500 m | 5933 | 81.01 |
| DMF (men, deaths 1975 on) | Industrial land 1937 | 10%+ industrial within 250 m | 805 | 79.52 |
| DMF (men, deaths 1975 on) | Industrial land 1937 | under 10% | 7585 | 80.97 |
| Numident (men and women, deaths 1988-2005) | 1929 zoning district | commercial | 545 | 81.43 |
| Numident (men and women, deaths 1988-2005) | 1929 zoning district | industrial | 766 | 81.87 |
| Numident (men and women, deaths 1988-2005) | 1929 zoning district | residence | 12065 | 81.96 |
| Numident (men and women, deaths 1988-2005) | 1938 HOLC grade | A | 608 | 81.98 |
| Numident (men and women, deaths 1988-2005) | 1938 HOLC grade | B | 2014 | 82.11 |
| Numident (men and women, deaths 1988-2005) | 1938 HOLC grade | C | 5841 | 82.01 |
| Numident (men and women, deaths 1988-2005) | 1938 HOLC grade | D | 3976 | 81.63 |
| Numident (men and women, deaths 1988-2005) | 1938 HOLC grade | ungraded | 937 | 82.14 |
| Numident (men and women, deaths 1988-2005) | Hazardous trades to 1940 | hazardous trade within 500 m | 3717 | 81.83 |
| Numident (men and women, deaths 1988-2005) | Hazardous trades to 1940 | none within 500 m | 9659 | 81.97 |
| Numident (men and women, deaths 1988-2005) | Industrial land 1937 | 10%+ industrial within 250 m | 1228 | 81.64 |
| Numident (men and women, deaths 1988-2005) | Industrial land 1937 | under 10% | 12148 | 81.96 |
