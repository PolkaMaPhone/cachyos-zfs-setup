function vr-start --description "Start Sunshine VR streaming server"
    systemctl --user start sunshine
    echo "✓ Sunshine started - Web UI: https://localhost:47990"
    echo "✓ Ready for Moonlight connection"
end
