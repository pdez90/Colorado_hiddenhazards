# Residential histories of Denver's 1940 residents (IPUMS MLP)

## Persistence

| address_1940 | census | residents_1940 | pct_linked | pct_in_denver_then_of_linked | pct_within_100m_of_1940_address | pct_within_1km | pct_near_hazardous_trade_then | pct_in_top_quarter_then |
|---|---|---|---|---|---|---|---|---|
| other 1940 addresses | 1910 | 114394 | 25.6 | 72.7 | 14.6 | 31.9 | 2.9 | 16.7 |
| 1929 industrial district | 1910 | 5920 | 21.0 | 70.8 | 23.5 | 50.9 | 7.3 | 25.0 |
| 10%+ industrial land within 250 m | 1910 | 7268 | 20.8 | 72.2 | 29.4 | 57.2 | 7.1 | 24.3 |
| other 1940 addresses | 1920 | 147543 | 36.4 | 77.6 | 22.1 | 40.2 | 27.8 | 10.1 |
| 1929 industrial district | 1920 | 7925 | 31.5 | 74.8 | 33.5 | 54.4 | 33.5 | 10.1 |
| 10%+ industrial land within 250 m | 1920 | 9744 | 30.7 | 75.8 | 34.9 | 63.7 | 37.1 | 18.5 |
| other 1940 addresses | 1930 | 179859 | 57.2 | 87.7 | 37.4 | 55.4 | 15.6 | 16.3 |
| 1929 industrial district | 1930 | 10491 | 53.2 | 84.2 | 40.3 | 60.2 | 22.2 | 19.2 |
| 10%+ industrial land within 250 m | 1930 | 12396 | 49.8 | 83.3 | 41.1 | 66.8 | 25.5 | 28.7 |

## Hazardous trades listed in each census window

| census | window | hazardous_sites_listed | directory_years_with_a_denver_listing | pct_residents_within_500m | comparable |
|---|---|---|---|---|---|
| 1910 | 1901-1910 | 6 | 1910 | 7.6 | FALSE |
| 1920 | 1911-1920 | 137 | 1911 1912 1913 1914 1915 1916 1917 1920 | 40.5 | TRUE |
| 1930 | 1921-1930 | 31 | 1927 1929 | 23.1 | TRUE |
| 1940 | 1931-1940 | 52 | 1932 1933 1935 1939 | 20.4 | TRUE |

## Age at death and exposure over the life course (years, 95% CI)

| model | term | years | lo | hi | p | n | people |
|---|---|---|---|---|---|---|---|
| Mean within-census percentile of hazardous-trade exposure, 1910-1940 (per 10 points), people traced to an earlier Denver address | mean_pct10 | -0.070 | -0.244 | 0.105 | 0.435 | 4005 | Men, deaths 1975-2020 |
| Share of observed censuses (1910-1940) in that census's top quarter of exposure | top_share | -0.138 | -1.463 | 1.187 | 0.838 | 4005 | Men, deaths 1975-2020 |
| Mean within-census percentile, only censuses whose directory window lists 20+ sites (1920, 1930, 1940) | mean_pct10_good | -0.070 | -0.243 | 0.104 | 0.432 | 3962 | Men, deaths 1975-2020 |
| 1940 address only, within-census percentile (per 10 points), same people (comparison) | pct40_10 | -0.085 | -0.225 | 0.054 | 0.230 | 4005 | Men, deaths 1975-2020 |
| Raw count of censuses within 500 m of a listed hazardous trade (depends on which directory years survive) | censuses_near_haz | 0.039 | -0.457 | 0.534 | 0.879 | 4005 | Men, deaths 1975-2020 |
| Childhood address (ages 0-14, 1910-1930), within-census percentile per 10 points, with the 1940 address | child_pct10 | 0.025 | -0.187 | 0.238 | 0.814 | 2370 | Men, deaths 1975-2020 |
| 1940 address, with the childhood address | pct40_10 | -0.128 | -0.345 | 0.089 | 0.248 | 2370 | Men, deaths 1975-2020 |
| Mean within-census percentile of hazardous-trade exposure, 1910-1940 (per 10 points), people traced to an earlier Denver address | mean_pct10 | -0.035 | -0.115 | 0.045 | 0.393 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Share of observed censuses (1910-1940) in that census's top quarter of exposure | top_share | -0.401 | -1.012 | 0.209 | 0.197 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Mean within-census percentile, only censuses whose directory window lists 20+ sites (1920, 1930, 1940) | mean_pct10_good | -0.033 | -0.113 | 0.047 | 0.416 | 5944 | Men and women, deaths at 65+ 1988-2005 |
| 1940 address only, within-census percentile (per 10 points), same people (comparison) | pct40_10 | -0.008 | -0.072 | 0.056 | 0.812 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Raw count of censuses within 500 m of a listed hazardous trade (depends on which directory years survive) | censuses_near_haz | -0.115 | -0.387 | 0.158 | 0.409 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Childhood address (ages 0-14, 1910-1930), within-census percentile per 10 points, with the 1940 address | child_pct10 | 0.005 | -0.068 | 0.077 | 0.898 | 5001 | Men and women, deaths at 65+ 1988-2005 |
| 1940 address, with the childhood address | pct40_10 | -0.022 | -0.099 | 0.055 | 0.579 | 5001 | Men and women, deaths at 65+ 1988-2005 |
