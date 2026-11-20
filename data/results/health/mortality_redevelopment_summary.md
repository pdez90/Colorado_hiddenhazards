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
| hidden | 231 | 10 | 13 | 208 |
| known | 738 | 44 | 31 | 663 |
| pre1960 | 380 | 51 | 109 | 220 |

## Rate ratio per SD of nearby sites still standing (block and year fixed effects)

| model | outcome | term | rr | lo | hi | p | n_obs |
|---|---|---|---|---|---|---|---|
| All three groups together | deaths_nat | hidden | 1.1337 | 0.8061 | 1.5944 | 0.471 | 156400 |
| All three groups together | deaths_nat | known | 0.8485 | 0.5157 | 1.3962 | 0.518 | 156400 |
| All three groups together | deaths_nat | pre1960 | 1.0612 | 0.8341 | 1.3501 | 0.629 | 156400 |
| One group: hidden | deaths_nat | hidden | 1.1018 | 0.7822 | 1.5521 | 0.579 | 156400 |
| One group: known | deaths_nat | known | 0.9052 | 0.5914 | 1.3855 | 0.646 | 156400 |
| One group: pre1960 | deaths_nat | pre1960 | 0.9699 | 0.7319 | 1.2854 | 0.832 | 156400 |
| All three groups together | deaths_all | hidden | 1.1508 | 0.8265 | 1.6023 | 0.406 | 159360 |
| All three groups together | deaths_all | known | 0.7251 | 0.4250 | 1.2369 | 0.238 | 159360 |
| All three groups together | deaths_all | pre1960 | 1.1274 | 0.8843 | 1.4372 | 0.333 | 159360 |
| One group: hidden | deaths_all | hidden | 1.0880 | 0.7715 | 1.5341 | 0.631 | 159360 |
| One group: known | deaths_all | known | 0.8115 | 0.5176 | 1.2721 | 0.362 | 159360 |
| One group: pre1960 | deaths_all | pre1960 | 0.9359 | 0.6898 | 1.2699 | 0.671 | 159360 |

## Event study (rate ratio relative to the year before the rebuild)

| outcome | years_since_rebuild | rr | lo | hi | p | n_obs | rebuilt_blocks | comparison_blocks |
|---|---|---|---|---|---|---|---|---|
| deaths_nat | -4 or earlier | 0.9505 | 0.7508 | 1.2035 | 0.6730 | 51280 | 754 | 2889 |
| deaths_nat | -3 | 0.9619 | 0.7742 | 1.1951 | 0.7260 | 51280 | 754 | 2889 |
| deaths_nat | -2 | 0.9658 | 0.8136 | 1.1466 | 0.6910 | 51280 | 754 | 2889 |
| deaths_nat | 0 | 0.8794 | 0.7094 | 1.0901 | 0.2410 | 51280 | 754 | 2889 |
| deaths_nat | 1 | 0.8793 | 0.7166 | 1.0790 | 0.2180 | 51280 | 754 | 2889 |
| deaths_nat | 2 | 0.7859 | 0.6243 | 0.9895 | 0.0404 | 51280 | 754 | 2889 |
| deaths_nat | 3 | 0.9790 | 0.7849 | 1.2211 | 0.8510 | 51280 | 754 | 2889 |
| deaths_nat | 4 or later | 0.9685 | 0.7905 | 1.1866 | 0.7570 | 51280 | 754 | 2889 |
| deaths_all | -4 or earlier | 0.9830 | 0.7789 | 1.2407 | 0.8850 | 52300 | 754 | 2889 |
| deaths_all | -3 | 0.9776 | 0.7845 | 1.2182 | 0.8400 | 52300 | 754 | 2889 |
| deaths_all | -2 | 0.9424 | 0.8039 | 1.1046 | 0.4640 | 52300 | 754 | 2889 |
| deaths_all | 0 | 0.8955 | 0.7219 | 1.1110 | 0.3160 | 52300 | 754 | 2889 |
| deaths_all | 1 | 0.8933 | 0.7323 | 1.0897 | 0.2660 | 52300 | 754 | 2889 |
| deaths_all | 2 | 0.8205 | 0.6622 | 1.0167 | 0.0705 | 52300 | 754 | 2889 |
| deaths_all | 3 | 1.0423 | 0.8488 | 1.2799 | 0.6930 | 52300 | 754 | 2889 |
| deaths_all | 4 or later | 1.0178 | 0.8447 | 1.2265 | 0.8530 | 52300 | 754 | 2889 |
