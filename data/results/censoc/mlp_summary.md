# Residential histories of Denver's 1940 residents (IPUMS MLP)

## Persistence

| address_1940 | census | residents_1940 | pct_linked | pct_in_denver_then_of_linked | pct_within_100m_of_1940_address | pct_within_1km | pct_near_hazardous_trade_then | pct_in_top_quarter_then |
|---|---|---|---|---|---|---|---|---|
| other 1940 addresses | 1910 | 114276 | 25.5 | 72.7 | 14.5 | 31.8 | 3.4 | 17.1 |
| 1929 industrial district | 1910 | 6023 | 21.2 | 70.3 | 24.9 | 52.0 | 6.1 | 22.4 |
| 10%+ industrial land within 250 m | 1910 | 7283 | 21.5 | 72.3 | 30.0 | 56.9 | 8.1 | 23.8 |
| other 1940 addresses | 1920 | 147317 | 36.4 | 77.6 | 22.0 | 40.1 | 28.6 | 10.5 |
| 1929 industrial district | 1920 | 8110 | 31.0 | 75.3 | 35.0 | 56.5 | 31.8 | 11.2 |
| 10%+ industrial land within 250 m | 1920 | 9785 | 31.9 | 75.8 | 34.8 | 62.9 | 42.2 | 18.9 |
| other 1940 addresses | 1930 | 179604 | 57.1 | 87.7 | 37.4 | 55.3 | 12.0 | 15.7 |
| 1929 industrial district | 1930 | 10665 | 52.5 | 83.5 | 40.7 | 61.9 | 19.6 | 20.1 |
| 10%+ industrial land within 250 m | 1930 | 12477 | 51.4 | 84.0 | 41.4 | 66.3 | 21.3 | 30.6 |

## Hazardous trades listed in each census window

| census | window | hazardous_sites_listed | directory_years_with_a_denver_listing | pct_residents_within_500m | comparable |
|---|---|---|---|---|---|
| 1910 | 1901-1910 | 5 | 1910 |  | FALSE |
| 1920 | 1911-1920 | 103 | 1911 1912 1913 1914 1915 1916 1917 1920 |  | TRUE |
| 1930 | 1921-1930 | 21 | 1927 1929 |  | TRUE |
| 1940 | 1931-1940 | 43 | 1932 1933 1935 1939 | 21.7 | TRUE |

## Age at death and exposure over the life course (years, 95% CI)

| model | term | years | lo | hi | p | n | people |
|---|---|---|---|---|---|---|---|
| Mean within-census percentile of hazardous-trade exposure, 1910-1940 (per 10 points), people traced to an earlier Denver address | mean_pct10 | -0.081 | -0.256 | 0.094 | 0.366 | 4005 | Men, deaths 1975-2020 |
| Share of observed censuses (1910-1940) in that census's top quarter of exposure | top_share | -0.596 | -1.907 | 0.716 | 0.373 | 4005 | Men, deaths 1975-2020 |
| Mean within-census percentile, only censuses whose directory window lists 20+ sites (1920, 1930, 1940) | mean_pct10_good | -0.080 | -0.254 | 0.093 | 0.366 | 3962 | Men, deaths 1975-2020 |
| 1940 address only, within-census percentile (per 10 points), same people (comparison) | pct40_10 | -0.086 | -0.222 | 0.051 | 0.218 | 4005 | Men, deaths 1975-2020 |
| Raw count of censuses within 500 m of a listed hazardous trade (depends on which directory years survive) | censuses_near_haz | -0.060 | -0.547 | 0.427 | 0.809 | 4005 | Men, deaths 1975-2020 |
| Childhood address (ages 0-14, 1910-1930), within-census percentile per 10 points, with the 1940 address | child_pct10 | 0.018 | -0.192 | 0.228 | 0.869 | 2370 | Men, deaths 1975-2020 |
| 1940 address, with the childhood address | pct40_10 | -0.129 | -0.337 | 0.080 | 0.226 | 2370 | Men, deaths 1975-2020 |
| Mean within-census percentile of hazardous-trade exposure, 1910-1940 (per 10 points), people traced to an earlier Denver address | mean_pct10 | -0.038 | -0.117 | 0.041 | 0.346 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Share of observed censuses (1910-1940) in that census's top quarter of exposure | top_share | -0.363 | -0.937 | 0.210 | 0.214 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Mean within-census percentile, only censuses whose directory window lists 20+ sites (1920, 1930, 1940) | mean_pct10_good | -0.037 | -0.116 | 0.042 | 0.361 | 5944 | Men and women, deaths at 65+ 1988-2005 |
| 1940 address only, within-census percentile (per 10 points), same people (comparison) | pct40_10 | -0.009 | -0.073 | 0.055 | 0.779 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Raw count of censuses within 500 m of a listed hazardous trade (depends on which directory years survive) | censuses_near_haz | -0.118 | -0.398 | 0.161 | 0.408 | 5956 | Men and women, deaths at 65+ 1988-2005 |
| Childhood address (ages 0-14, 1910-1930), within-census percentile per 10 points, with the 1940 address | child_pct10 | 0.001 | -0.069 | 0.071 | 0.985 | 5001 | Men and women, deaths at 65+ 1988-2005 |
| 1940 address, with the childhood address | pct40_10 | -0.021 | -0.097 | 0.055 | 0.591 | 5001 | Men and women, deaths at 65+ 1988-2005 |
