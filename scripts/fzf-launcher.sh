#!/usr/bin/env bash
# fzf-based application launcher for i3
# Based on: https://fearby.com/article/using-fzf-as-a-dmenu-replacement/

# --print-query is used to run a custom command when none of the list is selected.
# --bind=ctrl-space:print-query allows you to execute exactly what you typed with Ctrl+Space
# --bind=tab:replace-query allows you to replace the query with the selected item
OPTS='--info=inline --print-query --bind=ctrl-space:print-query,tab:replace-query'

exec i3-msg -q "exec --no-startup-id $(compgen -c | fzf $OPTS | tail -1)"
