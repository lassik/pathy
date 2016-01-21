# This script is meant to be sourced from sh.
#
# Tested to work on bash, zsh.

PATHY_HELPER= # This is filled in by the build script.

pathy() {
    local fd3output
    exec 4>&1
    IFS= fd3output=$($PATHY_HELPER user "$@" 3>&1 >&4) || return
    eval "$fd3output"
}

if [ -n "${BASH_VERSION:-}" ]; then
    _pathy_complete() {
        IFS=$'\n' COMPREPLY=($(compgen -W "$($PATHY_HELPER complete "$COMP_CWORD" "${COMP_WORDS[@]}")" -- "${COMP_WORDS[COMP_CWORD]}"))
    }
    complete -F _pathy_complete pathy
fi
