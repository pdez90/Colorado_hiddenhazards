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
| hidden | 307 | 23 | 21 | 263 |
| known | 825 | 54 | 42 | 729 |
| pre1960 | 366 | 49 | 102 | 215 |

## Rate ratio per SD of nearby sites still standing (block and year fixed effects)

| model | outcome | term | rr | lo | hi | p | n_obs |
|---|---|---|---|---|---|---|---|
| All three groups together | deaths_nat | hidden | 1.0530 | 0.7762 | 1.4286 | 0.740 | 156400 |
| All three groups together | deaths_nat | known | 0.7931 | 0.4402 | 1.4289 | 0.440 | 156400 |
| All three groups together | deaths_nat | pre1960 | 1.1431 | 0.8516 | 1.5344 | 0.373 | 156400 |
| One group: hidden | deaths_nat | hidden | 1.0070 | 0.7578 | 1.3383 | 0.961 | 156400 |
| One group: known | deaths_nat | known | 0.9073 | 0.5900 | 1.3952 | 0.658 | 156400 |
| One group: pre1960 | deaths_nat | pre1960 | 0.9828 | 0.7301 | 1.3231 | 0.909 | 156400 |
| All three groups together | deaths_all | hidden | 1.0540 | 0.7972 | 1.3934 | 0.712 | 159360 |
| All three groups together | deaths_all | known | 0.6652 | 0.3447 | 1.2838 | 0.224 | 159360 |
| All three groups together | deaths_all | pre1960 | 1.2444 | 0.9017 | 1.7174 | 0.183 | 159360 |
| One group: hidden | deaths_all | hidden | 0.9727 | 0.7517 | 1.2587 | 0.834 | 159360 |
| One group: known | deaths_all | known | 0.8139 | 0.5069 | 1.3069 | 0.394 | 159360 |
| One group: pre1960 | deaths_all | pre1960 | 0.9431 | 0.6810 | 1.3060 | 0.724 | 159360 |

## Event study (rate ratio relative to the year before the rebuild)

| outcome | years_since_rebuild | rr | lo | hi | p | n_obs | rebuilt_blocks | comparison_blocks |
|---|---|---|---|---|---|---|---|---|
| deaths_nat | -4 or earlier | 1.0549 | 0.8150 | 1.3656 | 0.685 | 60540 | 770 | 3400 |
| deaths_nat | -3 | 1.0424 | 0.8459 | 1.2845 | 0.697 | 60540 | 770 | 3400 |
| deaths_nat | -2 | 0.9813 | 0.8455 | 1.1389 | 0.804 | 60540 | 770 | 3400 |
| deaths_nat | 0 | 0.8986 | 0.7331 | 1.1016 | 0.304 | 60540 | 770 | 3400 |
| deaths_nat | 1 | 0.9646 | 0.7951 | 1.1701 | 0.714 | 60540 | 770 | 3400 |
| deaths_nat | 2 | 0.8640 | 0.6848 | 1.0902 | 0.218 | 60540 | 770 | 3400 |
| deaths_nat | 3 | 0.9921 | 0.7814 | 1.2597 | 0.948 | 60540 | 770 | 3400 |
| deaths_nat | 4 or later | 1.0289 | 0.8498 | 1.2459 | 0.770 | 60540 | 770 | 3400 |
| deaths_all | -4 or earlier | 1.0397 | 0.8166 | 1.3238 | 0.752 | 61720 | 770 | 3400 |
| deaths_all | -3 | 0.9860 | 0.7941 | 1.2244 | 0.899 | 61720 | 770 | 3400 |
| deaths_all | -2 | 0.9575 | 0.8205 | 1.1173 | 0.581 | 61720 | 770 | 3400 |
| deaths_all | 0 | 0.8857 | 0.7190 | 1.0911 | 0.254 | 61720 | 770 | 3400 |
| deaths_all | 1 | 0.9469 | 0.7972 | 1.1247 | 0.534 | 61720 | 770 | 3400 |
| deaths_all | 2 | 0.8773 | 0.7094 | 1.0848 | 0.227 | 61720 | 770 | 3400 |
| deaths_all | 3 | 1.0025 | 0.7919 | 1.2692 | 0.983 | 61720 | 770 | 3400 |
| deaths_all | 4 or later | 1.0414 | 0.8804 | 1.2319 | 0.636 | 61720 | 770 | 3400 |
