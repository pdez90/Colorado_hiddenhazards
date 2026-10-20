# Sanborn sheet observations (batch 1)

`sanborn_observations_batch1.csv` records what the Sanborn Fire Insurance Map sheets show at 46 study sites in volume 1 (downtown, Lower Downtown, Auraria and the Platte valley edge): the building use as labelled, stories, construction, drawn or labelled equipment (boilers, furnaces, ovens, tanks and their contents), the business name printed on the sheet, approximate dwellings on the same block, neighbouring uses, a five-way verdict and a confidence rating.

- Pre-1960 street-level trades were checked on the 1929–30 edition (17 sites); 1941–1973 records on the 1929–Dec. 1951 edition, which carries paste-over corrections to 1951 (29 sites).
- Sheet numbers come from each volume's street index (`data/results/context/sanborn_batch1_sheets.csv`).
- Source: Digital Sanborn Maps, 1867–1970 (ProQuest / Environmental Data Resources), consulted through the Denver Public Library for non-commercial academic research. The map images are not redistributed; they stay in `work/sanborn/`, which is git-ignored. This file contains only our own transcribed notes.
- Verdicts: same or closely related hazardous trade · related trade or vehicle/fuel use · other industrial or workshop use · store, office, hotel or warehouse · dwelling or vacant lot.

R/context_layers.R adds each observation to the site's map popup and writes `data/results/context/sanborn_validation_summary.csv`.
