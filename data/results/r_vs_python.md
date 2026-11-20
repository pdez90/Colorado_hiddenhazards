# R vs Python

## Sites (R/build_sites.R vs pipeline/build_sites.py + finalize.py)

* sites: Python 7,978, R 7,978, identical membership 7,978
* hazardous-sector sites with the same inventory status: 3,129 of 3,129
* same confidence class: 3,129 of 3,129
* max coordinate difference: 0.000 m

## Exposures (R/build_exposures.R vs pipeline/health/build_exposures.py; not rerun here: restricted inputs)

* block groups: Python 4,058, R 4,058, matched 4,058; 18 exposure columns; largest absolute difference 2e-10

## Tract models (R/health_models.R vs pipeline/health/health_models.py)

77 model rows compared; largest absolute difference per quantity:

| quantity | max abs diff | max abs value |
|---|---|---|
| n | 0 | 1.43e+03 |
| r2_ols | 0 | 0.732 |
| aic_sem | 0 | 1.2e+04 |
| lambda_sem | 0 | 0.75 |
| z_hidden_b | 0 | 0.851 |
| z_hidden_se | 0 | 0.923 |
| z_hidden_p | 0 | 0.993 |
| z_hidden_b_ols | 0 | 1.23 |
| z_known_hist_b | 0 | 1.91 |
| z_placebo_b | 0 | 3.41 |
| lr | 0 | 63.2 |

## Block-group mortality (R/mortality_bg.R vs pipeline/health/mortality_bg.py)

14 model rows compared; largest absolute difference per quantity:

| quantity | max abs diff | max abs value |
|---|---|---|
| n | 0 | 3.44e+03 |
| deaths | 0 | 1.79e+05 |
| alpha | 0 | 0.265 |
| aic | 0 | 3.14e+04 |
| z_hidden_rr | 0 | 1.04 |
| z_hidden_lo | 0 | 1 |
| z_hidden_hi | 0 | 1.07 |
| z_hidden_p | 0 | 0.186 |
| z_placebo_rr | 0 | 1.06 |
| z_known_hist_rr | 0 | 1.03 |

