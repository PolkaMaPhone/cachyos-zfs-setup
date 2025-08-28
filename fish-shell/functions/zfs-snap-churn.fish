function zfs-snap-churn
    # Usage/help
    set -l cmd (status current-command)
    if test (count $argv) -lt 1
        echo "Usage: $cmd DATASET"
        echo "Example: $cmd zpcachyos/ROOT/cos/root"
        return 2
    end

    set -l DS $argv[1]

    # Collect snapshots (oldest -> newest) for the dataset
    set -l SNAPS (zfs list -t snapshot -o name -s creation -H | awk -v ds="$DS@" '$1 ~ "^"ds {print $1}')
    set -l nsnaps (count $SNAPS)
    if test $nsnaps -lt 2
        echo "Found $nsnaps snapshot(s) for $DS — need at least 2 to compute deltas."
        return 1
    end

    # Sum 'written' between consecutive snapshots
    set -l total_bytes 0
    set -l intervals 0
    for i in (seq 2 $nsnaps)
        set -l snap $SNAPS[$i]
        set -l w (zfs get -Hp -o value written "$snap" 2>/dev/null)
        if test -z "$w"
            set w 0
        end
        set total_bytes (math "$total_bytes + $w")
        set intervals (math "$intervals + 1")
    end

    # Averages / projection
    set -l avg_per_snap_bytes (math "$total_bytes / $intervals")
    set -l window_bytes $total_bytes

    # Pretty-print
    set -l avg_mib (math "$avg_per_snap_bytes / 1048576")
    set -l window_gib (math "$window_bytes / 1073741824")

    printf "Dataset:          %s\n" "$DS"
    printf "Snapshots:        %d (intervals: %d)\n" $nsnaps $intervals
    printf "Avg per snapshot: %.2f MiB (bytes: %.0f)\n" $avg_mib $avg_per_snap_bytes
    printf "Window estimate:  %.2f GiB (bytes: %.0f)\n" $window_gib $window_bytes

    # Optional: newest snapshot's 'written'
    set -l newest $SNAPS[$nsnaps]
    set -l newest_written (zfs get -Hp -o value written "$newest" 2>/dev/null)
    if test -n "$newest_written"
        set -l newest_mib (math "$newest_written / 1048576")
        printf "Newest snap '%s' written: %.2f MiB\n" "$newest" $newest_mib
    end
end

