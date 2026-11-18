# Review of every 1961–2002 hazardous-sector listing against the page scans (14 November 2026)

The *Directory of Colorado Manufacturers* (1961–2002 editions) was OCR'd and parsed. 10,586 parsed listings are classified as
hazardous-sector (Frickel & Elliott: SIC major groups **28** chemicals, **29** petroleum, **30** rubber & plastics, **33** primary
metals, **34** fabricated metals, **35** industrial machinery, **37** transportation equipment; NAICS 325, 324, 326, 331, 332, 333, 336
in 2002). They make up the 3,565 published hazardous sites. A scan check of 30 found 4 that were not hazardous at all (a code read
from a house number, a neighbour's code, a name keyword, an OCR digit misread) and 2 wrong house numbers. Your job: read each listing
of your chunk on the page image and record what is actually printed. Your output becomes a committed review file that the pipeline
applies, so every row changes the published data. Be exact. Decide from the page image only, never from outside knowledge.

Input: `/home/claude/review7/chunks/cNN.csv`, one row per listing: lid, year, source_volume, page, name, street, city, zip, sic,
sic_source, fe_sectors, tiles. `tiles` lists the image files of that page (`;`-separated; overlapping pieces of the one page, read
left-to-right, top-to-bottom). Rows are sorted by page: open the page's tiles once (Read tool) and decide all of its rows together.
Find each firm by its name (alphabetical within a town, under a town heading; in 1988–1992 editions the town heading also prints the
county). OCR names may be garbled; the street, zip and codes help you find the entry.

For each row write one output row (same order) to `/home/claude/review7/out/cNN_review.csv` with columns:
`lid, verdict, name_fix, street_fix, city_fix, sic_printed, hazardous, note`

- **verdict**: one of
  - `ok`: the entry is on the page and name, street and town are right (trivial OCR noise such as a dropped period, `+` for `&`,
    `0`/`O` in a word, is fine; name_fix/street_fix/city_fix stay empty).
  - `fix`: the entry is on the page but name, street or town is materially wrong: fill the field(s) that are wrong.
  - `not_found`: you cannot find this firm on the page or its tiles (say what you looked for in the note).
  - `not_listing`: the row is not a firm (a heading, a fragment, a mix of two entries that does not correspond to any one firm).
- **name_fix**: the firm name as printed, when the published name is missing words, carries words of another entry (`SKIS SONOCO
  PRODUCTS CO` → `SONOCO PRODUCTS CO`), is unreadable, or is another firm. Upper case as printed.
- **street_fix**: the firm's own street address as printed, whenever the house number or street differs from `street` in any digit or
  word (`375 S RARITAN` printed `2375 S RARITAN` → `2375 S RARITAN`; `12 W COLORADO AVE` printed `2802 1/2 W COLORADO AVE`). Print
  P O boxes as printed. If the entry prints a plant address and an office or owner address, use the firm's own plant address.
- **city_fix**: the town the entry is printed under (the town heading above it, or the town printed in the entry in 1988–2002),
  upper case, only when it differs from `city`. Exception: in the county sections a "DENVER" heading covers firms with Denver
  mailing addresses whose published `city` is the suburb of their zip (ARVADA, LAKEWOOD, AURORA, THORNTON, COMMERCE CITY,
  ENGLEWOOD...): leave city_fix empty for those (the zip decides the place).
- **sic_printed**: every industry code printed for THIS firm, `;`-separated, in printed order (e.g. `3079;2341`). Only the firm's own
  code lines — never a code from the entry above or below, never a house number, zip, phone or employment figure. In 2002 give the
  NAICS codes (6 digits) as printed. In the 1961, 1962 and 1966 editions no codes are printed: leave it empty and copy the printed
  product line(s) into the note.
- **hazardous**: `yes` if any printed code is in SIC major groups 28, 29, 30, 33, 34, 35 or 37 (NAICS 324, 325, 326, 331, 332, 333,
  336); `no` otherwise. In 1961/1962/1966 judge from the printed products: `yes` only if they clearly belong to those groups
  (chemicals, paints, plastics products, rubber products, metals, castings, metal fabrication, machinery, machine shop, vehicles and
  parts, aircraft); a product line naming another industry (meat products, printing, apparel, office supplies, pens and pencils,
  lumber) is `no`. For `not_found` / `not_listing` leave it empty.
- **note**: one short line: what you read (quote a few words), especially for every fix and every `no`.

Rules: a firm printed twice on the page is one entry; judge each row by the entry it stands for. If a row's name belongs to one entry
and its street/code to another, decide by the name (that is the firm), give that firm's own street and codes, and say so in the
note. Read-only everywhere except your output file and scratch under `/home/claude/review7/scratch/cNN/` (keep it tiny; delete when
done). Do not open any code. Validate before finishing: same number of rows and order as the input; verdict in the vocabulary;
hazardous in {yes,no,''}; every `no` and every fix has a note.
Final message (under 120 words): counts per verdict, counts of hazardous yes/no, and any systematic pattern (a whole page misread, a
volume whose codes are offset, etc.).
