function vr-restart --description "Restart Sunshine service"
    systemctl --user restart sunshine
    echo "✓ Sunshine restarted"
end
