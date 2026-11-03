# CenSoc: further analyses of Denver's 1940 residents

Years of age at death (95% CI) unless stated; OLS with birth-year fixed effects, 1940 controls, CenSoc weights, errors clustered by 1940 ED.

## 1. By age in 1940

| term | years | lo | hi | p | n | age_in_1940 | exposure | people |
|---|---|---|---|---|---|---|---|---|
| zone_ind | 0.063 | -1.587 | 1.712 | 9.41e-01 | 1559 | 0-14 in 1940 | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.176 | -0.499 | 0.147 | 2.84e-01 | 1559 | 0-14 in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.484 | -1.614 | 0.647 | 4.02e-01 | 1559 | 0-14 in 1940 | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | 0.406 | -1.318 | 2.130 | 6.44e-01 | 1559 | 0-14 in 1940 | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.175 | -0.047 | 0.396 | 1.22e-01 | 1559 | 0-14 in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | -1.335 | -2.865 | 0.196 | 8.74e-02 | 3181 | 15-29 in 1940 | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.485 | -0.711 | -0.258 | 2.91e-05 | 3181 | 15-29 in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.443 | -1.710 | 0.824 | 4.93e-01 | 3181 | 15-29 in 1940 | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | -0.300 | -2.200 | 1.600 | 7.57e-01 | 3181 | 15-29 in 1940 | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.072 | -0.117 | 0.262 | 4.53e-01 | 3181 | 15-29 in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | -0.796 | -1.850 | 0.257 | 1.38e-01 | 3650 | 30+ in 1940 | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | 0.064 | -0.130 | 0.258 | 5.17e-01 | 3650 | 30+ in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | 0.171 | -0.467 | 0.810 | 5.99e-01 | 3650 | 30+ in 1940 | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | -0.730 | -1.554 | 0.094 | 8.28e-02 | 3650 | 30+ in 1940 | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.010 | -0.100 | 0.119 | 8.61e-01 | 3650 | 30+ in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | 0.061 | -0.342 | 0.464 | 7.68e-01 | 3327 | 0-14 in 1940 | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | -0.024 | -0.125 | 0.077 | 6.37e-01 | 3327 | 0-14 in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | 0.089 | -0.252 | 0.430 | 6.08e-01 | 3327 | 0-14 in 1940 | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.346 | -0.900 | 0.207 | 2.20e-01 | 3327 | 0-14 in 1940 | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | -0.003 | -0.069 | 0.063 | 9.30e-01 | 3327 | 0-14 in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| zone_ind | 0.384 | -0.083 | 0.851 | 1.07e-01 | 8202 | 15-29 in 1940 | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | -0.092 | -0.209 | 0.024 | 1.21e-01 | 8202 | 15-29 in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.113 | -0.482 | 0.256 | 5.49e-01 | 8202 | 15-29 in 1940 | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.488 | -0.921 | -0.055 | 2.73e-02 | 8202 | 15-29 in 1940 | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | 0.008 | -0.043 | 0.060 | 7.56e-01 | 8202 | 15-29 in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| zone_ind | -0.486 | -1.579 | 0.606 | 3.83e-01 | 1847 | 30+ in 1940 | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | 0.161 | -0.117 | 0.438 | 2.57e-01 | 1847 | 30+ in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.004 | -0.685 | 0.676 | 9.90e-01 | 1847 | 30+ in 1940 | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | 0.085 | -0.759 | 0.929 | 8.43e-01 | 1847 | 30+ in 1940 | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | 0.012 | -0.082 | 0.107 | 7.96e-01 | 1847 | 30+ in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |

## 2. Stayers and leavers (Numident)

| group | people | pct_died_denver_metro | pct_died_denver_county | pct_died_colorado |
|---|---|---|---|---|
| other 1940 addresses | 10717 | 52.8 | 27.0 | 60.7 |
| 1940 address in a 1929 industrial district | 705 | 56.5 | 27.1 | 63.2 |
| 10%+ industrial land within 250 m | 729 | 53.6 | 23.2 | 61.3 |

| exposure | analysis | years | lo | hi | p | n | term |
|---|---|---|---|---|---|---|---|
| 1929 industrial district | Died in the Denver metro (percentage points) | 0.380 | -4.230 | 4.990 | 0.8720 | 12151 |  |
| Industrial land within 250 m, 1937 (per 10 points) | Died in the Denver metro (percentage points) | -0.520 | -1.370 | 0.320 | 0.2220 | 12151 |  |
| Hazardous trade within 500 m (to 1940) | Died in the Denver metro (percentage points) | 0.960 | -2.170 | 4.090 | 0.5460 | 12151 |  |
| HOLC grade D (vs A/B) | Died in the Denver metro (percentage points) | 4.250 | -0.320 | 8.810 | 0.0681 | 12151 |  |
| Placebo: commercial land within 250 m (per 10 points) | Died in the Denver metro (percentage points) | -0.490 | -1.110 | 0.130 | 0.1250 | 12151 |  |
| 1929 industrial district | Age at death, people who died in the Denver metro | 0.194 | -0.318 | 0.705 | 0.4570 | 6253 | zone_ind |
| Industrial land within 250 m, 1937 (per 10 points) | Age at death, people who died in the Denver metro | 0.025 | -0.061 | 0.112 | 0.5670 | 6253 | ind10 |
| Hazardous trade within 500 m (to 1940) | Age at death, people who died in the Denver metro | 0.087 | -0.361 | 0.535 | 0.7030 | 6253 | haz_500 |
| HOLC grade D (vs A/B) | Age at death, people who died in the Denver metro | -0.218 | -0.765 | 0.329 | 0.4360 | 6253 | holc_D |
| Placebo: commercial land within 250 m (per 10 points) | Age at death, people who died in the Denver metro | 0.003 | -0.069 | 0.074 | 0.9450 | 6253 | com10 |
| 1929 industrial district | Age at death, people who died elsewhere | -0.135 | -0.793 | 0.523 | 0.6880 | 5898 | zone_ind |
| Industrial land within 250 m, 1937 (per 10 points) | Age at death, people who died elsewhere | -0.062 | -0.237 | 0.112 | 0.4840 | 5898 | ind10 |
| Hazardous trade within 500 m (to 1940) | Age at death, people who died elsewhere | -0.323 | -0.759 | 0.113 | 0.1470 | 5898 | haz_500 |
| HOLC grade D (vs A/B) | Age at death, people who died elsewhere | -0.008 | -0.659 | 0.643 | 0.9810 | 5898 | holc_D |
| Placebo: commercial land within 250 m (per 10 points) | Age at death, people who died elsewhere | -0.017 | -0.082 | 0.047 | 0.5990 | 5898 | com10 |

## 3. Work and home

| term | years | lo | hi | p | n | analysis | model | people |
|---|---|---|---|---|---|---|---|---|
| own job: hazardous industry | 0.232 | -0.577 | 1.041 | 0.57400 | 5725 | Own job in a hazardous industry (men in the 1940 labour force) | job only | Men, deaths 1975-2020 (CenSoc-DMF) |
| own job: manufacturing | -0.288 | -0.912 | 0.336 | 0.36500 | 5725 | Own job in manufacturing (men in the 1940 labour force) | job only | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1929 industrial district | -0.716 | -1.744 | 0.313 | 0.17300 | 5725 | Men in the 1940 labour force: address and own job together | zone_ind | Men, deaths 1975-2020 (CenSoc-DMF) |
| own job: hazardous industry | 0.243 | -0.563 | 1.049 | 0.55500 | 5725 | Men in the 1940 labour force: address and own job together | zone_ind | Men, deaths 1975-2020 (CenSoc-DMF) |
| industrial land within 250 m (per 10 points) | -0.230 | -0.441 | -0.019 | 0.03230 | 5725 | Men in the 1940 labour force: address and own job together | ind10 | Men, deaths 1975-2020 (CenSoc-DMF) |
| own job: hazardous industry | 0.275 | -0.537 | 1.086 | 0.50700 | 5725 | Men in the 1940 labour force: address and own job together | ind10 | Men, deaths 1975-2020 (CenSoc-DMF) |
| hazardous trade within 500 m | -0.673 | -1.236 | -0.111 | 0.01900 | 5725 | Men in the 1940 labour force: address and own job together | haz_500 | Men, deaths 1975-2020 (CenSoc-DMF) |
| own job: hazardous industry | 0.228 | -0.586 | 1.041 | 0.58300 | 5725 | Men in the 1940 labour force: address and own job together | haz_500 | Men, deaths 1975-2020 (CenSoc-DMF) |
| head's job: hazardous industry | -0.606 | -1.437 | 0.226 | 0.15400 | 8390 | Household head in a hazardous industry (everyone) | job only | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1929 industrial district | -0.688 | -1.520 | 0.145 | 0.10500 | 8390 | Everyone: address and household head's job together | zone_ind | Men, deaths 1975-2020 (CenSoc-DMF) |
| head's job: hazardous industry | -0.580 | -1.413 | 0.253 | 0.17200 | 8390 | Everyone: address and household head's job together | zone_ind | Men, deaths 1975-2020 (CenSoc-DMF) |
| industrial land within 250 m (per 10 points) | -0.224 | -0.376 | -0.072 | 0.00395 | 8390 | Everyone: address and household head's job together | ind10 | Men, deaths 1975-2020 (CenSoc-DMF) |
| head's job: hazardous industry | -0.524 | -1.359 | 0.310 | 0.21800 | 8390 | Everyone: address and household head's job together | ind10 | Men, deaths 1975-2020 (CenSoc-DMF) |
| hazardous trade within 500 m | -0.234 | -0.840 | 0.371 | 0.44800 | 8390 | Everyone: address and household head's job together | haz_500 | Men, deaths 1975-2020 (CenSoc-DMF) |
| head's job: hazardous industry | -0.600 | -1.435 | 0.235 | 0.15900 | 8390 | Everyone: address and household head's job together | haz_500 | Men, deaths 1975-2020 (CenSoc-DMF) |
| own job: hazardous industry | 0.210 | -0.552 | 0.973 | 0.58900 | 2796 | Own job in a hazardous industry (men in the 1940 labour force) | job only | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| own job: manufacturing | 0.241 | -0.304 | 0.785 | 0.38600 | 2796 | Own job in manufacturing (men in the 1940 labour force) | job only | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1929 industrial district | 0.067 | -1.063 | 1.198 | 0.90700 | 2796 | Men in the 1940 labour force: address and own job together | zone_ind | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| own job: hazardous industry | 0.209 | -0.554 | 0.971 | 0.59200 | 2796 | Men in the 1940 labour force: address and own job together | zone_ind | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| industrial land within 250 m (per 10 points) | -0.046 | -0.277 | 0.185 | 0.69900 | 2796 | Men in the 1940 labour force: address and own job together | ind10 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| own job: hazardous industry | 0.221 | -0.537 | 0.980 | 0.56700 | 2796 | Men in the 1940 labour force: address and own job together | ind10 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| hazardous trade within 500 m | 0.277 | -0.272 | 0.825 | 0.32300 | 2796 | Men in the 1940 labour force: address and own job together | haz_500 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| own job: hazardous industry | 0.222 | -0.537 | 0.982 | 0.56600 | 2796 | Men in the 1940 labour force: address and own job together | haz_500 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| head's job: hazardous industry | -0.084 | -0.415 | 0.246 | 0.61700 | 13376 | Household head in a hazardous industry (everyone) | job only | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1929 industrial district | 0.096 | -0.324 | 0.517 | 0.65300 | 13376 | Everyone: address and household head's job together | zone_ind | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| head's job: hazardous industry | -0.085 | -0.416 | 0.245 | 0.61200 | 13376 | Everyone: address and household head's job together | zone_ind | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| industrial land within 250 m (per 10 points) | -0.007 | -0.096 | 0.082 | 0.87900 | 13376 | Everyone: address and household head's job together | ind10 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| head's job: hazardous industry | -0.083 | -0.414 | 0.247 | 0.62100 | 13376 | Everyone: address and household head's job together | ind10 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| hazardous trade within 500 m | -0.063 | -0.353 | 0.227 | 0.66900 | 13376 | Everyone: address and household head's job together | haz_500 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| head's job: hazardous industry | -0.085 | -0.416 | 0.245 | 0.61300 | 13376 | Everyone: address and household head's job together | haz_500 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |

## 4. Groups

| term | years | lo | hi | p | n | group | exposure | people |
|---|---|---|---|---|---|---|---|---|
| zone_ind | -1.002 | -3.229 | 1.226 | 0.3790 | 310 | Hispanic | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.296 | -0.686 | 0.094 | 0.1380 | 310 | Hispanic | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | 0.205 | -1.867 | 2.276 | 0.8460 | 310 | Hispanic | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | -0.137 | -6.283 | 6.009 | 0.9650 | 310 | Hispanic | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.331 | 0.031 | 0.631 | 0.0317 | 310 | Hispanic | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | -0.745 | -1.564 | 0.073 | 0.0744 | 7969 | White, not Hispanic | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.259 | -0.423 | -0.095 | 0.0020 | 7969 | White, not Hispanic | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.332 | -0.955 | 0.292 | 0.2970 | 7969 | White, not Hispanic | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | -0.228 | -1.204 | 0.747 | 0.6460 | 7969 | White, not Hispanic | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.045 | -0.057 | 0.147 | 0.3850 | 7969 | White, not Hispanic | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | -0.425 | -1.625 | 0.775 | 0.4870 | 4502 | Renting household | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.254 | -0.451 | -0.057 | 0.0114 | 4502 | Renting household | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.217 | -0.857 | 0.423 | 0.5070 | 4502 | Renting household | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | -0.639 | -1.840 | 0.563 | 0.2980 | 4502 | Renting household | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.086 | -0.031 | 0.203 | 0.1500 | 4502 | Renting household | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | -1.217 | -2.315 | -0.120 | 0.0298 | 3888 | Owner household | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.204 | -0.429 | 0.020 | 0.0741 | 3888 | Owner household | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.512 | -1.754 | 0.730 | 0.4190 | 3888 | Owner household | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | 0.128 | -1.411 | 1.668 | 0.8700 | 3888 | Owner household | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | -0.007 | -0.215 | 0.201 | 0.9450 | 3888 | Owner household | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | 1.574 | 0.238 | 2.910 | 0.0214 | 477 | Hispanic | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | 0.094 | -0.158 | 0.346 | 0.4630 | 477 | Hispanic | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.278 | -1.408 | 0.852 | 0.6300 | 477 | Hispanic | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.791 | -5.923 | 4.341 | 0.7630 | 477 | Hispanic | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | 0.000 | -0.256 | 0.257 | 0.9980 | 477 | Hispanic | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| zone_ind | -0.160 | -0.571 | 0.252 | 0.4470 | 12687 | White, not Hispanic | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | -0.033 | -0.132 | 0.066 | 0.5180 | 12687 | White, not Hispanic | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.042 | -0.329 | 0.244 | 0.7720 | 12687 | White, not Hispanic | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.227 | -0.597 | 0.142 | 0.2280 | 12687 | White, not Hispanic | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | -0.004 | -0.045 | 0.037 | 0.8390 | 12687 | White, not Hispanic | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| zone_ind | 0.161 | -0.452 | 0.773 | 0.6070 | 7344 | Renting household | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | -0.004 | -0.118 | 0.110 | 0.9440 | 7344 | Renting household | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.139 | -0.471 | 0.193 | 0.4110 | 7344 | Renting household | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | 0.066 | -0.425 | 0.558 | 0.7920 | 7344 | Renting household | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | 0.003 | -0.043 | 0.049 | 0.8980 | 7344 | Renting household | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| zone_ind | 0.031 | -0.551 | 0.613 | 0.9170 | 6032 | Owner household | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | 0.001 | -0.146 | 0.147 | 0.9940 | 6032 | Owner household | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | 0.097 | -0.394 | 0.588 | 0.6980 | 6032 | Owner household | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.471 | -1.071 | 0.129 | 0.1240 | 6032 | Owner household | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | 0.029 | -0.076 | 0.134 | 0.5830 | 6032 | Owner household | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |

## 5. Who is linked (share of 1940 residents with a death record in the window)

| grp | people | n_1940 | pct_linked_dmf | pct_linked_numident |
|---|---|---|---|---|
| other addresses | Men aged 0-50 in 1940 | 76466 | 10.71 | 7.92 |
| 1929 industrial district | Men aged 0-50 in 1940 | 5447 | 9.34 | 8.22 |
| 10%+ industrial land within 250 m | Men aged 0-50 in 1940 | 6026 | 10.67 | 7.68 |
| other addresses | Women aged 0-50 in 1940 | 83663 |  | 8.15 |
| 1929 industrial district | Women aged 0-50 in 1940 | 5467 |  | 8.19 |
| 10%+ industrial land within 250 m | Women aged 0-50 in 1940 | 6051 |  | 7.27 |
| HOLC C | Everyone aged 0-50 in 1940 | 78388 |  | 8.05 |
| HOLC B | Everyone aged 0-50 in 1940 | 26328 |  | 8.14 |
| HOLC D | Everyone aged 0-50 in 1940 | 55197 |  | 8.09 |
| HOLC ungraded | Everyone aged 0-50 in 1940 | 15190 |  | 7.14 |
| HOLC A | Everyone aged 0-50 in 1940 | 8017 |  | 8.31 |

| outcome | term | pct_points | lo | hi | p | n |
|---|---|---|---|---|---|---|
| linked_dmf | zone_ind | -0.882 | -2.050 | 0.287 | 0.139000 | 87939 |
| linked_dmf | ind10 | 0.166 | -0.154 | 0.486 | 0.310000 | 87939 |
| linked_dmf | haz_500 | -0.751 | -1.637 | 0.135 | 0.096800 | 87939 |
| linked_num | zone_ind | 0.313 | -0.567 | 1.194 | 0.486000 | 183120 |
| linked_num | ind10 | 0.042 | -0.140 | 0.225 | 0.651000 | 183120 |
| linked_num | haz_500 | -1.022 | -1.555 | -0.489 | 0.000171 | 183120 |

## 6. Gompertz hazard ratios (and change in life expectancy at 65, years)

| people | window | exposure | hr | hr_lower | hr_upper | converged | n | e65_years | e65_lower | e65_upper |
|---|---|---|---|---|---|---|---|---|---|---|
| Men, deaths 1975-2020 (CenSoc-DMF) | 1975-2005 | 1929 industrial district | 1.117 | 0.962 | 1.297 | TRUE | 6949 | -0.84 | -1.93 | 0.30 |
| Men, deaths 1975-2020 (CenSoc-DMF) | 1975-2005 | Industrial land within 250 m, 1937 (per 10 points) | 0.997 | 0.966 | 1.028 | TRUE | 6949 | 0.03 | -0.21 | 0.26 |
| Men, deaths 1975-2020 (CenSoc-DMF) | 1975-2005 | Hazardous trade within 500 m (to 1940) | 0.990 | 0.904 | 1.083 | TRUE | 6949 | 0.08 | -0.60 | 0.77 |
| Men, deaths 1975-2020 (CenSoc-DMF) | 1975-2005 | HOLC grade D (vs A/B) | 1.163 | 1.013 | 1.335 | TRUE | 6949 | -1.14 | -2.14 | -0.10 |
| Men, deaths 1975-2020 (CenSoc-DMF) | 1975-2005 | Placebo: commercial land within 250 m (per 10 points) | 1.003 | 0.987 | 1.020 | TRUE | 6949 | -0.03 | -0.15 | 0.10 |
| Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) | 1988-2005 | 1929 industrial district | 1.097 | 0.922 | 1.306 | TRUE | 13376 | -0.71 | -2.02 | 0.64 |
| Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) | 1988-2005 | Industrial land within 250 m, 1937 (per 10 points) | 1.016 | 0.980 | 1.054 | TRUE | 13376 | -0.13 | -0.41 | 0.16 |
| Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) | 1988-2005 | Hazardous trade within 500 m (to 1940) | 0.996 | 0.903 | 1.098 | TRUE | 13376 | 0.03 | -0.72 | 0.80 |
| Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) | 1988-2005 | HOLC grade D (vs A/B) | 0.960 | 0.827 | 1.114 | TRUE | 13376 | 0.33 | -0.85 | 1.54 |
| Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) | 1988-2005 | Placebo: commercial land within 250 m (per 10 points) | 0.998 | 0.980 | 1.015 | TRUE | 13376 | 0.02 | -0.12 | 0.16 |

## 7. Highways and displacement

| address | residents_1940 | pct_hispanic | pct_black | pct_foreign_born | pct_owner |
|---|---|---|---|---|---|
| elsewhere | 197183 | 3.8 | 2.8 | 7.4 | 46.3 |
| 75-500 m from a later freeway | 31971 | 4.9 | 0.2 | 9.8 | 50.0 |
| in a later freeway's path (within 75 m) | 3071 | 14.8 | 0.4 | 10.5 | 46.8 |
| on land cleared by 1977 (USGS) | 3657 | 2.1 | 2.2 | 10.4 | 46.4 |

| term | ed_fixed_effects | years | lo | hi | p | n | n_exposed | people |
|---|---|---|---|---|---|---|---|---|
| 1940 address in a later freeway's path (within 75 m) | FALSE | -0.100 | -1.423 | 1.223 | 0.8820 | 8390 | 140 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address in a later freeway's path (within 75 m) | TRUE | 0.049 | -1.026 | 1.124 | 0.9290 | 8390 | 140 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address 75-500 m from a later freeway (traffic, not cleared) | FALSE | -0.178 | -0.751 | 0.395 | 0.5430 | 8390 | 1320 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address 75-500 m from a later freeway (traffic, not cleared) | TRUE | 0.387 | -0.364 | 1.139 | 0.3120 | 8390 | 1320 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address on residential land cleared by 1977 | FALSE | -0.101 | -1.609 | 1.406 | 0.8950 | 8390 | 150 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address on residential land cleared by 1977 | TRUE | 0.208 | -1.620 | 2.037 | 0.8230 | 8390 | 150 | Men, deaths 1975-2020 (CenSoc-DMF) |
| in a freeway's path or cleared | FALSE | -0.169 | -1.253 | 0.914 | 0.7590 | 8390 | 276 | Men, deaths 1975-2020 (CenSoc-DMF) |
| in a freeway's path or cleared | TRUE | 0.068 | -1.092 | 1.228 | 0.9090 | 8390 | 276 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address within 100 m of a major road open in 1940 | FALSE | 0.759 | -1.895 | 3.412 | 0.5750 | 8390 | 176 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address within 100 m of a major road open in 1940 | TRUE | 0.232 | -2.220 | 2.685 | 0.8530 | 8390 | 176 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address in a later freeway's path (within 75 m) | FALSE | -0.314 | -1.007 | 0.379 | 0.3740 | 13376 | 209 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address in a later freeway's path (within 75 m) | TRUE | -0.232 | -0.990 | 0.527 | 0.5490 | 13376 | 209 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address 75-500 m from a later freeway (traffic, not cleared) | FALSE | 0.122 | -0.166 | 0.409 | 0.4070 | 13376 | 2065 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address 75-500 m from a later freeway (traffic, not cleared) | TRUE | -0.034 | -0.453 | 0.384 | 0.8720 | 13376 | 2065 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address on residential land cleared by 1977 | FALSE | -0.335 | -1.178 | 0.508 | 0.4360 | 13376 | 244 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address on residential land cleared by 1977 | TRUE | -0.353 | -1.344 | 0.638 | 0.4850 | 13376 | 244 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| in a freeway's path or cleared | FALSE | -0.353 | -0.913 | 0.207 | 0.2170 | 13376 | 438 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| in a freeway's path or cleared | TRUE | -0.317 | -0.960 | 0.327 | 0.3350 | 13376 | 438 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address within 100 m of a major road open in 1940 | FALSE | -0.505 | -1.076 | 0.067 | 0.0836 | 13376 | 232 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address within 100 m of a major road open in 1940 | TRUE | -0.318 | -1.102 | 0.467 | 0.4270 | 13376 | 232 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
