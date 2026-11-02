# Former hazardous sites, before and after they were rebuilt: block mortality 2000-2019, Denver study area

13,439 blocks, 268,095 block-years, 101,159 natural-cause deaths, years 2000-2019.

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
| hidden | 248 | 20 | 21 | 207 |
| known | 701 | 51 | 39 | 611 |
| pre1960 | 303 | 52 | 118 | 133 |

## Rate ratio per SD of nearby sites still standing (block and year fixed effects)

| model | outcome | term | rr | lo | hi | p | n_obs |
|---|---|---|---|---|---|---|---|
| All three groups together | deaths_nat | hidden | 1.0413 | 0.8406 | 1.2900 | 0.711 | 199817 |
| All three groups together | deaths_nat | known | 0.9399 | 0.5782 | 1.5279 | 0.803 | 199817 |
| All three groups together | deaths_nat | pre1960 | 1.0349 | 0.8922 | 1.2005 | 0.650 | 199817 |
| One group: hidden | deaths_nat | hidden | 1.0300 | 0.8371 | 1.2673 | 0.780 | 199817 |
| One group: known | deaths_nat | known | 1.0037 | 0.6849 | 1.4709 | 0.985 | 199817 |
| One group: pre1960 | deaths_nat | pre1960 | 1.0131 | 0.8578 | 1.1965 | 0.878 | 199817 |
| All three groups together | deaths_all | hidden | 1.0654 | 0.8772 | 1.2939 | 0.523 | 203197 |
| All three groups together | deaths_all | known | 0.7844 | 0.4653 | 1.3223 | 0.362 | 203197 |
| All three groups together | deaths_all | pre1960 | 1.1020 | 0.9492 | 1.2793 | 0.202 | 203197 |
| One group: hidden | deaths_all | hidden | 1.0149 | 0.8413 | 1.2242 | 0.877 | 203197 |
| One group: known | deaths_all | known | 0.9142 | 0.6074 | 1.3758 | 0.667 | 203197 |
| One group: pre1960 | deaths_all | pre1960 | 0.9986 | 0.8301 | 1.2014 | 0.989 | 203197 |

## Event study (rate ratio relative to the year before the rebuild)

| outcome | years_since_rebuild | rr | lo | hi | p | n_obs | rebuilt_blocks | comparison_blocks |
|---|---|---|---|---|---|---|---|---|
| deaths_nat | -4 or earlier | 1.0523 | 0.9169 | 1.2077 | 0.468 | 63335 | 924 | 3630 |
| deaths_nat | -3 | 1.0511 | 0.9012 | 1.2260 | 0.525 | 63335 | 924 | 3630 |
| deaths_nat | -2 | 1.0555 | 0.9234 | 1.2065 | 0.428 | 63335 | 924 | 3630 |
| deaths_nat | 0 | 0.9837 | 0.8185 | 1.1822 | 0.861 | 63335 | 924 | 3630 |
| deaths_nat | 1 | 1.0052 | 0.8596 | 1.1756 | 0.948 | 63335 | 924 | 3630 |
| deaths_nat | 2 | 1.0579 | 0.8930 | 1.2533 | 0.515 | 63335 | 924 | 3630 |
| deaths_nat | 3 | 1.0854 | 0.9204 | 1.2800 | 0.330 | 63335 | 924 | 3630 |
| deaths_nat | 4 or later | 1.0482 | 0.9042 | 1.2152 | 0.533 | 63335 | 924 | 3630 |
| deaths_all | -4 or earlier | 1.0076 | 0.8644 | 1.1746 | 0.923 | 64655 | 924 | 3630 |
| deaths_all | -3 | 0.9956 | 0.8390 | 1.1815 | 0.960 | 64655 | 924 | 3630 |
| deaths_all | -2 | 1.0079 | 0.8739 | 1.1624 | 0.914 | 64655 | 924 | 3630 |
| deaths_all | 0 | 0.9608 | 0.8062 | 1.1452 | 0.655 | 64655 | 924 | 3630 |
| deaths_all | 1 | 0.9680 | 0.8626 | 1.0863 | 0.580 | 64655 | 924 | 3630 |
| deaths_all | 2 | 1.0438 | 0.9105 | 1.1968 | 0.538 | 64655 | 924 | 3630 |
| deaths_all | 3 | 1.0334 | 0.8772 | 1.2175 | 0.694 | 64655 | 924 | 3630 |
| deaths_all | 4 or later | 1.0428 | 0.9123 | 1.1920 | 0.539 | 64655 | 924 | 3630 |
