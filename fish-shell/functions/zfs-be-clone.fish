function zfs-be-clone --description 'Clone snapshot to boot environment'
    set -l options 'h/help' 'a/auto-zbm' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-be-clone [options] <snapshot> <be-name>"
        echo "  -a/--auto-zbm  Automatically run generate-zbm after creation"
        echo "  -q/--quiet     Don't show the executed command"
        echo "  -h/--help      Show this help"
        echo "  snapshot       Source snapshot to clone"
        echo "  be-name        Boot environment name (creates if needed)"
        echo ""
        echo "Creates: $ZFS_BE_ROOT/<be-name>/root from snapshot"
        return
    end

    if test (count $argv) -lt 2
        echo "Error: Both snapshot and BE name required. Use -h for help."
        return 1
    end

    if test -z "$ZFS_BE_ROOT"
        echo "Error: ZFS_BE_ROOT environment variable not set"
        return 1
    end

    set -l snapshot $argv[1]
    set -l be_name $argv[2]
    set -l be_container "$ZFS_BE_ROOT/$be_name"
    set -l be_root "$ZFS_BE_ROOT/$be_name/root"

    # Create BE container if it doesn't exist
    if not zfs list $be_container >/dev/null 2>&1
        set -l create_cmd "sudo zfs create -o canmount=off -o mountpoint=none $be_container"
        if not set -q _flag_quiet
            set_color blue
            echo "# $create_cmd"
            set_color normal
        end
        eval $create_cmd
        if test $status -ne 0
            echo "Error: Failed to create BE container"
            return 1
        end
        echo "Created BE container: $be_container"
    end

    # Clone snapshot to BE root
    set -l clone_cmd "sudo zfs clone -o canmount=noauto -o mountpoint=/ $snapshot $be_root"
    if not set -q _flag_quiet
        set_color blue
        echo "# $clone_cmd"
        set_color normal
    end
    eval $clone_cmd
    if test $status -ne 0
        echo "Error: Failed to clone snapshot"
        return 1
    end

    # Remove pacman database lock from new BE
    set -l mnt (mktemp -d)
    if sudo mount -t zfs $be_root $mnt
        sudo rm -f $mnt/var/lib/pacman/db.lck
        sudo umount $mnt
    end
    rmdir $mnt


    # Set ZBM properties
    set -l zbm_cmd "sudo zfs set org.zfsbootmenu:commandline=\"rw quiet\" $be_root"
    if not set -q _flag_quiet
        set_color blue
        echo "# $zbm_cmd"
        set_color normal
    end
    eval $zbm_cmd

    echo "Cloned $snapshot to $be_root"

    if set -q _flag_auto_zbm
        echo "Regenerating ZBM..."
        set -l gen_cmd "sudo generate-zbm"
        if not set -q _flag_quiet
            set_color blue
            echo "# $gen_cmd"
            set_color normal
        end
        eval $gen_cmd
        echo "Boot menu updated"
    else
        echo "Run 'sudo generate-zbm' to update boot menu"
    end
end
