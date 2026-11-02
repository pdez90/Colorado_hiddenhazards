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
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Hazardous trades to 1940, kernel (per SD) | -0.043 | -0.19 to 0.11 | 5.72e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Hazardous trades to 1940, kernel (per SD) | 0.008 | -0.13 to 0.14 | 9.06e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Hazardous trades to 1940, kernel (per SD) | 0.111 | -0.56 to 0.78 | 7.47e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Hazardous trade within 500 m | -0.205 | -0.49 to 0.08 | 1.60e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Hazardous trade within 500 m | -0.074 | -0.37 to 0.22 | 6.18e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Hazardous trade within 500 m | -0.069 | -0.62 to 0.48 | 8.06e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Industrial land within 250 m, 1937 (per 10 points) | -0.058 | -0.14 to 0.03 | 1.69e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Industrial land within 250 m, 1937 (per 10 points) | -0.008 | -0.10 to 0.08 | 8.69e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Industrial land within 250 m, 1937 (per 10 points) | 0.069 | -0.13 to 0.26 | 4.89e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Placebo: commercial land within 250 m, 1937 (per 10 points) | -0.022 | -0.06 to 0.02 | 2.92e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Placebo: commercial land within 250 m, 1937 (per 10 points) | 0.004 | -0.04 to 0.04 | 8.50e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Placebo: commercial land within 250 m, 1937 (per 10 points) | -0.017 | -0.13 to 0.09 | 7.58e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | 1929 industrial district | -0.065 | -0.48 to 0.35 | 7.60e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | 1929 industrial district | 0.095 | -0.33 to 0.52 | 6.58e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.132 | -0.23 to -0.03 | 8.24e-03 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.056 | -0.16 to 0.05 | 2.87e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.175 | -0.72 to 0.37 | 5.30e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.094 | -0.19 to 0.00 | 5.90e-02 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Later (1965-92) manufacturers on an inventory, kernel (per SD) | 0.016 | -0.10 to 0.13 | 7.97e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Later (1965-92) manufacturers on an inventory, kernel (per SD) | 0.306 | -0.16 to 0.77 | 1.97e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | HOLC grade D (vs A/B) | -0.460 | -0.75 to -0.17 | 1.69e-03 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | HOLC grade D (vs A/B) | -0.227 | -0.60 to 0.15 | 2.33e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2 joint | Hazardous trades kernel, with industrial and commercial land | 0.007 | -0.14 to 0.16 | 9.24e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2 joint | Industrial land, with hazardous trades and commercial land | -0.008 | -0.10 to 0.08 | 8.58e-01 | 13376 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Hazardous trades to 1940, kernel (per SD) | 0.003 | -0.27 to 0.28 | 9.81e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Hazardous trades to 1940, kernel (per SD) | 0.181 | -0.08 to 0.45 | 1.78e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Hazardous trades to 1940, kernel (per SD) | -0.053 | -0.78 to 0.67 | 8.87e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Hazardous trade within 500 m | -0.862 | -1.41 to -0.32 | 1.96e-03 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Hazardous trade within 500 m | -0.391 | -0.92 to 0.14 | 1.51e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Hazardous trade within 500 m | -0.326 | -1.15 to 0.49 | 4.36e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Industrial land within 250 m, 1937 (per 10 points) | -0.376 | -0.54 to -0.21 | 6.32e-06 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Industrial land within 250 m, 1937 (per 10 points) | -0.234 | -0.39 to -0.08 | 2.73e-03 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Industrial land within 250 m, 1937 (per 10 points) | -0.093 | -0.33 to 0.14 | 4.38e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Placebo: commercial land within 250 m, 1937 (per 10 points) | -0.008 | -0.11 to 0.09 | 8.82e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Placebo: commercial land within 250 m, 1937 (per 10 points) | 0.082 | -0.02 to 0.19 | 1.30e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Placebo: commercial land within 250 m, 1937 (per 10 points) | 0.022 | -0.22 to 0.26 | 8.60e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | 1929 industrial district | -1.289 | -2.14 to -0.43 | 3.15e-03 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | 1929 industrial district | -0.718 | -1.56 to 0.12 | 9.38e-02 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.277 | -0.64 to 0.08 | 1.30e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | 0.000 | -0.38 to 0.38 | 9.99e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.114 | -1.33 to 1.10 | 8.54e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.466 | -0.80 to -0.13 | 6.69e-03 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.175 | -0.57 to 0.23 | 3.93e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.189 | -0.96 to 0.58 | 6.31e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | HOLC grade D (vs A/B) | -1.294 | -2.01 to -0.58 | 4.08e-04 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | HOLC grade D (vs A/B) | -0.302 | -1.26 to 0.65 | 5.36e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2 joint | Hazardous trades kernel, with industrial and commercial land | 0.206 | -0.08 to 0.50 | 1.64e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2 joint | Industrial land, with hazardous trades and commercial land | -0.259 | -0.41 to -0.11 | 5.58e-04 | 8390 |

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
| DMF (men, deaths 1975 on) | Hazardous trades to 1940 | hazardous trade within 500 m | 1637 | 80.15 |
| DMF (men, deaths 1975 on) | Hazardous trades to 1940 | none within 500 m | 6753 | 80.99 |
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
| Numident (men and women, deaths 1988-2005) | Hazardous trades to 1940 | hazardous trade within 500 m | 2493 | 81.76 |
| Numident (men and women, deaths 1988-2005) | Hazardous trades to 1940 | none within 500 m | 10883 | 81.97 |
| Numident (men and women, deaths 1988-2005) | Industrial land 1937 | 10%+ industrial within 250 m | 1228 | 81.64 |
| Numident (men and women, deaths 1988-2005) | Industrial land 1937 | under 10% | 12148 | 81.96 |
