#!/usr/bin/awk -f

BEGIN {
    FS = " ";
    cell_count = 0;
}

# Ignore comments and header lines
/^%/ { next }
NR == 1 { next }  # Skip first non-comment line (matrix dimensions)

/^#/ { next }

{
    col_id = $2;  # Column (cell) ID
    value = $3;   # Count value
    counts[col_id] += value;
}

END {
    for (c in counts) {
        if (counts[c] > threshold) {
            cell_count++;
        }
    }
    print cell_count;
}
