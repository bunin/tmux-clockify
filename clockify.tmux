#!/usr/bin/env bash

set_tmux_option() {
    local option="$1"
    local value="$2"
    tmux set-option -gq "$option" "$value"
}

get_tmux_option() {
    local option=$1
    local default_value=$2
    local option_value="$(tmux show-option -gqv "$option")"

    [[ -z "$option_value" ]] && echo $default_value || echo $option_value
}

clockify_interpolation="\#{clockify}"
clockify="#(clockify-cli show -f'{{ .Project.Name }} / {{ .Description }} ')"
clockify+="[#(clockify-cli show -D)]"

do_interpolation() {
    local input=$1
    local result=""

    result=${input/$clockify_interpolation/$clockify}

    echo "$result"

}

update_tmux_option() {
    local option=$1
    local option_value=$(get_tmux_option "$option")
    set_tmux_option "$option" "$(do_interpolation "$option_value")"
}

main() {
    if ! command -v clockify-cli 2>&1 >/dev/null ; then
        return
    fi

    update_tmux_option "status-right"
    update_tmux_option "status-left"
}

main
