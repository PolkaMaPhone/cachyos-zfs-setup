function zfs-list-datasets --description 'List ZFS datasets with useful information'
    set -l options 'h/help' 'a/all' 's/space' 'r/recursive' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-list-datasets [options] [dataset]"
        echo "  -a/--all         Include snapshots and bookmarks"
        echo "  -s/--space       Show space usage and compression info"
        echo "  -r/--recursive   Recursive listing"
        echo "  -q/--quiet       Don't show the executed command"
        echo "  -h/--help        Show this help"
        echo "  dataset          Dataset to list (default: \$ZFS_ROOT_POOL)"
        echo ""
        echo "Current default dataset: $ZFS_ROOT_POOL"
        return
    end

    set -l dataset $argv[1]
    if test -z "$dataset"
        set dataset $ZFS_ROOT_POOL
    end

    if test -z "$dataset"
        echo "Error: No dataset specified and ZFS_ROOT_POOL not set"
        return 1
    end

    set -l cmd "zfs list"

    if set -q _flag_all
        set cmd "$cmd -t all"
    end

    if set -q _flag_recursive
        set cmd "$cmd -r"
    end

    if set -q _flag_space
        set cmd "$cmd -o name,used,avail,refer,compressratio,compression"
    else
        set cmd "$cmd -o name,used,avail,refer,mountpoint"
    end

    set -l full_cmd "$cmd $dataset"

    # Show the command being executed (unless quiet)
    if not set -q _flag_quiet
        set_color blue
        echo "# $full_cmd"
        set_color normal
    end

    eval $full_cmd
end
