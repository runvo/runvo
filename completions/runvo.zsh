#compdef runvo
# Zsh completion for runvo
# Place in your fpath or source directly:
#   fpath=(/path/to/completions $fpath) && compinit

_runvo() {
  local -a commands project_names

  commands=(
    'setup:Setup wizard'
    'new:Create new project'
    'add:Register existing project'
    'clone:Clone repo & register'
    'remove:Remove project'
    'list:List projects'
    'status:Git status dashboard'
    'config:Edit config file'
    'edit:Open project in editor'
    'prompts:List all prompts'
    'prompt:Manage prompts (add/edit/rm)'
    'send:Send prompt to session'
    'peek:View session output'
    'attach:Attach to session'
    'sessions:Active tmux sessions'
    'kill:Kill session(s)'
    'history:Recent history'
    'ssh-auto:Toggle SSH auto-launch'
    'doctor:Check system health'
    'update:Check & install updates'
    'version:Show version'
    'help:Full help'
  )

  # Load project names
  local projects_file="${RUNVO_DIR:-$HOME/.runvo}/projects.conf"
  if [[ -f "$projects_file" ]]; then
    while IFS='|' read -r name rest; do
      [[ "$name" =~ ^[[:space:]]*# ]] && continue
      [[ -z "$name" ]] && continue
      name="${name## }"; name="${name%% }"
      project_names+=("$name")
    done < "$projects_file"
  fi

  case "$CURRENT" in
    2)
      _describe 'command' commands
      [[ ${#project_names[@]} -gt 0 ]] && _describe 'project' project_names
      ;;
    3)
      case "${words[2]}" in
        prompt)
          local -a sub=('add:Create custom prompt' 'edit:Edit prompt' 'rm:Delete prompt')
          _describe 'subcommand' sub
          ;;
        remove|rm|kill|attach|peek|edit|send)
          _describe 'project' project_names
          [[ "${words[2]}" == "kill" ]] && _describe 'target' '(all:Kill all sessions)'
          ;;
      esac
      ;;
  esac
}

_runvo "$@"
