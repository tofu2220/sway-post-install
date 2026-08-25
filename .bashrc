#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
RESET='\[\e[0m\]'
BOLD='\[\e[1m\]'
BLUE='\[\e[38;5;75m\]'
GREEN='\[\e[38;5;114m\]'
PURPLE='\[\e[38;5;141m\]'
GRAY='\[\e[38;5;245m\]'

PS1="${GRAY}╭─${GREEN}\u${GRAY}@${BLUE}\h ${PURPLE}\w${RESET}\n${GRAY}╰─${BOLD}\$ ${RESET}"

export EDITOR="helix"

eval "$(zoxide init bash)"

function y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"

    yazi "$@" --cwd-file="$tmp"

    if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        cd -- "$cwd"
    fi

    rm -f -- "$tmp"
}
