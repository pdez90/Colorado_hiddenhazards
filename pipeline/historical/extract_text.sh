#!/usr/bin/env bash
# Text layers of the CU Boulder scans of the Colorado State Business Directory (1877-1950).
# Put the PDFs (downloaded from https://www.historycolorado.org/business-directories -> CU Boulder Libraries) in work/hist/pdf/.
# The scans carry an OCR text layer; we use it as-is (poppler's pdftotext, one form feed per page).
set -euo pipefail
mkdir -p work/hist/text
for f in work/hist/pdf/*.pdf; do
  b=$(basename "$f" .pdf); [[ -s work/hist/text/$b.txt ]] || pdftotext "$f" "work/hist/text/$b.txt"
done
ls work/hist/text | wc -l
