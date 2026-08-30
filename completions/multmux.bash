# Bash completion for multmux.
# Installed by install.sh; regenerated on every install/update, do not edit.

_multmux() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"

    if ((COMP_CWORD == 1)); then
        mapfile -t COMPREPLY < <(compgen -W "$(multmux _commands 2>/dev/null)" -- "${cur}")
        return 0
    fi

    # Command names come from 'multmux _commands', the same list the
    # dispatcher itself uses, so this never drifts out of sync.
    case "${COMP_WORDS[1]}" in
    start)
        [[ "${prev}" == "start" ]] && mapfile -t COMPREPLY < <(compgen -W "--no-attach" -- "${cur}")
        ;;
    update)
        [[ "${prev}" == "update" ]] && mapfile -t COMPREPLY < <(compgen -W "--dry-run" -- "${cur}")
        ;;
    uninstall)
        [[ "${prev}" == "uninstall" ]] && mapfile -t COMPREPLY < <(compgen -W "--config" -- "${cur}")
        ;;
    add)
        [[ "${prev}" == "add" ]] && mapfile -t COMPREPLY < <(compgen -d -- "${cur}")
        ;;
    esac
}
complete -F _multmux multmux
