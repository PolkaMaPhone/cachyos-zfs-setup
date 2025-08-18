function bt-reconnect --description 'Soft reconnect Bluetooth device to renegotiate codecs'
    set device_mac $argv[1]
    
    if test -z "$device_mac"
        echo "No MAC address provided. Here are your Bluetooth devices:"
        echo ""
        bluetoothctl devices
        echo ""
        echo "Usage: bt-reconnect <MAC_ADDRESS>"
        echo "Example: bt-reconnect 4C:87:5D:9E:73:6F"
        return 1
    end
    
    echo "Disconnecting $device_mac..."
    bluetoothctl disconnect $device_mac
    
    echo "Waiting 2 seconds..."
    sleep 2
    
    echo "Reconnecting $device_mac..."
    bluetoothctl connect $device_mac
    
    echo "Codec renegotiation complete!"
end
