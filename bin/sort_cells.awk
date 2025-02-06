#!/usr/bin/awk -f

BEGIN {
    FS = " ";
}

# Ignore comments and header lines
/^%/ { next }
NR == 1 { next }  # Skip first non-comment line (matrix dimensions)

/^#/ { next }

{
    cell_id = $2;  # Column (cell) ID
    umi_count = $3;  # UMI count
    counts[cell_id] += umi_count;
}

END {
    # Store UMI counts in an array for sorting
    n = asorti(counts, sorted_counts, "@val_num_desc");

    # Print the nth cell's UMI count if it exists
    if (n >= target_cell) {
        nth_value = counts[sorted_counts[target_cell]];
        print (nth_value > preset_value) ? nth_value : preset_value;
    } else {
        print preset_value;
    }
}