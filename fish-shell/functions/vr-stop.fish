function vr-stop --description "Stop Sunshine and release VRAM"
    systemctl --user stop sunshine
    echo "✓ Sunshine stopped - VRAM released"
end
