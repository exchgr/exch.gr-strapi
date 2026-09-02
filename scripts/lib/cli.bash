# scripts/lib/cli.bash — CLI argument parsing ONLY: turns flags into the
# WANT_* selection booleans (+ DRY_RUN) that the orchestrator (upgrade.sh)
# reads to decide which phases run. Owns the usage text and the usage-error
# convention (message + usage on stderr, exit 2). No phase logic here.
# Dependencies: common.bash.
# shellcheck source=scripts/lib/common.bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.bash"

# Selection result consumed by upgrade.sh's main: 1 = phase requested.
WANT_ALL=0
WANT_YARN=0
WANT_NODE=0
WANT_DEPS=0
WANT_TRANSITIVE=0
WANT_TYPES=0
WANT_WORKFLOWS=0
WANT_DOCKERFILE=0

usage() {
  cat <<'EOF'
Usage: bash scripts/upgrade.sh [options]

Preflight always runs first, then exactly the selected phases in canonical
order (yarn -> node -> deps -> transitive -> types -> workflows -> docker),
then a summary. No selection is an error: choose the blast radius.

  -a, --all            every phase (yarn node deps transitive types workflows docker)
  -y, --yarn           yarn phase: yarn set version berry + install
  -n, --node           node phase: asdf LTS pin + engines rewrite
  -d, --dependencies   deps phase: Strapi plugin dependency bumps
  -t, --transitive     transitive phase: yarn up -R + dedupe
  -s, --strapi-types   types phase: Strapi type regeneration
  -w, --workflows      workflows phase: GitHub Actions action bumps
  -i, --docker         dockerfile phase: base image bumps
  -r, --dry-run        print every mutation without applying it
  -h, --help           show this help and exit
EOF
}

usage_error() {
  warn "$*"
  usage >&2
  exit 2
}

# The ONE place long flags are spelled: long -> single letter consumed by the
# getopts loop (r is the internal letter for --dry-run; only -r/--dry-run).
map_long_option() {
  case "$1" in
    --all) printf 'a' ;;
    --yarn) printf 'y' ;;
    --node) printf 'n' ;;
    --dependencies) printf 'd' ;;
    --transitive) printf 't' ;;
    --strapi-types) printf 's' ;;
    --workflows) printf 'w' ;;
    --docker) printf 'i' ;;
    --dry-run) printf 'r' ;;
    --help) printf 'h' ;;
    *) return 1 ;;
  esac
}

parse_args() {
  WANT_ALL=0 WANT_YARN=0 WANT_NODE=0 WANT_DEPS=0 WANT_TRANSITIVE=0
  WANT_TYPES=0 WANT_WORKFLOWS=0 WANT_DOCKERFILE=0
  OPTIND=1
  local -a normalized=()
  local arg short
  while (( $# )); do
    arg="$1"
    shift
    if [[ "$arg" == --* ]]; then
      short="$(map_long_option "$arg")" || usage_error "unknown option: $arg"
      normalized+=("-$short")
    else
      normalized+=("$arg")
    fi
  done

  local optspec=":ayndtswirh" opt
  # ${arr[@]+...} keeps bash 3.2 happy about empty arrays under set -u.
  while getopts "$optspec" opt ${normalized[@]+"${normalized[@]}"}; do
    case "$opt" in
      a) WANT_ALL=1 ;;
      y) WANT_YARN=1 ;;
      n) WANT_NODE=1 ;;
      d) WANT_DEPS=1 ;;
      t) WANT_TRANSITIVE=1 ;;
      s) WANT_TYPES=1 ;;
      w) WANT_WORKFLOWS=1 ;;
      i) WANT_DOCKERFILE=1 ;;
      r) export DRY_RUN=1 ;;
      h)
        usage
        exit 0
        ;;
      \?) usage_error "unknown option: -${OPTARG}" ;;
    esac
  done
  if (( OPTIND <= ${#normalized[@]} )); then
    usage_error "unexpected argument: ${normalized[OPTIND - 1]}"
  fi
  if (( WANT_ALL + WANT_YARN + WANT_NODE + WANT_DEPS + WANT_TRANSITIVE + WANT_TYPES + WANT_WORKFLOWS + WANT_DOCKERFILE == 0 )); then
    usage_error "no phases selected (use --all for everything)"
  fi
}
