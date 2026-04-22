_omohi_complete() {
  local cur prev cword
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev=""
  if (( COMP_CWORD > 0 )); then
    prev="${COMP_WORDS[COMP_CWORD - 1]}"
  fi
  cword=${COMP_CWORD}

  local top_level_commands="track untrack add rm commit status tracklist version find show journal tag help"
  local top_level_aliases="-h --help -v --version"
  local completion_command="${OMOHI_COMPLETION_COMMAND:-omohi}"

  if (( cword == 1 )); then
    _omohi_collect_candidates
    return 0
  fi

  case "${COMP_WORDS[1]}" in
    tag)
      if (( cword >= 3 )) && [[ "${COMP_WORDS[2]}" == "ls" || "${COMP_WORDS[2]}" == "add" || "${COMP_WORDS[2]}" == "rm" ]]; then
        _omohi_collect_candidates
        return 0
      fi
      _omohi_collect_candidates
      return 0
      ;;
    commit)
      case "${prev}" in
        -m|--message|-t|--tag)
          _omohi_collect_candidates
          return 0
          ;;
      esac
      _omohi_collect_candidates
      return 0
      ;;
    find)
      case "${prev}" in
        -t|--tag|-s|--since|-u|--until|--limit)
          _omohi_collect_candidates
          return 0
          ;;
      esac
      _omohi_collect_candidates
      return 0
      ;;
    tracklist)
      case "${prev}" in
        --output|--field)
          _omohi_collect_candidates
          return 0
          ;;
      esac
      _omohi_collect_candidates
      return 0
      ;;
    status|version|journal)
      return 0
      ;;
    rm)
      if [[ -z "${cur}" || "${cur}" == -* ]]; then
        _omohi_collect_candidates
        return 0
      fi
      _omohi_collect_candidates
      return 0
      ;;
    help|untrack|show)
      _omohi_collect_candidates
      return 0
      ;;
    track)
      compopt -o filenames 2>/dev/null || true
      COMPREPLY=( $(compgen -f -- "${cur}") )
      return 0
      ;;
    add)
      compopt -o filenames 2>/dev/null || true
      if [[ -z "${cur}" || "${cur}" == -* ]]; then
        _omohi_collect_candidates
        return 0
      fi
      COMPREPLY=( $(compgen -f -- "${cur}") )
      return 0
      ;;
    -h|--help|-v|--version)
      return 0
      ;;
  esac

  return 0
}

_omohi_collect_candidates() {
  local completion_command="${OMOHI_COMPLETION_COMMAND:-omohi}"
  local line
  local -a candidates=()

  while IFS= read -r line; do
    candidates+=("${line}")
  done < <("${completion_command}" __complete --index "${COMP_CWORD}" -- "${COMP_WORDS[@]}" 2>/dev/null)

  if (( ${#candidates[@]} == 0 )); then
    COMPREPLY=()
  else
    COMPREPLY=("${candidates[@]}")
  fi
}

complete -F _omohi_complete omohi
