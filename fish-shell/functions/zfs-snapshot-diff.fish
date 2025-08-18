function zfs-snapshot-diff --description 'Show differences between ZFS snapshots or current state'
    set -l options 'h/help' 'F/file-type' 'H/parseable' 't/types=' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-snapshot-diff [options] <snapshot1> [snapshot2]"
        echo "  -F/--file-type       Show file type indicators"
        echo "  -H/--parseable       Machine parseable output"
        echo "  -t/--types TYPES     Filter by change types (M,+,-,R)"
        echo "  -q/--quiet           Don't show the executed command"
        echo "  -h/--help            Show this help"
        echo "  snapshot1            First snapshot (older)"
        echo "  snapshot2            Second snapshot or current state (default: current)"
        echo ""
        echo "Example: zfs-snapshot-diff $ZFS_ROOT_DATASET@pacman-20250817-164008"
        return
    end

    if test (count $argv) -eq 0
        echo "Error: No snapshot specified. Use -h for help."
        return 1
    end

    set -l snapshot1 $argv[1]
    set -l snapshot2
    if test (count $argv) -gt 1
        set snapshot2 $argv[2]
    else
        # Default to current state of the dataset
        set snapshot2 (echo $snapshot1 | cut -d@ -f1)
    end

    set -l cmd "sudo zfs diff"

    if set -q _flag_file_type
        set cmd "$cmd -F"
    end

    if set -q _flag_parseable
        set cmd "$cmd -H"
    end

    if set -q _flag_types
        set cmd "$cmd -t $_flag_types"
    end

    set cmd "$cmd $snapshot1 $snapshot2"

    # Show the command being executed (unless quiet)
    if not set -q _flag_quiet
        set_color blue
        echo "# $cmd"
        set_color normal
    end

    eval $cmd
end
