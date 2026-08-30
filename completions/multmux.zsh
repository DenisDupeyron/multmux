#compdef multmux
# Zsh completion for multmux.
# Installed by install.sh; regenerated on every install/update, do not edit.

_multmux() {
    local -a commands
    # Command names come from 'multmux _commands', the same list the
    # dispatcher itself uses, so this never drifts out of sync.
    commands=(${(f)"$(multmux _commands 2>/dev/null)"})

    if (( CURRENT == 2 )); then
        _describe -t commands 'multmux command' commands
        return
    fi

    case "${words[2]}" in
    start)
        compadd -- --no-attach
        ;;
    update)
        compadd -- --dry-run
        ;;
    uninstall)
        compadd -- --config
        ;;
    add)
        _files -/
        ;;
    esac
}
