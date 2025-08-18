function vr-logs --description "Follow Sunshine service logs"
    journalctl --user -u sunshine -f
end
