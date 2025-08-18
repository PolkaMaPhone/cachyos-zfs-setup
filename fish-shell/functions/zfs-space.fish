function zfs-space --description 'ZFS space usage analysis'
    set -l options 'h/help' 't/top=' 'c/compression' 's/snapshots' 'd/dataset=' 'o/overview' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-space [options]"
        echo "  -o/--overview        Show basic space overview (default)"
        echo "  -t/--top N           Show top N space consumers"
        echo "  -c/--compression     Show compression analysis"
        echo "  -s/--snapshots       Show detailed snapshot space usage"
        echo "  -d/--dataset NAME    Analyze specific dataset (default: \$ZFS_ROOT_POOL)"
        echo "  -q/--quiet           Don't show the executed commands"
        echo "  -h/--help            Show this help"
        return
    end

    set -l dataset $ZFS_ROOT_POOL
    if set -q _flag_dataset
        set dataset $_flag_dataset
    end

    if test -z "$dataset"
        echo "Error: No dataset specified and ZFS_ROOT_POOL not set"
        return 1
    end

    echo "=== ZFS Space Analysis for $dataset ==="
    echo

    if set -q _flag_top
        echo "Top $_flag_top Space Consumers:"
        set -l cmd "zfs list -s used -o name,used,refer,type | head -$_flag_top"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
        echo
    end

    if set -q _flag_compression
        echo "Compression Analysis:"
        # Remove -s local to show compressratio
        set -l cmd2 "zfs get compressratio,compression,used -r $dataset"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd2"
            set_color normal
        end
        eval $cmd2
        echo

        echo "Compression Summary:"
        set -l cmd2b "zfs list -o name,used,compressratio $dataset"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd2b"
            set_color normal
        end
        eval $cmd2b
        echo
    end

    if set -q _flag_snapshots
        echo "Snapshot Space Usage:"
        set -l cmd3 "zfs list -t snapshot -s used -o name,used,refer | head -20"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd3"
            set_color normal
        end
        eval $cmd3
        echo

        echo "Space Used by Snapshots vs Data:"
        set -l cmd4 "zfs get usedbysnapshots,usedbydataset -r $dataset"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd4"
            set_color normal
        end
        eval $cmd4
        echo

        echo "Snapshot Space Summary:"
        set -l cmd5 "zfs list -o name,used,usedsnap,usedbydataset $dataset"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd5"
            set_color normal
        end
        eval $cmd5
        echo
    end

    # Default overview when no specific flags are set
    if not set -q _flag_top; and not set -q _flag_compression; and not set -q _flag_snapshots
        set _flag_overview true
    end

    if set -q _flag_overview
        echo "Dataset Space Overview:"
        set -l cmd6 "zfs list -o name,used,avail,refer,compressratio $dataset"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd6"
            set_color normal
        end
        eval $cmd6

        echo
        echo "Largest Datasets:"
        set -l cmd7 "zfs list -s used -o name,used,refer | head -10"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd7"
            set_color normal
        end
        eval $cmd7

        echo
        echo "Dataset vs Snapshot Space Usage:"
        set -l cmd8 "zfs list -r -o name,used,usedsnap,usedbydataset $dataset | grep -v '\\s0B\\s.*0B'"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd8 | grep -v '\\s0B\\s.*0B' (filtering empty entries)"
            set_color normal
        end
        eval $cmd8
    end
end
