function zfs-be-info --description 'Show information about boot environment'
    set -l options 'h/help' 'a/all' 'c/current' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-be-info [options] [be-name]"
        echo "  -a/--all      Show all boot environments"
        echo "  -c/--current  Show current boot environment"
        echo "  -q/--quiet    Don't show the executed command"
        echo "  -h/--help     Show this help"
        echo "  be-name       Specific BE to show info for"
        return
    end

    if test -z "$ZFS_BE_ROOT"
        echo "Error: ZFS_BE_ROOT environment variable not set"
        return 1
    end

    if set -q _flag_current
        echo "=== Current Boot Environment ==="
        set -l current_root (findmnt -no SOURCE /)
        if not set -q _flag_quiet
            set_color blue
            echo "# findmnt -no SOURCE /"
            set_color normal
        end
        echo "Root dataset: $current_root"

        if test -n "$current_root"
            set -l cmd "zfs get origin,creation,used,compressratio $current_root"
            if not set -q _flag_quiet
                set_color blue
                echo "# $cmd"
                set_color normal
            end
            eval $cmd
        end
        return
    end

    if set -q _flag_all
        echo "=== All Boot Environments ==="
        set -l cmd "zfs list -r $ZFS_BE_ROOT -o name,used,refer,origin,mountpoint"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
        return
    end

    if test (count $argv) -gt 0
        set -l be_name $argv[1]
        set -l be_root "$ZFS_BE_ROOT/$be_name/root"

        echo "=== Boot Environment: $be_name ==="

        # Check if BE exists
        if not zfs list $be_root >/dev/null 2>&1
            echo "Error: Boot environment '$be_name' not found"
            return 1
        end

        set -l cmd "zfs get origin,creation,used,compressratio,org.zfsbootmenu:commandline $be_root"
        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end
        eval $cmd
        return
    end

    # Default: show summary
    echo "=== Boot Environment Summary ==="
    set -l cmd "zfs list -r $ZFS_BE_ROOT -t filesystem -o name,used,refer,mountpoint"
    if not set -q _flag_quiet
        set_color blue
        echo "# $cmd"
        set_color normal
    end
    eval $cmd
end
