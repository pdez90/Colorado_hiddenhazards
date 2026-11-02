# Residential histories of Denver's 1940 residents (IPUMS MLP)

## Persistence

| address_1940 | census | residents_1940 | pct_linked | pct_in_denver_then_of_linked | pct_within_100m_of_1940_address | pct_within_1km | pct_near_hazardous_trade_then | pct_in_top_quarter_then |
|---|---|---|---|---|---|---|---|---|
| other 1940 addresses | 1910 | 114394 | 25.6 | 72.7 | 14.6 | 31.9 | 2.3 | 17.6 |
| 1929 industrial district | 1910 | 5920 | 21.0 | 70.8 | 23.5 | 50.9 | 6.8 | 27.9 |
| 10%+ industrial land within 250 m | 1910 | 7268 | 20.8 | 72.2 | 29.4 | 57.2 | 6.0 | 31.9 |
| other 1940 addresses | 1920 | 147543 | 36.4 | 77.6 | 22.1 | 40.2 | 13.4 | 10.5 |
| 1929 industrial district | 1920 | 7925 | 31.5 | 74.8 | 33.5 | 54.4 | 19.1 | 11.5 |
| 10%+ industrial land within 250 m | 1920 | 9744 | 30.7 | 75.8 | 34.9 | 63.7 | 24.4 | 21.1 |
| other 1940 addresses | 1930 | 179859 | 57.2 | 87.7 | 37.4 | 55.4 | 7.5 | 14.9 |
| 1929 industrial district | 1930 | 10491 | 53.2 | 84.2 | 40.3 | 60.2 | 18.4 | 32.9 |
| 10%+ industrial land within 250 m | 1930 | 12396 | 49.8 | 83.3 | 41.1 | 66.8 | 18.8 | 35.2 |

## Hazardous trades listed in each census window

| census | window | hazardous_sites_listed | directory_years_with_a_denver_listing | pct_residents_within_500m | comparable |
|---|---|---|---|---|---|
| 1910 | 1901-1910 | 4 | 1910 | 5.5 | FALSE |
| 1920 | 1911-1920 | 98 | 1911 1912 1913 1914 1915 1916 1917 1920 | 26.9 | TRUE |
| 1930 | 1921-1930 | 19 | 1927 1929 | 13.1 | FALSE |
| 1940 | 1931-1940 | 39 | 1932 1933 1935 1939 | 14.4 | TRUE |

## Age at death and exposure over the life course (years, 95% CI)

| model | term | years | lo | hi | p | n | people |
|---|---|---|---|---|---|---|---|
| Mean within-census percentile of hazardous-trade exposure, 1910-1940 (per 10 points), people traced to an earlier Denver address | mean_pct10 | -0.113 | -0.297 | 0.071 | 0.2290 | 4005 | Men, deaths 1975-2020 |
| Share of observed censuses (1910-1940) in that census's top quarter of exposure | top_share | -0.935 | -2.142 | 0.272 | 0.1290 | 4005 | Men, deaths 1975-2020 |
| Mean within-census percentile, only censuses whose directory window lists 20+ sites (1920, 1940) | mean_pct10_good | 0.209 | -0.025 | 0.443 | 0.0797 | 1448 | Men, deaths 1975-2020 |
| 1940 address only, within-census percentile (per 10 points), same people (comparison) | pct40_10 | -0.143 | -0.270 | -0.015 | 0.0285 | 4005 | Men, deaths 1975-2020 |
| Raw count of censuses within 500 m of a listed hazardous trade (depends on which directory years survive) | censuses_near_haz | 0.065 | -0.605 | 0.736 | 0.8480 | 4005 | Men, deaths 1975-2020 |
| Childhood address (ages 0-14, 1910-1930), within-census percentile per 10 points, with the 1940 address | child_pct10 | 0.044 | -0.138 | 0.227 | 0.6340 | 2370 | Men, deaths 1975-2020 |
| 1940 address, with the childhood address | pct40_10 | -0.194 | -0.371 | -0.017 | 0.0322 | 2370 | Men, deaths 1975-2020 |
| Mean within-census percentile of hazardous-trade exposure, 1910-1940 (per 10 points), people traced to an earlier Denver address | mean_pct10 | 0.009 | -0.067 | 0.085 | 0.8170 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Share of observed censuses (1910-1940) in that census's top quarter of exposure | top_share | -0.261 | -0.851 | 0.328 | 0.3850 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Mean within-census percentile, only censuses whose directory window lists 20+ sites (1920, 1940) | mean_pct10_good | 0.018 | -0.142 | 0.178 | 0.8260 | 1546 | Men and women, deaths at 65+ 1988-2005 |
| 1940 address only, within-census percentile (per 10 points), same people (comparison) | pct40_10 | 0.028 | -0.040 | 0.095 | 0.4240 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Raw count of censuses within 500 m of a listed hazardous trade (depends on which directory years survive) | censuses_near_haz | -0.015 | -0.355 | 0.325 | 0.9300 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Childhood address (ages 0-14, 1910-1930), within-census percentile per 10 points, with the 1940 address | child_pct10 | 0.007 | -0.067 | 0.080 | 0.8610 | 5001 | Men and women, deaths at 65+ 1988-2005 |
| 1940 address, with the childhood address | pct40_10 | 0.002 | -0.082 | 0.086 | 0.9650 | 5001 | Men and women, deaths at 65+ 1988-2005 |
