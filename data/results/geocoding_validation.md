# Geocoding validation

## Distance to EPA Facility Registry coordinates for identical addresses

| geocode_level   |    n |   median_m |   p75_m |   p90_m |   within_100m |   within_250m |   over_1km |
|:----------------|-----:|-----------:|--------:|--------:|--------------:|--------------:|-----------:|
| address         | 1237 |         48 |     111 |     311 |         0.724 |         0.876 |      0.031 |
| address_approx  |   98 |        131 |     474 |    1116 |         0.408 |         0.612 |      0.112 |

FRS coordinates have their own error (often 30-100 m), so these distances overstate our error somewhat; addresses that also appear in FRS are cleaner than average, so they may understate it.

## Geocode level by edition (share of listings)

|   year |   listings |   address |   address_approx |   city_centroid |   none |   zip_centroid |
|-------:|-----------:|----------:|-----------------:|----------------:|-------:|---------------:|
|   1965 |       3127 |     0.324 |            0.092 |           0.486 |  0.027 |          0.071 |
|   1966 |       2908 |     0.488 |            0.104 |           0.048 |  0.004 |          0.356 |
|   1967 |       2927 |     0.412 |            0.128 |           0.111 |  0.013 |          0.335 |
|   1968 |       3043 |     0.423 |            0.141 |           0.078 |  0.024 |          0.335 |
|   1970 |       2842 |     0.484 |            0.11  |           0.047 |  0.023 |          0.336 |
|   1973 |       3223 |     0.581 |            0.117 |           0.036 |  0.005 |          0.261 |
|   1974 |       3310 |     0.536 |            0.127 |           0.045 |  0.034 |          0.257 |
|   1977 |       3482 |     0.544 |            0.123 |           0.034 |  0.012 |          0.286 |
|   1980 |       3946 |     0.56  |            0.139 |           0.029 |  0.018 |          0.254 |
|   1983 |       4381 |     0.611 |            0.135 |           0.019 |  0.006 |          0.229 |
|   1988 |       4168 |     0.492 |            0.155 |           0.055 |  0.106 |          0.193 |
|   1990 |       4487 |     0.651 |            0.125 |           0.093 |  0.001 |          0.13  |
|   1992 |       3874 |     0.303 |            0.095 |           0.381 |  0.005 |          0.216 |
