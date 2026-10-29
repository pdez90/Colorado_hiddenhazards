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
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Hazardous trades to 1940, kernel (per SD) | -0.080 | -0.21 to 0.05 | 2.22e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Hazardous trades to 1940, kernel (per SD) | -0.018 | -0.14 to 0.10 | 7.69e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Hazardous trades to 1940, kernel (per SD) | -0.044 | -0.76 to 0.67 | 9.04e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Hazardous trade within 500 m | -0.187 | -0.40 to 0.03 | 8.65e-02 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Hazardous trade within 500 m | -0.047 | -0.26 to 0.17 | 6.67e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Hazardous trade within 500 m | 0.128 | -0.28 to 0.54 | 5.43e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Industrial land within 250 m, 1937 (per 10 points) | -0.058 | -0.14 to 0.03 | 1.69e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Industrial land within 250 m, 1937 (per 10 points) | -0.008 | -0.10 to 0.08 | 8.69e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Industrial land within 250 m, 1937 (per 10 points) | 0.069 | -0.13 to 0.26 | 4.89e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Placebo: commercial land within 250 m, 1937 (per 10 points) | -0.022 | -0.06 to 0.02 | 2.92e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Placebo: commercial land within 250 m, 1937 (per 10 points) | 0.004 | -0.04 to 0.04 | 8.50e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Placebo: commercial land within 250 m, 1937 (per 10 points) | -0.017 | -0.13 to 0.09 | 7.58e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | 1929 industrial district | -0.071 | -0.55 to 0.41 | 7.71e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | 1929 industrial district | 0.101 | -0.39 to 0.59 | 6.88e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.127 | -0.23 to -0.03 | 1.18e-02 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.058 | -0.16 to 0.04 | 2.67e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.067 | -0.68 to 0.55 | 8.30e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.106 | -0.20 to -0.01 | 2.76e-02 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | Later (1965-92) manufacturers on an inventory, kernel (per SD) | 0.004 | -0.11 to 0.12 | 9.41e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M3: + 1940 ED fixed effects | Later (1965-92) manufacturers on an inventory, kernel (per SD) | 0.234 | -0.20 to 0.66 | 2.88e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M1: birth year (and sex) only | HOLC grade D (vs A/B) | -0.460 | -0.75 to -0.17 | 1.69e-03 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2: + 1940 person and household controls | HOLC grade D (vs A/B) | -0.227 | -0.60 to 0.15 | 2.33e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2 joint | Hazardous trades kernel, with industrial and commercial land | -0.030 | -0.17 to 0.11 | 6.70e-01 | 13376 |
| Numident (men and women, deaths 1988-2005) | M2 joint | Industrial land, with hazardous trades and commercial land | -0.002 | -0.09 to 0.09 | 9.66e-01 | 13376 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Hazardous trades to 1940, kernel (per SD) | -0.114 | -0.39 to 0.16 | 4.13e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Hazardous trades to 1940, kernel (per SD) | 0.094 | -0.17 to 0.36 | 4.89e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Hazardous trades to 1940, kernel (per SD) | -0.392 | -1.31 to 0.53 | 4.04e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Hazardous trade within 500 m | -0.944 | -1.45 to -0.43 | 2.82e-04 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Hazardous trade within 500 m | -0.499 | -1.04 to 0.05 | 7.31e-02 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Hazardous trade within 500 m | -0.253 | -1.08 to 0.57 | 5.49e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Industrial land within 250 m, 1937 (per 10 points) | -0.376 | -0.54 to -0.21 | 6.32e-06 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Industrial land within 250 m, 1937 (per 10 points) | -0.234 | -0.39 to -0.08 | 2.73e-03 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Industrial land within 250 m, 1937 (per 10 points) | -0.093 | -0.33 to 0.14 | 4.38e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Placebo: commercial land within 250 m, 1937 (per 10 points) | -0.008 | -0.11 to 0.09 | 8.82e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Placebo: commercial land within 250 m, 1937 (per 10 points) | 0.082 | -0.02 to 0.19 | 1.30e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Placebo: commercial land within 250 m, 1937 (per 10 points) | 0.022 | -0.22 to 0.26 | 8.60e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | 1929 industrial district | -1.575 | -2.48 to -0.67 | 6.33e-04 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | 1929 industrial district | -0.982 | -1.88 to -0.09 | 3.15e-02 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.278 | -0.58 to 0.03 | 7.42e-02 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.019 | -0.35 to 0.31 | 9.10e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Later (1965-92) hazardous manufacturers on no inventory, kernel (per SD) | -0.169 | -1.60 to 1.26 | 8.17e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.532 | -0.84 to -0.22 | 7.05e-04 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.244 | -0.62 to 0.13 | 2.01e-01 | 8390 |
| DMF (men, deaths 1975 on) | M3: + 1940 ED fixed effects | Later (1965-92) manufacturers on an inventory, kernel (per SD) | -0.461 | -1.31 to 0.39 | 2.90e-01 | 8390 |
| DMF (men, deaths 1975 on) | M1: birth year (and sex) only | HOLC grade D (vs A/B) | -1.294 | -2.01 to -0.58 | 4.08e-04 | 8390 |
| DMF (men, deaths 1975 on) | M2: + 1940 person and household controls | HOLC grade D (vs A/B) | -0.302 | -1.26 to 0.65 | 5.36e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2 joint | Hazardous trades kernel, with industrial and commercial land | 0.075 | -0.23 to 0.38 | 6.27e-01 | 8390 |
| DMF (men, deaths 1975 on) | M2 joint | Industrial land, with hazardous trades and commercial land | -0.232 | -0.38 to -0.08 | 2.52e-03 | 8390 |

## Mean age at death, net of birth year and sex (groups of 20+)

| file | measure | group | n | adj_mean_age_at_death |
|---|---|---|---|---|
| DMF (men, deaths 1975 on) | 1929 zoning district | commercial | 366 | 80.29 |
| DMF (men, deaths 1975 on) | 1929 zoning district | industrial | 450 | 79.38 |
| DMF (men, deaths 1975 on) | 1929 zoning district | residence | 7574 | 80.94 |
| DMF (men, deaths 1975 on) | 1938 HOLC grade | A | 389 | 82.06 |
| DMF (men, deaths 1975 on) | 1938 HOLC grade | B | 1201 | 81.11 |
| DMF (men, deaths 1975 on) | 1938 HOLC grade | C | 3668 | 81.25 |
| DMF (men, deaths 1975 on) | 1938 HOLC grade | D | 2451 | 80.07 |
| DMF (men, deaths 1975 on) | 1938 HOLC grade | ungraded | 681 | 80.28 |
| DMF (men, deaths 1975 on) | Hazardous trades to 1940 | hazardous trade within 500 m | 2683 | 80.20 |
| DMF (men, deaths 1975 on) | Hazardous trades to 1940 | none within 500 m | 5707 | 81.13 |
| DMF (men, deaths 1975 on) | Industrial land 1937 | 10%+ industrial within 250 m | 805 | 79.52 |
| DMF (men, deaths 1975 on) | Industrial land 1937 | under 10% | 7585 | 80.97 |
| Numident (men and women, deaths 1988-2005) | 1929 zoning district | commercial | 553 | 81.48 |
| Numident (men and women, deaths 1988-2005) | 1929 zoning district | industrial | 762 | 81.86 |
| Numident (men and women, deaths 1988-2005) | 1929 zoning district | residence | 12061 | 81.96 |
| Numident (men and women, deaths 1988-2005) | 1938 HOLC grade | A | 608 | 81.98 |
| Numident (men and women, deaths 1988-2005) | 1938 HOLC grade | B | 2014 | 82.11 |
| Numident (men and women, deaths 1988-2005) | 1938 HOLC grade | C | 5841 | 82.01 |
| Numident (men and women, deaths 1988-2005) | 1938 HOLC grade | D | 3976 | 81.63 |
| Numident (men and women, deaths 1988-2005) | 1938 HOLC grade | ungraded | 937 | 82.14 |
| Numident (men and women, deaths 1988-2005) | Hazardous trades to 1940 | hazardous trade within 500 m | 4220 | 81.80 |
| Numident (men and women, deaths 1988-2005) | Hazardous trades to 1940 | none within 500 m | 9156 | 81.99 |
| Numident (men and women, deaths 1988-2005) | Industrial land 1937 | 10%+ industrial within 250 m | 1228 | 81.64 |
| Numident (men and women, deaths 1988-2005) | Industrial land 1937 | under 10% | 12148 | 81.96 |
