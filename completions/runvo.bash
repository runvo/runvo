# Bash completion for runvo
# Source this file or add to ~/.bashrc:
#   source /path/to/completions/runvo.bash

_runvo_completions() {
  local cur prev commands
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  commands="setup new add clone remove list status config edit
            prompts prompt send peek attach sessions kill
            history ssh-auto doctor update version help"

  # First argument: commands or project numbers
  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )

    # Also suggest project names
    local projects_file="${RUNVO_DIR:-$HOME/.runvo}/projects.conf"
    if [[ -f "$projects_file" ]]; then
      local names
      names=$(grep -vE '^[[:space:]]*#|^$' "$projects_file" 2>/dev/null | cut -d'|' -f1 | xargs)
      COMPREPLY+=( $(compgen -W "$names" -- "$cur") )
    fi
    return
  fi

  # Subcommands
  case "$prev" in
    prompt)
      COMPREPLY=( $(compgen -W "add edit rm" -- "$cur") )
      ;;
    remove|rm|kill|attach|peek|edit)
      # Suggest project names
      local projects_file="${RUNVO_DIR:-$HOME/.runvo}/projects.conf"
      if [[ -f "$projects_file" ]]; then
        local names
        names=$(grep -vE '^[[:space:]]*#|^$' "$projects_file" 2>/dev/null | cut -d'|' -f1 | xargs)
        COMPREPLY=( $(compgen -W "$names all" -- "$cur") )
      fi
      ;;
  esac
}

complete -F _runvo_completions runvo
