function vr-status --description "Check Sunshine service status"
    systemctl --user status sunshine --no-pager
end
