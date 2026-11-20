# Residential histories of Denver's 1940 residents (IPUMS MLP)

## Persistence

| address_1940 | census | residents_1940 | pct_linked | pct_in_denver_then_of_linked | pct_within_100m_of_1940_address | pct_within_1km | pct_near_hazardous_trade_then | pct_in_top_quarter_then |
|---|---|---|---|---|---|---|---|---|
| other 1940 addresses | 1910 | 114394 | 25.6 | 72.7 | 14.6 | 31.9 | 12.0 | 17.1 |
| 1929 industrial district | 1910 | 5920 | 21.0 | 70.8 | 23.5 | 50.9 | 19.1 | 24.9 |
| 10%+ industrial land within 250 m | 1910 | 7268 | 20.8 | 72.2 | 29.4 | 57.2 | 27.0 | 33.5 |
| other 1940 addresses | 1920 | 147543 | 36.4 | 77.6 | 22.1 | 40.2 | 17.4 | 10.5 |
| 1929 industrial district | 1920 | 7925 | 31.5 | 74.8 | 33.5 | 54.4 | 25.9 | 11.4 |
| 10%+ industrial land within 250 m | 1920 | 9744 | 30.7 | 75.8 | 34.9 | 63.7 | 32.5 | 21.0 |
| other 1940 addresses | 1930 | 179859 | 57.2 | 87.7 | 37.4 | 55.4 | 15.8 | 15.2 |
| 1929 industrial district | 1930 | 10491 | 53.2 | 84.2 | 40.3 | 60.2 | 35.1 | 27.8 |
| 10%+ industrial land within 250 m | 1930 | 12396 | 49.8 | 83.3 | 41.1 | 66.8 | 31.4 | 31.9 |

## Hazardous trades listed in each census window

| census | window | hazardous_sites_listed | directory_years_with_a_denver_listing | pct_residents_within_500m | comparable |
|---|---|---|---|---|---|
| 1910 | 1901-1910 | 22 | 1910 | 18.3 | TRUE |
| 1920 | 1911-1920 | 146 | 1911 1912 1913 1914 1915 1916 1917 1920 | 30.7 | TRUE |
| 1930 | 1921-1930 | 51 | 1927 1929 | 24.2 | TRUE |
| 1940 | 1931-1940 | 81 | 1932 1933 1935 1939 | 23.1 | TRUE |

## Age at death and exposure over the life course (years, 95% CI)

| model | term | years | lo | hi | p | n | people |
|---|---|---|---|---|---|---|---|
| Mean within-census percentile of hazardous-trade exposure, 1910-1940 (per 10 points), people traced to an earlier Denver address | mean_pct10 | -0.010 | -0.207 | 0.187 | 0.9230 | 4005 | Men, deaths 1975-2020 |
| Share of observed censuses (1910-1940) in that census's top quarter of exposure | top_share | -0.547 | -1.839 | 0.746 | 0.4070 | 4005 | Men, deaths 1975-2020 |
| Mean within-census percentile, only censuses whose directory window lists 20+ sites (1910, 1920, 1930, 1940) | mean_pct10_good | -0.010 | -0.207 | 0.187 | 0.9230 | 4005 | Men, deaths 1975-2020 |
| 1940 address only, within-census percentile (per 10 points), same people (comparison) | pct40_10 | -0.073 | -0.226 | 0.081 | 0.3560 | 4005 | Men, deaths 1975-2020 |
| Raw count of censuses within 500 m of a listed hazardous trade (depends on which directory years survive) | censuses_near_haz | -0.008 | -0.507 | 0.492 | 0.9760 | 4005 | Men, deaths 1975-2020 |
| Childhood address (ages 0-14, 1910-1930), within-census percentile per 10 points, with the 1940 address | child_pct10 | 0.178 | -0.007 | 0.364 | 0.0593 | 2370 | Men, deaths 1975-2020 |
| 1940 address, with the childhood address | pct40_10 | -0.170 | -0.374 | 0.034 | 0.1030 | 2370 | Men, deaths 1975-2020 |
| Mean within-census percentile of hazardous-trade exposure, 1910-1940 (per 10 points), people traced to an earlier Denver address | mean_pct10 | -0.040 | -0.122 | 0.043 | 0.3440 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Share of observed censuses (1910-1940) in that census's top quarter of exposure | top_share | -0.668 | -1.248 | -0.087 | 0.0242 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Mean within-census percentile, only censuses whose directory window lists 20+ sites (1910, 1920, 1930, 1940) | mean_pct10_good | -0.040 | -0.122 | 0.043 | 0.3440 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| 1940 address only, within-census percentile (per 10 points), same people (comparison) | pct40_10 | -0.014 | -0.083 | 0.055 | 0.6900 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Raw count of censuses within 500 m of a listed hazardous trade (depends on which directory years survive) | censuses_near_haz | -0.238 | -0.516 | 0.039 | 0.0924 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Childhood address (ages 0-14, 1910-1930), within-census percentile per 10 points, with the 1940 address | child_pct10 | -0.003 | -0.080 | 0.075 | 0.9440 | 5001 | Men and women, deaths at 65+ 1988-2005 |
| 1940 address, with the childhood address | pct40_10 | -0.002 | -0.090 | 0.086 | 0.9630 | 5001 | Men and women, deaths at 65+ 1988-2005 |
