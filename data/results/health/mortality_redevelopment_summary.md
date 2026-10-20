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
| hidden | 180 | 22 | 17 | 141 |
| known | 581 | 58 | 48 | 475 |
| pre1960 | 242 | 37 | 90 | 115 |

## Rate ratio per SD of nearby sites still standing (block and year fixed effects)

| model | outcome | term | rr | lo | hi | p | n_obs |
|---|---|---|---|---|---|---|---|
| All three groups together | deaths_nat | hidden | 0.9616 | 0.7099 | 1.3025 | 0.800 | 199817 |
| All three groups together | deaths_nat | known | 0.9367 | 0.5821 | 1.5074 | 0.788 | 199817 |
| All three groups together | deaths_nat | pre1960 | 1.2186 | 0.8412 | 1.7654 | 0.296 | 199817 |
| One group: hidden | deaths_nat | hidden | 1.0126 | 0.8427 | 1.2167 | 0.894 | 199817 |
| One group: known | deaths_nat | known | 1.0142 | 0.7287 | 1.4116 | 0.933 | 199817 |
| One group: pre1960 | deaths_nat | pre1960 | 1.1085 | 0.8308 | 1.4791 | 0.484 | 199817 |
| All three groups together | deaths_all | hidden | 0.9620 | 0.7192 | 1.2867 | 0.794 | 203197 |
| All three groups together | deaths_all | known | 0.8990 | 0.5652 | 1.4302 | 0.653 | 203197 |
| All three groups together | deaths_all | pre1960 | 1.2112 | 0.8636 | 1.6986 | 0.267 | 203197 |
| One group: hidden | deaths_all | hidden | 0.9945 | 0.8081 | 1.2237 | 0.958 | 203197 |
| One group: known | deaths_all | known | 0.9690 | 0.6821 | 1.3767 | 0.861 | 203197 |
| One group: pre1960 | deaths_all | pre1960 | 1.0709 | 0.7821 | 1.4665 | 0.669 | 203197 |

## Event study (rate ratio relative to the year before the rebuild)

| outcome | years_since_rebuild | rr | lo | hi | p | n_obs | rebuilt_blocks | comparison_blocks |
|---|---|---|---|---|---|---|---|---|
| deaths_nat | -4 or earlier | 1.1368 | 1.0076 | 1.2826 | 0.0373 | 61240 | 966 | 3457 |
| deaths_nat | -3 | 1.0390 | 0.8779 | 1.2295 | 0.6560 | 61240 | 966 | 3457 |
| deaths_nat | -2 | 1.1491 | 1.0187 | 1.2962 | 0.0237 | 61240 | 966 | 3457 |
| deaths_nat | 0 | 0.9191 | 0.7767 | 1.0878 | 0.3270 | 61240 | 966 | 3457 |
| deaths_nat | 1 | 0.8717 | 0.7206 | 1.0544 | 0.1570 | 61240 | 966 | 3457 |
| deaths_nat | 2 | 0.9939 | 0.8467 | 1.1667 | 0.9410 | 61240 | 966 | 3457 |
| deaths_nat | 3 | 0.9486 | 0.7503 | 1.1994 | 0.6590 | 61240 | 966 | 3457 |
| deaths_nat | 4 or later | 1.0546 | 0.8971 | 1.2398 | 0.5200 | 61240 | 966 | 3457 |
| deaths_all | -4 or earlier | 1.1280 | 1.0065 | 1.2642 | 0.0383 | 62480 | 966 | 3457 |
| deaths_all | -3 | 1.0379 | 0.8885 | 1.2124 | 0.6390 | 62480 | 966 | 3457 |
| deaths_all | -2 | 1.1152 | 0.9943 | 1.2508 | 0.0626 | 62480 | 966 | 3457 |
| deaths_all | 0 | 0.9500 | 0.8147 | 1.1078 | 0.5130 | 62480 | 966 | 3457 |
| deaths_all | 1 | 0.9439 | 0.8136 | 1.0951 | 0.4470 | 62480 | 966 | 3457 |
| deaths_all | 2 | 1.0045 | 0.8681 | 1.1623 | 0.9520 | 62480 | 966 | 3457 |
| deaths_all | 3 | 0.9729 | 0.7930 | 1.1936 | 0.7920 | 62480 | 966 | 3457 |
| deaths_all | 4 or later | 1.0761 | 0.9205 | 1.2580 | 0.3570 | 62480 | 966 | 3457 |
