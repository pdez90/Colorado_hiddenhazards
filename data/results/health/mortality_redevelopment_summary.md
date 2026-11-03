# Former hazardous sites, before and after they were rebuilt: block mortality 2000-2019, Denver study area

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
| hidden | 303 | 20 | 21 | 262 |
| known | 809 | 51 | 39 | 719 |
| pre1960 | 266 | 38 | 82 | 146 |

## Rate ratio per SD of nearby sites still standing (block and year fixed effects)

| model | outcome | term | rr | lo | hi | p | n_obs |
|---|---|---|---|---|---|---|---|
| All three groups together | deaths_nat | hidden | 1.0169 | 0.7417 | 1.3942 | 0.917 | 156400 |
| All three groups together | deaths_nat | known | 0.8252 | 0.4548 | 1.4971 | 0.527 | 156400 |
| All three groups together | deaths_nat | pre1960 | 1.0722 | 0.8754 | 1.3132 | 0.501 | 156400 |
| One group: hidden | deaths_nat | hidden | 0.9698 | 0.7141 | 1.3171 | 0.844 | 156400 |
| One group: known | deaths_nat | known | 0.8963 | 0.5576 | 1.4408 | 0.651 | 156400 |
| One group: pre1960 | deaths_nat | pre1960 | 0.9810 | 0.7771 | 1.2383 | 0.872 | 156400 |
| All three groups together | deaths_all | hidden | 1.0396 | 0.7770 | 1.3907 | 0.794 | 159360 |
| All three groups together | deaths_all | known | 0.6734 | 0.3472 | 1.3061 | 0.242 | 159360 |
| All three groups together | deaths_all | pre1960 | 1.1476 | 0.9404 | 1.4005 | 0.175 | 159360 |
| One group: hidden | deaths_all | hidden | 0.9438 | 0.7153 | 1.2453 | 0.682 | 159360 |
| One group: known | deaths_all | known | 0.7937 | 0.4749 | 1.3265 | 0.378 | 159360 |
| One group: pre1960 | deaths_all | pre1960 | 0.9532 | 0.7436 | 1.2218 | 0.705 | 159360 |

## Event study (rate ratio relative to the year before the rebuild)

| outcome | years_since_rebuild | rr | lo | hi | p | n_obs | rebuilt_blocks | comparison_blocks |
|---|---|---|---|---|---|---|---|---|
| deaths_nat | -4 or earlier | 1.1608 | 0.9764 | 1.3800 | 0.0912 | 57780 | 682 | 3330 |
| deaths_nat | -3 | 1.1358 | 0.9145 | 1.4107 | 0.2490 | 57780 | 682 | 3330 |
| deaths_nat | -2 | 0.9704 | 0.8030 | 1.1727 | 0.7560 | 57780 | 682 | 3330 |
| deaths_nat | 0 | 0.9181 | 0.7391 | 1.1403 | 0.4400 | 57780 | 682 | 3330 |
| deaths_nat | 1 | 0.9220 | 0.7408 | 1.1476 | 0.4670 | 57780 | 682 | 3330 |
| deaths_nat | 2 | 0.9401 | 0.7746 | 1.1410 | 0.5320 | 57780 | 682 | 3330 |
| deaths_nat | 3 | 1.0976 | 0.8736 | 1.3791 | 0.4240 | 57780 | 682 | 3330 |
| deaths_nat | 4 or later | 1.0648 | 0.8680 | 1.3061 | 0.5470 | 57780 | 682 | 3330 |
| deaths_all | -4 or earlier | 1.1617 | 0.9861 | 1.3685 | 0.0730 | 58860 | 682 | 3330 |
| deaths_all | -3 | 1.1086 | 0.8958 | 1.3718 | 0.3430 | 58860 | 682 | 3330 |
| deaths_all | -2 | 0.9811 | 0.8301 | 1.1596 | 0.8230 | 58860 | 682 | 3330 |
| deaths_all | 0 | 0.8963 | 0.7147 | 1.1241 | 0.3430 | 58860 | 682 | 3330 |
| deaths_all | 1 | 0.9330 | 0.7733 | 1.1257 | 0.4690 | 58860 | 682 | 3330 |
| deaths_all | 2 | 0.9718 | 0.8097 | 1.1665 | 0.7590 | 58860 | 682 | 3330 |
| deaths_all | 3 | 1.0976 | 0.8728 | 1.3804 | 0.4260 | 58860 | 682 | 3330 |
| deaths_all | 4 or later | 1.1004 | 0.9076 | 1.3341 | 0.3300 | 58860 | 682 | 3330 |
