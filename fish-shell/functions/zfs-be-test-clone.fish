function zfs-be-test-clone --description 'Create test boot environment from latest pacman snapshot'
    set -l options 'h/help' 's/snapshot=' 'a/auto-zbm' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-be-test-clone [options]"
        echo "  -s/--snapshot SNAP  Use specific snapshot (default: latest pacman)"
        echo "  -a/--auto-zbm       Automatically run generate-zbm after creation"
        echo "  -q/--quiet          Don't show the executed command"
        echo "  -h/--help           Show this help"
        echo ""
        echo "Creates test BE with timestamp: test-YYYYMMDD-HHMMSS"
        return
    end

    set -l snapshot
    if set -q _flag_snapshot
        set snapshot $_flag_snapshot
    else
        set snapshot (zfs list -t snapshot -H -o name -s creation | grep pacman | tail -1)
    end

    if test -z "$snapshot"
        echo "Error: No pacman snapshots found and no snapshot specified"
        return 1
    end

    set -l test_name "test-"(date +%Y%m%d-%H%M%S)

    echo "Creating test BE '$test_name' from: $snapshot"

    # Use zfs-be-clone to do the work
    if set -q _flag_auto_zbm
        zfs-be-clone --auto-zbm $snapshot $test_name
    else
        zfs-be-clone $snapshot $test_name
    end

    if test $status -eq 0
        set -l be_root "$ZFS_BE_ROOT/$test_name/root"
        set -l mnt (mktemp -d)
        set -l orig_mountpoint (zfs get -H -o value mountpoint $be_root)
        sudo zfs set mountpoint=$mnt $be_root
        if sudo zfs mount $be_root
            sudo rm -f $mnt/var/lib/pacman/db.lck
            sudo zfs umount $be_root
        end
        sudo zfs set mountpoint=$orig_mountpoint $be_root
        rmdir $mnt
        echo "Test BE created: $test_name"
        echo "To clean up later: sudo zfs destroy -r $ZFS_BE_ROOT/$test_name"
    end
end
