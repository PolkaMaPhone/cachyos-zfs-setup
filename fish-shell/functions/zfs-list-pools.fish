function zfs-list-pools --description 'List ZFS pools with status and usage'
    set -l options 'h/help' 'v/verbose' 'i/iostat' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-list-pools [options]"
        echo "  -v/--verbose     Show detailed pool status"
        echo "  -i/--iostat      Show I/O statistics"
        echo "  -q/--quiet       Don't show the executed command"
        echo "  -h/--help        Show this help"
        return
    end

    if set -q _flag_verbose
        set -l cmd "zpool status -v"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
    else if set -q _flag_iostat
        set -l cmd "zpool iostat -v"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
    else
        if not set -q _flag_quiet
            set_color blue
            echo "# zpool list"
            set_color normal
        end
        echo "=== Pool Status ==="
        zpool list

        echo
        if not set -q _flag_quiet
            set_color blue
            echo "# zpool status"
            set_color normal
        end
        echo "=== Pool Health ==="
        zpool status
    end
end
