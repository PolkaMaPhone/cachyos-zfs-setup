function zfs-be-create --description 'Create new ZFS boot environment'
    set -l options 'h/help' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-be-create [options] <be-name>"
        echo "  -q/--quiet    Don't show the executed command"
        echo "  -h/--help     Show this help"
        echo "  be-name       Name for the new boot environment"
        echo ""
        echo "Creates: $ZFS_BE_ROOT/<be-name>"
        echo "This only creates the container. Use zfs-be-clone to populate it."
        return
    end

    if test (count $argv) -eq 0
        echo "Error: Boot environment name required. Use -h for help."
        return 1
    end

    if test -z "$ZFS_BE_ROOT"
        echo "Error: ZFS_BE_ROOT environment variable not set"
        return 1
    end

    set -l be_name $argv[1]
    set -l be_path "$ZFS_BE_ROOT/$be_name"
    set -l cmd "sudo zfs create -o canmount=off -o mountpoint=none $be_path"

    # Show the command being executed (unless quiet)
    if not set -q _flag_quiet
        set_color blue
        echo "# $cmd"
        set_color normal
    end

    eval $cmd
    if test $status -eq 0
        echo "Created boot environment container: $be_path"
        echo "Use 'zfs-be-clone <snapshot> $be_name' to populate it"
    end
end
