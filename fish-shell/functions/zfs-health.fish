function zfs-health --description 'ZFS system health overview'
    set -l options 'h/help' 'v/verbose' 'p/performance' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-health [options]"
        echo "  -v/--verbose      Show detailed information"
        echo "  -p/--performance  Include performance metrics"
        echo "  -q/--quiet        Don't show the executed commands"
        echo "  -h/--help         Show this help"
        return
    end

    echo "=== ZFS Health Overview ==="
    echo

    # Pool Status
    echo "Pool Status:"
    if test -n "$ZFS_ROOT_POOL"
        set -l cmd "zpool status $ZFS_ROOT_POOL"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
    else
        set -l cmd "zpool status"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
    end

    echo
    echo "Pool Usage:"
    set -l cmd2 "zpool list"
    if not set -q _flag_quiet
        set_color blue
        echo "# $cmd2"
        set_color normal
    end
    eval $cmd2

    echo
    echo "Dataset Usage:"
    if test -n "$ZFS_ROOT_POOL"
        set -l cmd3 "zfs list -o name,used,avail,refer,compressratio $ZFS_ROOT_POOL"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd3"
            set_color normal
        end
        eval $cmd3
    else
        set -l cmd3 "zfs list -o name,used,avail,refer,compressratio"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd3"
            set_color normal
        end
        eval $cmd3
    end

    if set -q _flag_verbose
        echo
        echo "Recent Snapshots:"
        set -l cmd4 "zfs list -t snapshot -o name,used,creation -s creation | tail -10"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd4"
            set_color normal
        end
        eval $cmd4

        echo
        echo "Boot Environments:"
        if test -n "$ZFS_BE_ROOT"
            set -l cmd5 "zfs list -r $ZFS_BE_ROOT -o name,used,refer,mountpoint"
            if not set -q _flag_quiet
                set_color blue
                echo "# $cmd5"
                set_color normal
            end
            eval $cmd5
        end
    end

    if set -q _flag_performance
        echo
        echo "ARC Summary:"
        set -l cmd6 "arc_summary | grep -E '(Hit|Miss|Size|Metadata)'"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd6"
            set_color normal
        end
        eval $cmd6

        echo
        echo "I/O Statistics:"
        set -l cmd7 "zpool iostat $ZFS_ROOT_POOL 1 3"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd7"
            set_color normal
        end
        eval $cmd7
    end
end
