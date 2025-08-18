function zfs-snapshot-properties --description 'View or set ZFS snapshot properties'
    set -l options 'h/help' 's/set=' 'g/get=' 'a/all' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-snapshot-properties [options] <snapshot>"
        echo "  -g/--get PROP        Get specific property"
        echo "  -s/--set PROP=VALUE  Set property on snapshot"
        echo "  -a/--all             Show all properties"
        echo "  -q/--quiet           Don't show the executed command"
        echo "  -h/--help            Show this help"
        echo "  snapshot             Snapshot to query/modify"
        echo ""
        echo "Example: zfs-snapshot-properties -g used $ZFS_ROOT_DATASET@backup"
        return
    end

    if test (count $argv) -eq 0
        echo "Error: No snapshot specified. Use -h for help."
        return 1
    end

    set -l snapshot $argv[1]

    if set -q _flag_set
        set -l cmd "sudo zfs set $_flag_set $snapshot"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
    else if set -q _flag_get
        set -l cmd "zfs get $_flag_get $snapshot"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
    else if set -q _flag_all
        set -l cmd "zfs get all $snapshot"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
    else
        # Default: show common properties
        set -l cmd "zfs get used,creation,referenced,compressratio $snapshot"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
    end
end
