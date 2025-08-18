function bt-bose --description 'Reconnect Bose headphones to renegotiate codecs'
    echo "Reconnecting Bose (Sylvester)..."
    bluetoothctl disconnect 4C:87:5D:9E:73:6F
    sleep 2
    bluetoothctl connect 4C:87:5D:9E:73:6F
    echo "Done! Check audio profile in System Settings if needed."
end
