function vr-toggle --description "Toggle Sunshine on/off"
    if systemctl --user is-active sunshine -q
        vr-stop
    else
        vr-start
    end
end
