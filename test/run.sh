#!/usr/bin/env bash
# Checks are eval strings, so single-quoted expansions and eval-only vars are intended.
# shellcheck disable=SC2016,SC2034
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export PATH="$ROOT/bin:$ROOT/test/stub:/usr/bin:/bin"
export STUB_LOG="$WORK/calls"
export XDG_CONFIG_HOME="$WORK/config"
export TMPDIR="$WORK/tmp"
export DOCKER_UTIL_PICKER=builtin
export DOCKER_UTIL_TTY="$WORK/keys"
mkdir -p "$TMPDIR"
: > "$DOCKER_UTIL_TTY"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
called() { grep -qxF -- "$1" "$STUB_LOG"; }
reset() { : > "$STUB_LOG"; }
# shellcheck disable=SC2059
keys() { printf "$1" > "$DOCKER_UTIL_TTY"; }

pkg_version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$ROOT/package.json")
for cmd in docker-util docker-list docker-stop docker-prune docker-help; do
  check "$cmd --version matches package.json" '[ "$($cmd --version)" = "$pkg_version" ]'
done
check "docker-help lists every command" \
  'out=$(docker-help); for c in list stop prune help; do grep -q "docker-$c" <<<"$out" || exit 1; done'
check "docker-util dispatches subcommands" 'docker-util prune --help | grep -q "^Usage: docker-prune"'
docker-util bogus >/dev/null 2>&1; rc=$?
check "docker-util unknown command exits 2" '[ "$rc" = 2 ]'
ln -s "$ROOT/bin/docker-help" "$WORK/linked-help"
check "works when invoked through a symlink" '"$WORK/linked-help" | grep -q docker-stop'

docker-prune --bogus >/dev/null 2>&1; rc=$?
check "unknown option exits 2" '[ "$rc" = 2 ]'
docker-prune --cache-cap >/dev/null 2>&1; rc=$?
check "missing option value exits 2" '[ "$rc" = 2 ]'

out=$(docker-list 2>&1)
check "list shows running project" 'grep -qE "web +running +1/1 up" <<<"$out"'
check "list shows stopped project" 'grep -qE "old +stopped +0/1 up" <<<"$out"'
check "list shows loose container" 'grep -qE "loose +exited +redis" <<<"$out"'

reset
out=$(docker-prune --dry-run --yes --no-mole 2>&1)
check "dry run removes nothing" '! grep -qE "^(rm|volume rm|image rm|volume prune|builder prune -af)" "$STUB_LOG"'
check "dry run lists stopped container" 'grep -q "would run: docker rm -v c-old c-loose" <<<"$out"'
check "running project image kept" '! grep -q "image rm nginx" <<<"$out"'
check "unused image removed" 'grep -q "would run: docker image rm redis:7" <<<"$out"'
check "empty keep pattern keeps nothing extra" 'grep -q "would run: docker image rm myreg.io/app:1" <<<"$out"'
check "digest-pinned image removed by id" 'grep -q "would run: docker image rm sha256:pinned" <<<"$out"'
check "--yes deletes no named volumes" '! grep -q "volume rm" <<<"$out"'
check "cache cap uses max-used-space" 'grep -q "builder prune -af --max-used-space 20GB" <<<"$out"'

reset
docker-prune --yes --no-mole --keep-image '^myreg\.io/' --cache-cap 5GB >/dev/null 2>&1
check "real run removes stopped containers" 'called "rm -v c-old c-loose"'
check "real run removes unused image" 'called "image rm redis:7"'
check "--keep-image protects matching image" '! called "image rm myreg.io/app:1"'
check "--cache-cap applied" 'called "builder prune -af --max-used-space 5GB"'
check "running container untouched" '! grep "^rm" "$STUB_LOG" | grep -q c-web'

mkdir -p "$XDG_CONFIG_HOME/docker-util"
echo "KEEP_IMAGE_PATTERN='^redis'" > "$XDG_CONFIG_HOME/docker-util/config"
reset
out=$(docker-prune -n -y --no-mole 2>&1)
check "config file keep pattern honoured" '! grep -q "image rm redis:7" <<<"$out"'
rm -rf "$XDG_CONFIG_HOME/docker-util"

mkdir -p "$TMPDIR/mytest-old" "$TMPDIR/mytest-new" "$TMPDIR/other-old"
touch -t 202001010000 "$TMPDIR/mytest-old" "$TMPDIR/other-old"
docker-prune -y --no-mole --tmp-prefix mytest- >/dev/null 2>&1
check "old prefixed tmp dir removed" '[ ! -d "$TMPDIR/mytest-old" ]'
check "fresh prefixed tmp dir kept" '[ -d "$TMPDIR/mytest-new" ]'
check "unprefixed tmp dir kept" '[ -d "$TMPDIR/other-old" ]'

# Menu keys: space marks, j moves down, enter confirms, q aborts.
reset; keys '\n\n\n'
out=$(docker-prune --no-mole 2>&1)
check "prune confirm defaults to No" 'grep -q "Nothing removed." <<<"$out" && ! called "volume prune -f"'

reset; keys 'q'
docker-prune --no-mole >/dev/null 2>&1; rc=$?
check "prune picker abort exits 130 and removes nothing" '[ "$rc" = 130 ] && ! called "volume prune -f"'

reset; keys ' \nj\n'
docker-prune --no-mole >/dev/null 2>&1
check "prune keeps project marked in menu" '! called "rm -v c-old c-loose" && called "rm -v c-loose"'

reset; keys '\n'
out=$(docker-stop 2>&1)
check "stop with nothing marked stops nothing" 'grep -q "Nothing stopped." <<<"$out" && ! grep -q "^stop" "$STUB_LOG"'

reset; keys 'j \n\n'
out=$(docker-stop 2>&1)
check "stop stops only marked project" 'called "stop c-web" && ! called "stop c-api"'
check "stop without delete pick deletes nothing" 'grep -q "nothing deleted" <<<"$out" && ! grep -q "^rm" "$STUB_LOG"'

reset; keys ' j \nj \n\n'
docker-stop >/dev/null 2>&1
check "stop handles multiple projects" 'called "stop c-api" && called "stop c-web"'
check "delete removes containers and networks" 'called "rm -v c-web" && called "network rm n-web" && ! called "rm -v c-api"'
check "volumes kept by default" '! called "volume rm webdata"'

reset; keys 'j \nj \nj\n'
docker-stop >/dev/null 2>&1
check "volumes deleted when picked" 'called "volume rm webdata"'

reset; keys ' \n'
out=$(docker-stop -n 2>&1)
check "stop dry run changes nothing" '! grep -qE "^(stop|rm|network rm)" "$STUB_LOG" && grep -q "would run: docker stop c-api" <<<"$out"'

echo
if [ "$fails" = 0 ]; then echo "all tests passed"; else echo "$fails failed"; exit 1; fi
