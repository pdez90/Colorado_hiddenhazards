# CenSoc: further analyses of Denver's 1940 residents

Years of age at death (95% CI) unless stated; OLS with birth-year fixed effects, 1940 controls, CenSoc weights, errors clustered by 1940 ED.

## 1. By age in 1940

| term | years | lo | hi | p | n | age_in_1940 | exposure | people |
|---|---|---|---|---|---|---|---|---|
| zone_ind | 0.060 | -1.587 | 1.708 | 0.943000 | 1559 | 0-14 in 1940 | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.175 | -0.498 | 0.147 | 0.287000 | 1559 | 0-14 in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.310 | -1.461 | 0.841 | 0.597000 | 1559 | 0-14 in 1940 | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | 0.459 | -1.262 | 2.180 | 0.601000 | 1559 | 0-14 in 1940 | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.175 | -0.046 | 0.395 | 0.121000 | 1559 | 0-14 in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | -1.345 | -2.872 | 0.182 | 0.084300 | 3181 | 15-29 in 1940 | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.484 | -0.710 | -0.259 | 0.000027 | 3181 | 15-29 in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.559 | -1.620 | 0.501 | 0.301000 | 3181 | 15-29 in 1940 | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | -0.093 | -2.030 | 1.843 | 0.925000 | 3181 | 15-29 in 1940 | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.074 | -0.115 | 0.264 | 0.442000 | 3181 | 15-29 in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | -0.788 | -1.838 | 0.263 | 0.142000 | 3650 | 30+ in 1940 | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | 0.067 | -0.127 | 0.260 | 0.499000 | 3650 | 30+ in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | 0.205 | -0.357 | 0.766 | 0.475000 | 3650 | 30+ in 1940 | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | -0.604 | -1.437 | 0.230 | 0.156000 | 3650 | 30+ in 1940 | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.016 | -0.092 | 0.124 | 0.770000 | 3650 | 30+ in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | 0.056 | -0.347 | 0.460 | 0.784000 | 3327 | 0-14 in 1940 | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | -0.025 | -0.126 | 0.075 | 0.620000 | 3327 | 0-14 in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | 0.013 | -0.259 | 0.286 | 0.923000 | 3327 | 0-14 in 1940 | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.370 | -0.929 | 0.189 | 0.195000 | 3327 | 0-14 in 1940 | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | -0.004 | -0.069 | 0.062 | 0.912000 | 3327 | 0-14 in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| zone_ind | 0.386 | -0.079 | 0.852 | 0.104000 | 8202 | 15-29 in 1940 | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | -0.091 | -0.208 | 0.025 | 0.124000 | 8202 | 15-29 in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.030 | -0.341 | 0.281 | 0.848000 | 8202 | 15-29 in 1940 | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.488 | -0.926 | -0.050 | 0.029000 | 8202 | 15-29 in 1940 | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | 0.008 | -0.044 | 0.060 | 0.766000 | 8202 | 15-29 in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| zone_ind | -0.516 | -1.611 | 0.579 | 0.356000 | 1847 | 30+ in 1940 | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | 0.152 | -0.127 | 0.431 | 0.285000 | 1847 | 30+ in 1940 | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.014 | -0.539 | 0.510 | 0.957000 | 1847 | 30+ in 1940 | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.017 | -0.867 | 0.832 | 0.968000 | 1847 | 30+ in 1940 | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | 0.012 | -0.083 | 0.107 | 0.801000 | 1847 | 30+ in 1940 | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |

## 2. Stayers and leavers (Numident)

| group | people | pct_died_denver_metro | pct_died_denver_county | pct_died_colorado |
|---|---|---|---|---|
| other 1940 addresses | 10717 | 52.8 | 27.0 | 60.7 |
| 1940 address in a 1929 industrial district | 705 | 56.5 | 27.1 | 63.2 |
| 10%+ industrial land within 250 m | 729 | 53.6 | 23.2 | 61.3 |

| exposure | analysis | years | lo | hi | p | n | term |
|---|---|---|---|---|---|---|---|
| 1929 industrial district | Died in the Denver metro (percentage points) | 0.450 | -4.170 | 5.070 | 0.8490 | 12151 |  |
| Industrial land within 250 m, 1937 (per 10 points) | Died in the Denver metro (percentage points) | -0.520 | -1.360 | 0.330 | 0.2290 | 12151 |  |
| Hazardous trade within 500 m (to 1940) | Died in the Denver metro (percentage points) | 0.520 | -2.210 | 3.250 | 0.7080 | 12151 |  |
| HOLC grade D (vs A/B) | Died in the Denver metro (percentage points) | 4.540 | -0.020 | 9.110 | 0.0511 | 12151 |  |
| Placebo: commercial land within 250 m (per 10 points) | Died in the Denver metro (percentage points) | -0.490 | -1.110 | 0.130 | 0.1200 | 12151 |  |
| 1929 industrial district | Age at death, people who died in the Denver metro | 0.182 | -0.331 | 0.694 | 0.4870 | 6253 | zone_ind |
| Industrial land within 250 m, 1937 (per 10 points) | Age at death, people who died in the Denver metro | 0.022 | -0.064 | 0.109 | 0.6140 | 6253 | ind10 |
| Hazardous trade within 500 m (to 1940) | Age at death, people who died in the Denver metro | 0.153 | -0.211 | 0.518 | 0.4100 | 6253 | haz_500 |
| HOLC grade D (vs A/B) | Age at death, people who died in the Denver metro | -0.274 | -0.826 | 0.278 | 0.3310 | 6253 | holc_D |
| Placebo: commercial land within 250 m (per 10 points) | Age at death, people who died in the Denver metro | 0.002 | -0.070 | 0.074 | 0.9540 | 6253 | com10 |
| 1929 industrial district | Age at death, people who died elsewhere | -0.133 | -0.791 | 0.525 | 0.6920 | 5898 | zone_ind |
| Industrial land within 250 m, 1937 (per 10 points) | Age at death, people who died elsewhere | -0.062 | -0.236 | 0.112 | 0.4830 | 5898 | ind10 |
| Hazardous trade within 500 m (to 1940) | Age at death, people who died elsewhere | -0.221 | -0.577 | 0.134 | 0.2230 | 5898 | haz_500 |
| HOLC grade D (vs A/B) | Age at death, people who died elsewhere | 0.019 | -0.639 | 0.676 | 0.9560 | 5898 | holc_D |
| Placebo: commercial land within 250 m (per 10 points) | Age at death, people who died elsewhere | -0.017 | -0.083 | 0.048 | 0.6060 | 5898 | com10 |

## 3. Work and home

| term | years | lo | hi | p | n | analysis | model | people |
|---|---|---|---|---|---|---|---|---|
| own job: hazardous industry | 0.228 | -0.579 | 1.035 | 0.58000 | 5725 | Own job in a hazardous industry (men in the 1940 labour force) | job only | Men, deaths 1975-2020 (CenSoc-DMF) |
| own job: manufacturing | -0.292 | -0.917 | 0.333 | 0.35900 | 5725 | Own job in manufacturing (men in the 1940 labour force) | job only | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1929 industrial district | -0.712 | -1.739 | 0.314 | 0.17400 | 5725 | Men in the 1940 labour force: address and own job together | zone_ind | Men, deaths 1975-2020 (CenSoc-DMF) |
| own job: hazardous industry | 0.239 | -0.566 | 1.043 | 0.56100 | 5725 | Men in the 1940 labour force: address and own job together | zone_ind | Men, deaths 1975-2020 (CenSoc-DMF) |
| industrial land within 250 m (per 10 points) | -0.230 | -0.440 | -0.020 | 0.03190 | 5725 | Men in the 1940 labour force: address and own job together | ind10 | Men, deaths 1975-2020 (CenSoc-DMF) |
| own job: hazardous industry | 0.270 | -0.539 | 1.080 | 0.51200 | 5725 | Men in the 1940 labour force: address and own job together | ind10 | Men, deaths 1975-2020 (CenSoc-DMF) |
| hazardous trade within 500 m | -0.605 | -1.129 | -0.081 | 0.02380 | 5725 | Men in the 1940 labour force: address and own job together | haz_500 | Men, deaths 1975-2020 (CenSoc-DMF) |
| own job: hazardous industry | 0.230 | -0.580 | 1.040 | 0.57800 | 5725 | Men in the 1940 labour force: address and own job together | haz_500 | Men, deaths 1975-2020 (CenSoc-DMF) |
| head's job: hazardous industry | -0.610 | -1.442 | 0.223 | 0.15100 | 8390 | Household head in a hazardous industry (everyone) | job only | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1929 industrial district | -0.690 | -1.520 | 0.140 | 0.10300 | 8390 | Everyone: address and household head's job together | zone_ind | Men, deaths 1975-2020 (CenSoc-DMF) |
| head's job: hazardous industry | -0.584 | -1.417 | 0.250 | 0.17000 | 8390 | Everyone: address and household head's job together | zone_ind | Men, deaths 1975-2020 (CenSoc-DMF) |
| industrial land within 250 m (per 10 points) | -0.224 | -0.376 | -0.072 | 0.00385 | 8390 | Everyone: address and household head's job together | ind10 | Men, deaths 1975-2020 (CenSoc-DMF) |
| head's job: hazardous industry | -0.528 | -1.364 | 0.307 | 0.21500 | 8390 | Everyone: address and household head's job together | ind10 | Men, deaths 1975-2020 (CenSoc-DMF) |
| hazardous trade within 500 m | -0.194 | -0.736 | 0.349 | 0.48400 | 8390 | Everyone: address and household head's job together | haz_500 | Men, deaths 1975-2020 (CenSoc-DMF) |
| head's job: hazardous industry | -0.597 | -1.433 | 0.239 | 0.16200 | 8390 | Everyone: address and household head's job together | haz_500 | Men, deaths 1975-2020 (CenSoc-DMF) |
| own job: hazardous industry | 0.205 | -0.564 | 0.973 | 0.60200 | 2796 | Own job in a hazardous industry (men in the 1940 labour force) | job only | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| own job: manufacturing | 0.246 | -0.301 | 0.792 | 0.37800 | 2796 | Own job in manufacturing (men in the 1940 labour force) | job only | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1929 industrial district | 0.065 | -1.065 | 1.194 | 0.91100 | 2796 | Men in the 1940 labour force: address and own job together | zone_ind | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| own job: hazardous industry | 0.203 | -0.565 | 0.972 | 0.60400 | 2796 | Men in the 1940 labour force: address and own job together | zone_ind | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| industrial land within 250 m (per 10 points) | -0.045 | -0.277 | 0.187 | 0.70300 | 2796 | Men in the 1940 labour force: address and own job together | ind10 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| own job: hazardous industry | 0.216 | -0.549 | 0.980 | 0.58000 | 2796 | Men in the 1940 labour force: address and own job together | ind10 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| hazardous trade within 500 m | 0.118 | -0.371 | 0.606 | 0.63700 | 2796 | Men in the 1940 labour force: address and own job together | haz_500 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| own job: hazardous industry | 0.209 | -0.556 | 0.975 | 0.59200 | 2796 | Men in the 1940 labour force: address and own job together | haz_500 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| head's job: hazardous industry | -0.086 | -0.417 | 0.245 | 0.60900 | 13376 | Household head in a hazardous industry (everyone) | job only | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1929 industrial district | 0.089 | -0.331 | 0.509 | 0.67700 | 13376 | Everyone: address and household head's job together | zone_ind | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| head's job: hazardous industry | -0.087 | -0.418 | 0.244 | 0.60500 | 13376 | Everyone: address and household head's job together | zone_ind | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| industrial land within 250 m (per 10 points) | -0.009 | -0.098 | 0.081 | 0.84900 | 13376 | Everyone: address and household head's job together | ind10 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| head's job: hazardous industry | -0.085 | -0.416 | 0.246 | 0.61400 | 13376 | Everyone: address and household head's job together | ind10 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| hazardous trade within 500 m | -0.034 | -0.270 | 0.202 | 0.77600 | 13376 | Everyone: address and household head's job together | haz_500 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| head's job: hazardous industry | -0.087 | -0.418 | 0.244 | 0.60800 | 13376 | Everyone: address and household head's job together | haz_500 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |

## 4. Groups

| term | years | lo | hi | p | n | group | exposure | people |
|---|---|---|---|---|---|---|---|---|
| zone_ind | -1.013 | -3.253 | 1.226 | 0.37600 | 310 | Hispanic | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.298 | -0.689 | 0.093 | 0.13700 | 310 | Hispanic | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.938 | -3.234 | 1.358 | 0.42400 | 310 | Hispanic | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | -0.383 | -7.456 | 6.690 | 0.91600 | 310 | Hispanic | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.331 | 0.033 | 0.628 | 0.03040 | 310 | Hispanic | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | -0.739 | -1.556 | 0.078 | 0.07620 | 7969 | White, not Hispanic | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.257 | -0.420 | -0.093 | 0.00211 | 7969 | White, not Hispanic | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.224 | -0.771 | 0.322 | 0.42200 | 7969 | White, not Hispanic | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | -0.063 | -1.058 | 0.932 | 0.90100 | 7969 | White, not Hispanic | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.051 | -0.052 | 0.153 | 0.33300 | 7969 | White, not Hispanic | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | -0.429 | -1.631 | 0.774 | 0.48500 | 4502 | Renting household | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.255 | -0.451 | -0.059 | 0.01060 | 4502 | Renting household | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.079 | -0.690 | 0.531 | 0.79900 | 4502 | Renting household | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | -0.288 | -1.551 | 0.975 | 0.65500 | 4502 | Renting household | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | 0.093 | -0.023 | 0.209 | 0.11700 | 4502 | Renting household | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | -1.217 | -2.315 | -0.120 | 0.02980 | 3888 | Owner household | 1929 industrial district | Men, deaths 1975-2020 (CenSoc-DMF) |
| ind10 | -0.204 | -0.429 | 0.020 | 0.07410 | 3888 | Owner household | Industrial land within 250 m, 1937 (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| haz_500 | -0.553 | -1.476 | 0.370 | 0.24000 | 3888 | Owner household | Hazardous trade within 500 m (to 1940) | Men, deaths 1975-2020 (CenSoc-DMF) |
| holc_D | 0.128 | -1.411 | 1.668 | 0.87000 | 3888 | Owner household | HOLC grade D (vs A/B) | Men, deaths 1975-2020 (CenSoc-DMF) |
| com10 | -0.007 | -0.215 | 0.201 | 0.94500 | 3888 | Owner household | Placebo: commercial land within 250 m (per 10 points) | Men, deaths 1975-2020 (CenSoc-DMF) |
| zone_ind | 1.546 | 0.217 | 2.875 | 0.02310 | 477 | Hispanic | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | 0.090 | -0.162 | 0.342 | 0.48600 | 477 | Hispanic | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.223 | -1.339 | 0.893 | 0.69600 | 477 | Hispanic | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -1.092 | -6.609 | 4.426 | 0.69800 | 477 | Hispanic | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | 0.003 | -0.248 | 0.253 | 0.98300 | 477 | Hispanic | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| zone_ind | -0.166 | -0.577 | 0.245 | 0.42800 | 12687 | White, not Hispanic | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | -0.034 | -0.133 | 0.065 | 0.49900 | 12687 | White, not Hispanic | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.032 | -0.269 | 0.204 | 0.78900 | 12687 | White, not Hispanic | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.259 | -0.628 | 0.111 | 0.17000 | 12687 | White, not Hispanic | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | -0.005 | -0.046 | 0.037 | 0.82200 | 12687 | White, not Hispanic | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| zone_ind | 0.147 | -0.466 | 0.760 | 0.63800 | 7344 | Renting household | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | -0.008 | -0.121 | 0.106 | 0.89700 | 7344 | Renting household | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.069 | -0.366 | 0.229 | 0.65100 | 7344 | Renting household | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.028 | -0.521 | 0.465 | 0.91200 | 7344 | Renting household | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | 0.002 | -0.044 | 0.048 | 0.93600 | 7344 | Renting household | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| zone_ind | 0.031 | -0.551 | 0.613 | 0.91700 | 6032 | Owner household | 1929 industrial district | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| ind10 | 0.001 | -0.146 | 0.147 | 0.99400 | 6032 | Owner household | Industrial land within 250 m, 1937 (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| haz_500 | -0.033 | -0.439 | 0.373 | 0.87400 | 6032 | Owner household | Hazardous trade within 500 m (to 1940) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| holc_D | -0.471 | -1.071 | 0.129 | 0.12400 | 6032 | Owner household | HOLC grade D (vs A/B) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| com10 | 0.029 | -0.076 | 0.134 | 0.58300 | 6032 | Owner household | Placebo: commercial land within 250 m (per 10 points) | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |

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
| linked_dmf | zone_ind | -0.894 | -2.064 | 0.276 | 0.134000 | 87939 |
| linked_dmf | ind10 | 0.162 | -0.158 | 0.482 | 0.320000 | 87939 |
| linked_dmf | haz_500 | -0.484 | -1.210 | 0.242 | 0.192000 | 87939 |
| linked_num | zone_ind | 0.318 | -0.561 | 1.198 | 0.478000 | 183120 |
| linked_num | ind10 | 0.043 | -0.139 | 0.225 | 0.644000 | 183120 |
| linked_num | haz_500 | -0.918 | -1.381 | -0.455 | 0.000101 | 183120 |

## 6. Gompertz hazard ratios (and change in life expectancy at 65, years)

| people | window | exposure | hr | hr_lower | hr_upper | converged | n | e65_years | e65_lower | e65_upper |
|---|---|---|---|---|---|---|---|---|---|---|
| Men, deaths 1975-2020 (CenSoc-DMF) | 1975-2005 | 1929 industrial district | 1.066 | 0.912 | 1.246 | TRUE | 6949 | -0.47 | -1.59 | 0.69 |
| Men, deaths 1975-2020 (CenSoc-DMF) | 1975-2005 | Industrial land within 250 m, 1937 (per 10 points) | 0.995 | 0.964 | 1.027 | TRUE | 6949 | 0.04 | -0.20 | 0.27 |
| Men, deaths 1975-2020 (CenSoc-DMF) | 1975-2005 | Hazardous trade within 500 m (to 1940) | 1.005 | 0.930 | 1.087 | TRUE | 6949 | -0.04 | -0.61 | 0.55 |
| Men, deaths 1975-2020 (CenSoc-DMF) | 1975-2005 | HOLC grade D (vs A/B) | 1.090 | 0.951 | 1.250 | TRUE | 6949 | -0.63 | -1.59 | 0.37 |
| Men, deaths 1975-2020 (CenSoc-DMF) | 1975-2005 | Placebo: commercial land within 250 m (per 10 points) | 1.009 | 0.994 | 1.025 | TRUE | 6949 | -0.07 | -0.19 | 0.05 |
| Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) | 1988-2005 | 1929 industrial district | 1.120 | 0.943 | 1.330 | TRUE | 13376 | -0.81 | -1.99 | 0.43 |
| Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) | 1988-2005 | Industrial land within 250 m, 1937 (per 10 points) | 1.013 | 0.977 | 1.050 | TRUE | 13376 | -0.09 | -0.35 | 0.17 |
| Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) | 1988-2005 | Hazardous trade within 500 m (to 1940) | 1.026 | 0.942 | 1.117 | TRUE | 13376 | -0.18 | -0.80 | 0.44 |
| Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) | 1988-2005 | HOLC grade D (vs A/B) | 0.983 | 0.850 | 1.136 | TRUE | 13376 | 0.12 | -0.87 | 1.16 |
| Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) | 1988-2005 | Placebo: commercial land within 250 m (per 10 points) | 0.995 | 0.978 | 1.013 | TRUE | 13376 | 0.03 | -0.09 | 0.16 |

## 7. Highways and displacement

| address | residents_1940 | pct_hispanic | pct_black | pct_foreign_born | pct_owner |
|---|---|---|---|---|---|
| elsewhere | 197183 | 3.8 | 2.8 | 7.4 | 46.3 |
| 75-500 m from a later freeway | 31971 | 4.9 | 0.2 | 9.8 | 50.0 |
| in a later freeway's path (within 75 m) | 3071 | 14.8 | 0.4 | 10.5 | 46.8 |
| on land cleared by 1977 (USGS) | 3657 | 2.1 | 2.2 | 10.4 | 46.4 |

| term | ed_fixed_effects | years | lo | hi | p | n | n_exposed | people |
|---|---|---|---|---|---|---|---|---|
| 1940 address in a later freeway's path (within 75 m) | FALSE | -0.090 | -1.407 | 1.228 | 0.8940 | 8390 | 140 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address in a later freeway's path (within 75 m) | TRUE | 0.062 | -0.999 | 1.122 | 0.9090 | 8390 | 140 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address 75-500 m from a later freeway (traffic, not cleared) | FALSE | -0.166 | -0.738 | 0.406 | 0.5690 | 8390 | 1320 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address 75-500 m from a later freeway (traffic, not cleared) | TRUE | 0.400 | -0.347 | 1.148 | 0.2940 | 8390 | 1320 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address on residential land cleared by 1977 | FALSE | -0.096 | -1.613 | 1.420 | 0.9010 | 8390 | 150 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address on residential land cleared by 1977 | TRUE | 0.204 | -1.631 | 2.039 | 0.8280 | 8390 | 150 | Men, deaths 1975-2020 (CenSoc-DMF) |
| in a freeway's path or cleared | FALSE | -0.159 | -1.245 | 0.926 | 0.7740 | 8390 | 276 | Men, deaths 1975-2020 (CenSoc-DMF) |
| in a freeway's path or cleared | TRUE | 0.074 | -1.086 | 1.234 | 0.9000 | 8390 | 276 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address within 100 m of a major road open in 1940 | FALSE | 0.791 | -1.871 | 3.452 | 0.5600 | 8390 | 176 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address within 100 m of a major road open in 1940 | TRUE | 0.232 | -2.225 | 2.689 | 0.8530 | 8390 | 176 | Men, deaths 1975-2020 (CenSoc-DMF) |
| 1940 address in a later freeway's path (within 75 m) | FALSE | -0.318 | -1.009 | 0.373 | 0.3680 | 13376 | 209 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address in a later freeway's path (within 75 m) | TRUE | -0.229 | -0.986 | 0.528 | 0.5530 | 13376 | 209 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address 75-500 m from a later freeway (traffic, not cleared) | FALSE | 0.114 | -0.174 | 0.402 | 0.4380 | 13376 | 2065 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address 75-500 m from a later freeway (traffic, not cleared) | TRUE | -0.034 | -0.452 | 0.384 | 0.8740 | 13376 | 2065 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address on residential land cleared by 1977 | FALSE | -0.339 | -1.182 | 0.503 | 0.4300 | 13376 | 244 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address on residential land cleared by 1977 | TRUE | -0.352 | -1.344 | 0.639 | 0.4860 | 13376 | 244 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| in a freeway's path or cleared | FALSE | -0.357 | -0.916 | 0.202 | 0.2110 | 13376 | 438 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| in a freeway's path or cleared | TRUE | -0.315 | -0.958 | 0.328 | 0.3360 | 13376 | 438 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address within 100 m of a major road open in 1940 | FALSE | -0.506 | -1.079 | 0.066 | 0.0832 | 13376 | 232 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
| 1940 address within 100 m of a major road open in 1940 | TRUE | -0.317 | -1.103 | 0.468 | 0.4290 | 13376 | 232 | Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident) |
