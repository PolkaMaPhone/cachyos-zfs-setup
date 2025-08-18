function ssh-pushkey --description "Install local ed25519 pubkey to remote hosts"
    set -l keyfile ~/.ssh/id_ed25519.pub
    if not test -f $keyfile
        echo "No $keyfile found"; return 1
    end

    for h in $argv
        echo "==> $h"

        # Prefer ssh-copy-id if available (handles perms & duplicates)
        if type -q ssh-copy-id
            if ssh-copy-id -i $keyfile -o StrictHostKeyChecking=accept-new $h >/dev/null 2>&1
                echo "   ✓ key ensured on $h"
            else
                echo "   ✗ ssh-copy-id failed on $h"
            end
            continue
        end

        # Manual install if ssh-copy-id is unavailable
        if ssh -o StrictHostKeyChecking=accept-new $h "
            set -e
            umask 077
            mkdir -p ~/.ssh
            touch ~/.ssh/authorized_keys
            tmp=\$(mktemp)
            cat > \"\$tmp\"
            if ! grep -qxF -- \"\$(cat \"\$tmp\")\" ~/.ssh/authorized_keys
                cat \"\$tmp\" >> ~/.ssh/authorized_keys
            end
            rm -f \"\$tmp\"
            chmod 700 ~/.ssh
            chmod 600 ~/.ssh/authorized_keys
            if command -v restorecon >/dev/null 2>&1
                restorecon -Rv ~/.ssh >/dev/null 2>&1
            end
        " < $keyfile
            echo "   ✓ key ensured on $h"
        else
            echo "   ✗ failed on $h"
        end
    end
end
