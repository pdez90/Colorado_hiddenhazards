# Former hazardous sites, before and after they were rebuilt: block mortality 2000-2019, City and County of Denver

10,531 blocks, 210,427 block-years, 74,776 natural-cause deaths, years 2000-2019.

## Death records matched to 2010 blocks, by year

| year | pct_matched |
|---|---|
| 2000 | 96.1 |
| 2001 | 95.9 |
| 2002 | 95.9 |
| 2003 | 96.3 |
| 2004 | 96.3 |
| 2005 | 95.9 |
| 2006 | 96.7 |
| 2007 | 97 |
| 2008 | 96.9 |
| 2009 | 96.6 |
| 2010 | 96.6 |
| 2011 | 96.5 |
| 2012 | 96 |
| 2013 | 96.2 |
| 2014 | 97 |
| 2015 | 95.5 |
| 2016 | 95.7 |
| 2017 | 94.5 |
| 2018 | 94.9 |
| 2019 | 94.9 |

## Sites

| group | sites | rebuilt_in_window | rebuilt_before | standing_throughout |
|---|---|---|---|---|
| hidden | 235 | 11 | 14 | 210 |
| known | 737 | 44 | 31 | 662 |
| pre1960 | 390 | 52 | 110 | 228 |

## Rate ratio per SD of nearby sites still standing (block and year fixed effects)

| model | outcome | term | rr | lo | hi | p | n_obs |
|---|---|---|---|---|---|---|---|
| All three groups together | deaths_nat | hidden | 1.0583 | 0.7404 | 1.5127 | 0.756 | 156400 |
| All three groups together | deaths_nat | known | 0.8708 | 0.5352 | 1.4167 | 0.577 | 156400 |
| All three groups together | deaths_nat | pre1960 | 1.0528 | 0.8412 | 1.3175 | 0.653 | 156400 |
| One group: hidden | deaths_nat | hidden | 1.0190 | 0.7043 | 1.4743 | 0.921 | 156400 |
| One group: known | deaths_nat | known | 0.9213 | 0.5963 | 1.4235 | 0.712 | 156400 |
| One group: pre1960 | deaths_nat | pre1960 | 0.9736 | 0.7292 | 1.2999 | 0.856 | 156400 |
| All three groups together | deaths_all | hidden | 1.0922 | 0.7794 | 1.5304 | 0.608 | 159360 |
| All three groups together | deaths_all | known | 0.7285 | 0.4261 | 1.2455 | 0.247 | 159360 |
| All three groups together | deaths_all | pre1960 | 1.1299 | 0.9009 | 1.4171 | 0.290 | 159360 |
| One group: hidden | deaths_all | hidden | 1.0025 | 0.7018 | 1.4320 | 0.989 | 159360 |
| One group: known | deaths_all | known | 0.8211 | 0.5163 | 1.3059 | 0.405 | 159360 |
| One group: pre1960 | deaths_all | pre1960 | 0.9380 | 0.6863 | 1.2821 | 0.688 | 159360 |

## Event study (rate ratio relative to the year before the rebuild)

| outcome | years_since_rebuild | rr | lo | hi | p | n_obs | rebuilt_blocks | comparison_blocks |
|---|---|---|---|---|---|---|---|---|
| deaths_nat | -4 or earlier | 0.9520 | 0.7519 | 1.2054 | 0.6830 | 51300 | 760 | 2887 |
| deaths_nat | -3 | 0.9675 | 0.7792 | 1.2015 | 0.7650 | 51300 | 760 | 2887 |
| deaths_nat | -2 | 0.9656 | 0.8134 | 1.1464 | 0.6900 | 51300 | 760 | 2887 |
| deaths_nat | 0 | 0.8793 | 0.7095 | 1.0898 | 0.2400 | 51300 | 760 | 2887 |
| deaths_nat | 1 | 0.8793 | 0.7166 | 1.0790 | 0.2180 | 51300 | 760 | 2887 |
| deaths_nat | 2 | 0.7860 | 0.6243 | 0.9895 | 0.0404 | 51300 | 760 | 2887 |
| deaths_nat | 3 | 0.9791 | 0.7850 | 1.2212 | 0.8510 | 51300 | 760 | 2887 |
| deaths_nat | 4 or later | 0.9696 | 0.7903 | 1.1897 | 0.7680 | 51300 | 760 | 2887 |
| deaths_all | -4 or earlier | 0.9858 | 0.7817 | 1.2432 | 0.9040 | 52340 | 760 | 2887 |
| deaths_all | -3 | 0.9825 | 0.7905 | 1.2210 | 0.8730 | 52340 | 760 | 2887 |
| deaths_all | -2 | 0.9421 | 0.8037 | 1.1043 | 0.4620 | 52340 | 760 | 2887 |
| deaths_all | 0 | 0.8953 | 0.7218 | 1.1106 | 0.3150 | 52340 | 760 | 2887 |
| deaths_all | 1 | 0.8932 | 0.7322 | 1.0896 | 0.2650 | 52340 | 760 | 2887 |
| deaths_all | 2 | 0.8205 | 0.6623 | 1.0166 | 0.0703 | 52340 | 760 | 2887 |
| deaths_all | 3 | 1.0423 | 0.8488 | 1.2798 | 0.6930 | 52340 | 760 | 2887 |
| deaths_all | 4 or later | 1.0195 | 0.8444 | 1.2309 | 0.8410 | 52340 | 760 | 2887 |
