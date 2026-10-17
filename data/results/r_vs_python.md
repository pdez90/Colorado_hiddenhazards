# R vs Python

## Sites (R/build_sites.R vs pipeline/build_sites.py + finalize.py)

* sites: Python 9,848, R 9,848, identical membership 9,848
* hazardous-sector sites with the same inventory status: 4,312 of 4,312
* same confidence class: 4,312 of 4,312
* max coordinate difference: 0.000 m

## Exposures (R/build_exposures.R vs pipeline/health/build_exposures.py)

* block groups: Python 4,058, R 4,058, matched 4,058; 18 exposure columns; largest absolute difference 2e-10

## Tract models (R/health_models.R vs pipeline/health/health_models.py)

77 model rows compared; largest absolute difference per quantity:

| quantity | max abs diff | max abs value |
|---|---|---|
| n | 0 | 1.43e+03 |
| r2_ols | 0 | 0.732 |
| aic_sem | 4 | 1.2e+04 |
| lambda_sem | 0 | 0.749 |
| z_hidden_b | 2.8e-07 | 0.866 |
| z_hidden_se | 4.5e-08 | 0.951 |
| z_hidden_p | 1.5e-06 | 0.993 |
| z_hidden_b_ols | 2.7e-12 | 1.65 |
| z_known_hist_b | 5.9e-07 | 1.8 |
| z_placebo_b | 1.6e-06 | 2.54 |
| lr | 0 | 62.7 |

## Block-group mortality (R/mortality_bg.R vs pipeline/health/mortality_bg.py)

14 model rows compared; largest absolute difference per quantity:

| quantity | max abs diff | max abs value |
|---|---|---|
| n | 0 | 3.44e+03 |
| deaths | 0 | 1.79e+05 |
| alpha | 0 | 0.264 |
| aic | 0 | 3.14e+04 |
| z_hidden_rr | 2e-06 | 1 |
| z_hidden_lo | 0.00034 | 0.97 |
| z_hidden_hi | 0.00037 | 1.04 |
| z_hidden_p | 0.0019 | 0.845 |
| z_placebo_rr | 1e-05 | 1.07 |
| z_known_hist_rr | 7.2e-06 | 1.05 |

