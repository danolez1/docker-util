# docker-util

Small interactive helpers for people who run a lot of Docker Compose stacks
on one machine. You pick projects from a list instead of typing names, and
anything that is still running is left alone.

```
docker-list    Show compose projects and containers outside compose
docker-stop    Pick running compose projects to stop, then pick which to delete
docker-prune   Clean stopped containers, unused images, volumes and build cache
docker-help    Show the command list
```

## Install

Run it once without installing:

```sh
npx @danolez/docker-util list
npx @danolez/docker-util stop
npx @danolez/docker-util prune --dry-run
```

Or install it so the `docker-*` commands are on your PATH:

```sh
npm install -g @danolez/docker-util
```

Straight from GitHub works too, no registry needed:

```sh
npx github:danolez1/docker-util help
```

Works on macOS and Linux. It needs `bash` (the 3.2 that ships with macOS is
fine) and the `docker` CLI. Node is only used to install it.

## Picking things

Every choice is a menu. Nothing asks you to type a name or a number.

The tool uses [fzf](https://github.com/junegunn/fzf) if it is installed, then
[gum](https://github.com/charmbracelet/gum), and otherwise falls back to its
own arrow-key menu:

| key | action |
| --- | --- |
| up / down (or k / j) | move |
| space | mark or unmark (multi-select menus) |
| enter | confirm |
| q or esc | abort, nothing is changed |

In fzf and gum, multi-select menus start with a `(none)` row. Confirm on it
to pick nothing. Yes/No questions default to No.

Force a picker with `DOCKER_UTIL_PICKER=fzf|gum|builtin`.

## docker-stop

1. Lists every compose project with at least one running container. Mark the
   ones to stop.
2. Stops them, then lists the same projects again so you can mark which ones
   to delete. Deleting removes their containers and networks.
3. If you deleted anything, asks whether to keep or delete the project
   volumes. Keeping them is the first option.

`docker-stop --dry-run` shows the commands without running them.

## docker-prune

Removes stopped containers, unused images, anonymous volumes and dangling
build cache. Compose projects with a running container are always kept, and
so are the images they use.

Before removing anything it asks:

- which stopped compose projects to keep,
- which unused named volumes to delete (none by default, since fixed-name
  volumes often hold data you care about),
- whether to go ahead with the plan it prints.

```
-n, --dry-run            Show what would be removed, remove nothing
-y, --yes                Skip prompts: remove all stopped projects, keep all named volumes
    --keep-image REGEX   Never remove images whose repo:tag matches REGEX (repeatable)
    --cache-cap SIZE     Build cache to keep, e.g. 10GB (default 20GB)
    --tmp-prefix PREFIX  Also delete $TMPDIR/PREFIX* dirs older than 24h (repeatable)
    --no-mole            Do not offer 'mo clean' afterwards
```

If [Mole](https://github.com/tw93/Mole) is installed, it offers to run
`mo clean` at the end.

### Config

Defaults can live in `~/.config/docker-util/config` (or `$DOCKER_UTIL_CONFIG`).
It is plain shell:

```sh
# Images you can't pull again, e.g. mirrors of deleted upstream tags
KEEP_IMAGE_PATTERN='^(registry\.example\.com/|myorg/)'
CACHE_CAP=20GB
# Scratch dirs your test suites leave in $TMPDIR
TMP_PREFIXES="myapp-test- e2e-run-"
TMP_MAX_AGE_MIN=1440
```

`DOCKER_UTIL_KEEP_IMAGES`, `DOCKER_UTIL_CACHE_CAP` and
`DOCKER_UTIL_TMP_PREFIXES` override the file, and flags override both.

## Development

```sh
npm test       # runs test/run.sh against a stub docker, no daemon needed
npm run lint   # shellcheck
```

## License

MIT
