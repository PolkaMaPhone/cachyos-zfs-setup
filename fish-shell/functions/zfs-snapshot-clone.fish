function zfs-snapshot-clone --description 'Clone ZFS snapshot to new dataset'
    set -l options 'h/help' 'p/properties=' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-snapshot-clone [options] <snapshot> <clone-name>"
        echo "  -p/--properties PROPS  Set properties on clone (prop=value,prop=value)"
        echo "  -q/--quiet             Don't show the executed command"
        echo "  -h/--help              Show this help"
        echo "  snapshot               Source snapshot to clone"
        echo "  clone-name             Name for the new cloned dataset"
        echo ""
        echo "Example: zfs-snapshot-clone $ZFS_ROOT_DATASET@backup-snapshot $ZFS_BE_ROOT/recovery"
        return
    end

    if test (count $argv) -lt 2
        echo "Error: Both snapshot and clone name required. Use -h for help."
        return 1
    end

    set -l snapshot $argv[1]
    set -l clone_name $argv[2]
    set -l cmd "sudo zfs clone"

    if set -q _flag_properties
        # Split properties and add -o for each
        for prop in (string split ',' $_flag_properties)
            set cmd "$cmd -o $prop"
        end
    end

    set cmd "$cmd $snapshot $clone_name"

    # Show the command being executed (unless quiet)
    if not set -q _flag_quiet
        set_color blue
        echo "# $cmd"
        set_color normal
    end

    eval $cmd
    if test $status -eq 0
        set -l mnt (mktemp -d)
        if sudo mount -t zfs $clone_name $mnt
            sudo rm -f $mnt/var/lib/pacman/db.lck
            sudo umount $mnt
        end
        rmdir $mnt

        echo "Cloned $snapshot to $clone_name"
    end
end
