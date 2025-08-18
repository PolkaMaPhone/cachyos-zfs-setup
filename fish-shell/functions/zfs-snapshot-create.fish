function zfs-snapshot-create --description 'Create ZFS snapshots'
    set -l options 'h/help' 'm/manual=' 'n/now' 'd/dataset=' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-snapshot-create [options] [snapshot-name]"
        echo "  -m/--manual DESC     Create manual snapshot with description"
        echo "  -n/--now             Create manual snapshot with current timestamp"
        echo "  -d/--dataset NAME    Dataset to snapshot (default: \$ZFS_ROOT_DATASET)"
        echo "  -q/--quiet           Don't show the executed command"
        echo "  -h/--help            Show this help"
        echo "  snapshot-name        Create specific snapshot (dataset@name format)"
        echo ""
        echo "Current default dataset: $ZFS_ROOT_DATASET"
        return
    end

    set -l dataset $ZFS_ROOT_DATASET
    if set -q _flag_dataset
        set dataset $_flag_dataset
    end

    if test -z "$dataset"
        echo "Error: No dataset specified and ZFS_ROOT_DATASET not set"
        return 1
    end

    set -l snapshot_name
    if set -q _flag_manual
        set snapshot_name "$dataset@manual-$_flag_manual-"(date +%Y%m%d-%H%M%S)
    else if set -q _flag_now
        set snapshot_name "$dataset@manual-"(date +%Y%m%d-%H%M%S)
    else if test (count $argv) -gt 0
        set snapshot_name $argv[1]
    else
        echo "Error: No snapshot specified. Use -h for help."
        return 1
    end

    set -l cmd "sudo zfs snapshot $snapshot_name"

    # Show the command being executed (unless quiet)
    if not set -q _flag_quiet
        set_color blue
        echo "# $cmd"
        set_color normal
    end

    eval $cmd
    if test $status -eq 0
        echo "Created: $snapshot_name"
    end
end
