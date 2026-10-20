# Residential histories of Denver's 1940 residents (IPUMS MLP)

## Persistence

| address_1940 | census | residents_1940 | pct_linked | pct_in_denver_then_of_linked | pct_within_100m_of_1940_address | pct_within_1km | pct_near_hazardous_trade_then |
|---|---|---|---|---|---|---|---|
| other 1940 addresses | 1910 | 114276 | 25.5 | 54.2 | 14.5 | 31.8 | 3.4 |
| 1929 industrial district | 1910 | 6023 | 21.2 | 47.8 | 24.9 | 52.0 | 6.1 |
| 10%+ industrial land within 250 m | 1910 | 7283 | 21.5 | 50.4 | 30.0 | 56.9 | 8.1 |
| other 1940 addresses | 1920 | 147317 | 36.4 | 61.7 | 22.0 | 40.1 | 28.6 |
| 1929 industrial district | 1920 | 8110 | 31.0 | 57.6 | 35.0 | 56.5 | 31.8 |
| 10%+ industrial land within 250 m | 1920 | 9785 | 31.9 | 61.0 | 34.8 | 62.9 | 42.2 |
| other 1940 addresses | 1930 | 179604 | 57.1 | 77.4 | 37.4 | 55.3 | 12.0 |
| 1929 industrial district | 1930 | 10665 | 52.5 | 65.7 | 40.7 | 61.9 | 19.6 |
| 10%+ industrial land within 250 m | 1930 | 12477 | 51.4 | 72.8 | 41.4 | 66.3 | 21.3 |

## Age at death and exposure over the life course (years, 95% CI)

| model | term | years | lo | hi | p | n | people |
|---|---|---|---|---|---|---|---|
| Censuses (1910-1940) living within 500 m of a hazardous trade, people traced to an earlier Denver address | censuses_near_haz | -0.154 | -0.588 | 0.280 | 0.4860 | 4005 | Men, deaths 1975-2020 |
| 1940 address only, same people (comparison) | haz_500 | -0.553 | -1.289 | 0.183 | 0.1410 | 4005 | Men, deaths 1975-2020 |
| Childhood address (ages 0-14, 1910-1930) within 500 m of a hazardous trade, with the 1940 address | child_haz_500 | 0.807 | -0.421 | 2.034 | 0.1980 | 2370 | Men, deaths 1975-2020 |
| 1940 address, with the childhood address | haz_500 | -0.955 | -1.999 | 0.088 | 0.0729 | 2370 | Men, deaths 1975-2020 |
| Censuses (1910-1940) living within 500 m of a hazardous trade, people traced to an earlier Denver address | censuses_near_haz | -0.121 | -0.351 | 0.109 | 0.3040 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| 1940 address only, same people (comparison) | haz_500 | -0.131 | -0.476 | 0.213 | 0.4550 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Childhood address (ages 0-14, 1910-1930) within 500 m of a hazardous trade, with the 1940 address | child_haz_500 | -0.081 | -0.536 | 0.374 | 0.7270 | 5001 | Men and women, deaths at 65+ 1988-2005 |
| 1940 address, with the childhood address | haz_500 | -0.238 | -0.615 | 0.138 | 0.2140 | 5001 | Men and women, deaths at 65+ 1988-2005 |
