# Geocoding validation

## Distance to EPA Facility Registry coordinates for identical addresses

| geocode_level   |    n |   median_m |   p75_m |   p90_m |   within_100m |   within_250m |   over_1km |
|:----------------|-----:|-----------:|--------:|--------:|--------------:|--------------:|-----------:|
| address         | 1224 |         48 |     110 |     305 |         0.728 |         0.877 |      0.029 |
| address_approx  |   96 |        131 |     429 |     943 |         0.417 |         0.625 |      0.104 |

FRS coordinates have their own error (often 30-100 m), so these distances overstate our error somewhat; addresses that also appear in FRS are cleaner than average, so they may understate it.

## Geocode level by edition (share of listings)

|   year |   listings |   address |   address_approx |   city_centroid |   none |   zip_centroid |
|-------:|-----------:|----------:|-----------------:|----------------:|-------:|---------------:|
|   1965 |       2411 |     0.216 |            0.123 |           0.506 |  0.098 |          0.056 |
|   1966 |       2703 |     0.467 |            0.09  |           0.075 |  0.014 |          0.354 |
|   1967 |       2670 |     0.374 |            0.147 |           0.128 |  0.021 |          0.33  |
|   1968 |       2942 |     0.405 |            0.165 |           0.081 |  0.024 |          0.325 |
|   1970 |       3004 |     0.397 |            0.112 |           0.085 |  0.033 |          0.373 |
|   1973 |       3236 |     0.557 |            0.123 |           0.049 |  0.005 |          0.267 |
|   1974 |       3293 |     0.513 |            0.139 |           0.052 |  0.036 |          0.26  |
|   1977 |       3588 |     0.508 |            0.132 |           0.047 |  0.015 |          0.298 |
|   1980 |       3957 |     0.536 |            0.154 |           0.033 |  0.017 |          0.26  |
|   1983 |       4462 |     0.59  |            0.141 |           0.028 |  0.007 |          0.234 |
|   1988 |       4179 |     0.432 |            0.143 |           0.13  |  0.109 |          0.186 |
|   1990 |       4487 |     0.651 |            0.124 |           0.071 |  0.024 |          0.13  |
|   1992 |       3876 |     0.296 |            0.103 |           0.289 |  0.098 |          0.214 |
