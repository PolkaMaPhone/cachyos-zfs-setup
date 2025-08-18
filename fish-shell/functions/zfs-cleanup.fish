function zfs-cleanup --description 'Clean up test and temporary ZFS datasets'
    set -l options 'h/help' 't/test-be' 's/test-snapshots' 'm/manual-snapshots' 'u/unbootable' 'o/old=' 'f/force' 'n/dry-run' 'q/quiet'
    argparse $options -- $argv
    or return

    if set -q _flag_help
        echo "Usage: zfs-cleanup [options]"
        echo "  -t/--test-be         Clean up test boot environments (test-*)"
        echo "  -s/--test-snapshots  Clean up test snapshots (@test-*)"
        echo "  -m/--manual-snapshots Clean up manual snapshots (@manual-*)"
        echo "  -u/--unbootable      Scan for unbootable pacman snapshots"
        echo "  -o/--old DAYS        Clean up snapshots older than N days (not implemented)"
        echo "  -f/--force           Skip confirmation prompts"
        echo "  -n/--dry-run         Show what would be deleted without doing it"
        echo "  -q/--quiet           Don't show the executed commands"
        echo "  -h/--help            Show this help"
        echo ""
        echo "WARNING: This function can destroy data. Use with caution!"
        return
    end

    if not set -q _flag_test_be; and not set -q _flag_test_snapshots; and not set -q _flag_manual_snapshots; and not set -q _flag_unbootable; and not set -q _flag_old
        echo "Error: No cleanup type specified. Use -h for help."
        echo "Available cleanup types: -t (test BEs), -s (test snapshots), -m (manual snapshots), -u (unbootable snapshots)"
        return 1
    end

    set -l items_to_delete
    set -l description
    set -l destroy_cmd_base

    if set -q _flag_test_be
        if test -z "$ZFS_BE_ROOT"
            echo "Error: ZFS_BE_ROOT environment variable not set"
            return 1
        end

        # Get parent containers only for recursive deletion
        set items_to_delete (zfs list -H -o name -r $ZFS_BE_ROOT | grep "^$ZFS_BE_ROOT/test-" | grep -v "/root\$")
        set description "test boot environments"
        set destroy_cmd_base "sudo zfs destroy -r"
    else if set -q _flag_test_snapshots
        set items_to_delete (zfs list -t snapshot -H -o name | grep '@test-')
        set description "test snapshots"
        set destroy_cmd_base "sudo zfs destroy"
    else if set -q _flag_manual_snapshots
        set items_to_delete (zfs list -t snapshot -H -o name | grep '@manual-')
        set description "manual snapshots"
        set destroy_cmd_base "sudo zfs destroy"
    else if set -q _flag_unbootable
        echo "Scanning for unbootable snapshots..."
        set description "selected unbootable snapshots"
        set destroy_cmd_base "sudo zfs destroy"
        set root_dataset (findmnt -no SOURCE / 2>/dev/null)
        if test -z "$root_dataset"
            echo "Error: Could not determine root dataset"
            return 1
        end

        for snapshot in (zfs list -H -t snapshot -o name -r $root_dataset | grep '@pacman-')
            set temp_mount (mktemp -d)
            # Use zfs mount directly to avoid "bad usage" errors from
            # mount(8) when inspecting snapshots. This handles any required
            # options such as zfsutil automatically.
            if zfs mount -o ro $snapshot $temp_mount >/dev/null ^/dev/null
                if not ls $temp_mount/boot/vmlinuz-* >/dev/null ^/dev/null
                    if set -q _flag_dry_run
                        set items_to_delete $items_to_delete $snapshot
                    else
                        read -l resp -P "Snapshot $snapshot is unbootable. Delete? [y/N] "
                        if test "$resp" = "y" -o "$resp" = "Y"
                            set items_to_delete $items_to_delete $snapshot
                        end
                    end
                end
                zfs umount $temp_mount >/dev/null ^/dev/null
            end
            rm -rf $temp_mount
        end

        if not set -q _flag_dry_run
            set _flag_force 1
        end
    else if set -q _flag_old
        echo "Error: Old snapshot cleanup not yet implemented"
        echo "This would require complex date parsing. Use manual cleanup for now."
        return 1
    end

    if test (count $items_to_delete) -eq 0
        echo "No $description found to clean up."
        return 0
    end

    echo "Found $description:"
    printf "  %s\n" $items_to_delete
    echo
    echo "Total items: "(count $items_to_delete)

    if set -q _flag_dry_run
        echo
        echo "DRY RUN - Commands that would be executed:"
        for item in $items_to_delete
            set -l cmd "$destroy_cmd_base $item"
            set_color yellow
            echo "# $cmd"
            set_color normal
        end
        echo
        echo "Use without --dry-run to actually delete these items"
        return 0
    end

    # Safety confirmations
    if not set -q _flag_force
        echo
        set_color red
        echo "WARNING: This will permanently delete "(count $items_to_delete)" $description"
        set_color normal
        echo "This action cannot be undone!"
        echo

        read -l confirm -P "Type 'DELETE' to confirm: "

        if test "$confirm" != "DELETE"
            echo "Cancelled - confirmation failed"
            return 1
        end

        echo
        read -l final_confirm -P "Are you absolutely sure? [y/N] "

        if test "$final_confirm" != "y" -a "$final_confirm" != "Y"
            echo "Cancelled"
            return 1
        end
    end

    # Perform deletion
    echo
    echo "Deleting $description..."
    set -l deleted_count 0
    set -l failed_count 0

    for item in $items_to_delete
        set -l cmd "$destroy_cmd_base $item"

        if not set -q _flag_quiet
            set_color blue
            echo "# $cmd"
            set_color normal
        end

        if eval $cmd
            set deleted_count (math $deleted_count + 1)
            echo "✓ Deleted: $item"
        else
            set failed_count (math $failed_count + 1)
            echo "✗ Failed to delete: $item"
        end
    end

    echo
    echo "Cleanup complete:"
    echo "  Deleted: $deleted_count"
    if test $failed_count -gt 0
        echo "  Failed: $failed_count"
        return 1
    else
        echo "  All items cleaned up successfully"

        # Suggest ZBM update if we deleted boot environments
        #if set -q _flag_test_be; and test $deleted_count -gt 0
        #    echo
        #    echo "Suggestion: Run 'zfs-be-update-zbm' to update boot menu"
        #end
    end
end
