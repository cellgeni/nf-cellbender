#!/usr/bin/awk -f
# ------------------------------------------------------------------
#  ils2paths.awk – convert `ils -r` output to full‑path file list
#
#  Usage:
#     ils -r /some/collection | awk -f ils2paths.awk
#  or: ils -r /some/collection | ./ils2paths.awk
# ------------------------------------------------------------------

BEGIN {
    # current collection we’re in
    dir = ""
}

# ------------------------------------------------------------------
# 1. Collection header lines (end with a colon) – remember path
# ------------------------------------------------------------------
/^[[:graph:]]*:$/ {
    sub(/:$/, "")          # drop trailing colon
    dir = $0               # store current collection path
    next
}

# ------------------------------------------------------------------
# 2. Sub‑collection markers (“  C- …”) – ignore them
# ------------------------------------------------------------------
/^[[:space:]]*C-/ { next }

# ------------------------------------------------------------------
# 3. Data‑object entries (indented file names) – print full path
# ------------------------------------------------------------------
/^[[:space:]]+/ {
    sub(/^[[:space:]]+/, "")   # strip leading spaces
    print dir "/" $0
}
