# Geocoding validation

## Distance to EPA Facility Registry coordinates for identical addresses

| geocode_level   |    n |   median_m |   p75_m |   p90_m |   within_100m |   within_250m |   over_1km |
|:----------------|-----:|-----------:|--------:|--------:|--------------:|--------------:|-----------:|
| address         | 1229 |         48 |     110 |     307 |         0.728 |         0.877 |      0.029 |
| address_approx  |   96 |        131 |     429 |     943 |         0.417 |         0.625 |      0.104 |

FRS coordinates have their own error (often 30-100 m), so these distances overstate our error somewhat; addresses that also appear in FRS are cleaner than average, so they may understate it.

## Geocode level by edition (share of listings)

|   year |   listings |   address |   address_approx |   city_centroid |   none |   zip_centroid |
|-------:|-----------:|----------:|-----------------:|----------------:|-------:|---------------:|
|   1965 |       3127 |     0.316 |            0.099 |           0.487 |  0.027 |          0.071 |
|   1966 |       2908 |     0.481 |            0.11  |           0.048 |  0.004 |          0.357 |
|   1967 |       2927 |     0.388 |            0.153 |           0.112 |  0.013 |          0.335 |
|   1968 |       3043 |     0.403 |            0.161 |           0.078 |  0.024 |          0.335 |
|   1970 |       2843 |     0.463 |            0.131 |           0.046 |  0.023 |          0.337 |
|   1973 |       3223 |     0.573 |            0.125 |           0.035 |  0.004 |          0.262 |
|   1974 |       3310 |     0.521 |            0.141 |           0.045 |  0.034 |          0.259 |
|   1977 |       3482 |     0.529 |            0.137 |           0.034 |  0.012 |          0.288 |
|   1980 |       3946 |     0.541 |            0.155 |           0.029 |  0.017 |          0.258 |
|   1983 |       4381 |     0.602 |            0.142 |           0.019 |  0.006 |          0.231 |
|   1988 |       4168 |     0.474 |            0.173 |           0.054 |  0.105 |          0.195 |
|   1990 |       4487 |     0.651 |            0.124 |           0.093 |  0.002 |          0.13  |
|   1992 |       3874 |     0.296 |            0.103 |           0.381 |  0.005 |          0.214 |
