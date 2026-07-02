#!/bin/bash
unlink_safe "$HOME/.config/nvim"
log_info "Plugin caches kept at ~/.local/share/nvim and ~/.cache/nvim"
log_hint "To clean caches: envup clean --nvim"
