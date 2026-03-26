_omohi_complete() {
  local cur prev cword
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev=""
  if (( COMP_CWORD > 0 )); then
    prev="${COMP_WORDS[COMP_CWORD - 1]}"
  fi
  cword=${COMP_CWORD}

  local top_level_commands="track untrack add rm commit status tracklist version find show tag help"
  local top_level_aliases="-h --help -v --version"
  local tag_commands="ls add rm"
  local commit_options="-m --message -t --tag --dry-run"
  local find_options="-t --tag -d --date"

  if (( cword == 1 )); then
    COMPREPLY=( $(compgen -W "${top_level_commands} ${top_level_aliases}" -- "${cur}") )
    return 0
  fi

  case "${COMP_WORDS[1]}" in
    tag)
      if (( cword == 2 )); then
        COMPREPLY=( $(compgen -W "${tag_commands}" -- "${cur}") )
        return 0
      fi
      return 0
      ;;
    commit)
      case "${prev}" in
        -m|--message|-t|--tag)
          return 0
          ;;
      esac
      COMPREPLY=( $(compgen -W "${commit_options}" -- "${cur}") )
      return 0
      ;;
    find)
      case "${prev}" in
        -t|--tag|-d|--date)
          return 0
          ;;
      esac
      COMPREPLY=( $(compgen -W "${find_options}" -- "${cur}") )
      return 0
      ;;
    status|tracklist|version|help)
      return 0
      ;;
    track|untrack|add|rm|show)
      return 0
      ;;
  esac

  return 0
}

complete -F _omohi_complete omohi
