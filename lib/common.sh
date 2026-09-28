# shellcheck shell=bash
# Shared by every docker-util command so they all pick things the same way.

# shellcheck disable=SC2034
DOCKER_UTIL_VERSION="1.0.0"
NONE="(none)"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
dim() { printf '\033[2m%s\033[0m\n' "$*"; }
# fd 3 keeps dry-run output visible past callers that silence the real command.
exec 3>&1
run() {
  if [ "$DRY_RUN" = 1 ]; then dim "  would run: $*" >&3; else "$@"; fi
}

in_list() { printf '%s\n' "$2" | grep -qxF -- "$1"; }

require_docker() {
  command -v docker >/dev/null 2>&1 || { echo "docker not found on PATH." >&2; exit 1; }
  docker info >/dev/null 2>&1 || { echo "Docker daemon not reachable." >&2; exit 1; }
}

# Opened once so every menu in a run shares one read offset (lets tests script keystrokes).
{ exec 4<"${DOCKER_UTIL_TTY:-/dev/tty}"; } 2>/dev/null || true

picker() {
  local want="${DOCKER_UTIL_PICKER:-auto}"
  if [ "$want" = auto ]; then
    if command -v fzf >/dev/null 2>&1; then want=fzf
    elif command -v gum >/dev/null 2>&1; then want=gum
    else want=builtin; fi
  fi
  echo "$want"
}

# Arrow-key menu for machines without fzf or gum. Args: multi(0|1) prompt items...
_menu() {
  local multi="$1" prompt="$2"; shift 2
  local opts=("$@") n=$# cur=0 i key rest mark ptr hint drawn=0
  local sel=()
  [ "$n" -eq 0 ] && return 0
  # Runs in a $() subshell, so this only restores the cursor for this menu.
  trap 'printf "\033[?25h" >&2' EXIT
  for ((i = 0; i < n; i++)); do sel[i]=0; done
  hint="up/down move, enter select, q abort"
  [ "$multi" = 1 ] && hint="up/down move, space mark, enter confirm, q abort"
  printf '\033[?25l\033[1m%s\033[0m  \033[2m%s\033[0m\n' "$prompt" "$hint" >&2
  while :; do
    [ "$drawn" = 1 ] && printf '\033[%dA' "$n" >&2
    for ((i = 0; i < n; i++)); do
      ptr="  "; [ "$i" = "$cur" ] && ptr="> "
      mark=""
      if [ "$multi" = 1 ]; then mark="[ ] "; [ "${sel[i]}" = 1 ] && mark="[x] "; fi
      printf '\033[2K%s%s%s\n' "$ptr" "$mark" "${opts[i]}" >&2
    done
    drawn=1
    IFS= read -rsn1 key 2>/dev/null <&4 || key=q
    if [ "$key" = $'\033' ]; then
      rest=""
      IFS= read -rsn2 -t 1 rest 2>/dev/null <&4
      case "$rest" in "[A") key=k ;; "[B") key=j ;; *) key=q ;; esac
    fi
    case "$key" in
      k) cur=$(((cur - 1 + n) % n)) ;;
      j) cur=$(((cur + 1) % n)) ;;
      " ") [ "$multi" = 1 ] && sel[cur]=$((1 - sel[cur])) ;;
      "") break ;;
      q) printf '\033[?25h' >&2; return 130 ;;
    esac
  done
  printf '\033[?25h' >&2
  if [ "$multi" = 1 ]; then
    for ((i = 0; i < n; i++)); do [ "${sel[i]}" = 1 ] && printf '%s\n' "${opts[i]}"; done
  else
    printf '%s\n' "${opts[cur]}"
  fi
  return 0
}

# Newline-separated items in, picked items out. Non-zero only on abort.
pick_many() {
  local prompt="$1" items="$2" picked rc line
  local arr=()
  [ -z "$items" ] && return 0
  [ "$ASSUME_YES" = 1 ] && return 0
  case "$(picker)" in
    # fzf and gum return the highlighted row on a bare ENTER, so (none) is the only way to pick nothing.
    fzf)
      picked=$(printf '%s\n%s\n' "$NONE" "$items" | fzf --multi --prompt="$prompt> " \
        --height=40% --reverse --header="TAB to mark, ENTER to confirm, ESC to abort")
      rc=$? ;;
    gum)
      picked=$(printf '%s\n%s\n' "$NONE" "$items" | gum choose --no-limit --header="$prompt")
      rc=$? ;;
    *)
      while IFS= read -r line; do [ -n "$line" ] && arr+=("$line"); done <<<"$items"
      [ ${#arr[@]} -eq 0 ] && return 0
      picked=$(_menu 1 "$prompt" "${arr[@]}")
      rc=$? ;;
  esac
  [ "$rc" -ne 0 ] && return 130
  printf '%s\n' "$picked" | grep -vxF -- "$NONE" | sed '/^$/d'
  return 0
}

# Items as arguments, one picked item out. Non-zero only on abort.
pick_one() {
  local prompt="$1"; shift
  case "$(picker)" in
    fzf) printf '%s\n' "$@" | fzf --prompt="$prompt> " --height=40% --reverse \
      --header="ENTER to select, ESC to abort" ;;
    gum) gum choose --header="$prompt" "$@" ;;
    *) _menu 0 "$prompt" "$@" ;;
  esac
}

confirm() {
  local answer
  [ "$ASSUME_YES" = 1 ] && return 0
  answer=$(pick_one "$1" No Yes) || return 1
  [ "$answer" = Yes ]
}

compose_projects() {
  docker ps "$@" --format '{{.Label "com.docker.compose.project"}}' | sed '/^$/d' | sort -u
}
