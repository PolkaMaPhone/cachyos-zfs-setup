function zfs-list-snapshots --description 'List ZFS snapshots with creation time and size'
    set -l options 'h/help' 'r/recent=' 'p/pacman' 'l/large' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-list-snapshots [options]"
        echo "  -r/--recent N    Show last N snapshots"
        echo "  -p/--pacman      Show only pacman snapshots"
        echo "  -l/--large       Sort by size (largest first)"
        echo "  -q/--quiet       Don't show the executed command"
        echo "  -h/--help        Show this help"
        return
    end

    set -l cmd "zfs list -t snapshot -o name,used,refer,creation"

    if set -q _flag_large
        set cmd "$cmd -s used"
    else
        set cmd "$cmd -s creation"
    end

    set -l pipe_cmd ""
    if set -q _flag_pacman
        set pipe_cmd "$pipe_cmd | grep pacman"
    end

    if set -q _flag_recent
        set pipe_cmd "$pipe_cmd | tail -$_flag_recent"
    end

    set -l full_cmd "$cmd$pipe_cmd"

    # Show the command being executed (unless quiet)
    if not set -q _flag_quiet
        set_color blue
        echo "# $full_cmd"
        set_color normal
    end

    eval $full_cmd
end
