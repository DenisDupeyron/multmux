#compdef multmux
# Zsh completion for multmux.
# Installed by install.sh; regenerated on every install/update, do not edit.

_multmux() {
    local -a commands
    # Command names come from 'multmux _commands', the same list the
    # dispatcher itself uses, so this never drifts out of sync.
    commands=(${(f)"$(multmux _commands 2>/dev/null)"})

    local curcontext="$curcontext" state

    # Standard _arguments -C / ->state dispatch, not a hand-rolled
    # _describe+case combo: this is what git/docker/kubectl-style
    # completions use, and it interoperates correctly with completion-UI
    # plugins (fzf-tab, zsh-autocomplete) that hook into _arguments.
    _arguments -C \
        '1: :->command' \
        '*:: :->args'

    case "${state}" in
    command)
        _describe -t commands 'multmux command' commands
        ;;
    args)
        case "${words[1]}" in
        start)
            _values 'option' --no-attach
            ;;
        update)
            _values 'option' --dry-run
            ;;
        add)
            _files -/
            ;;
        esac
        ;;
    esac
}
