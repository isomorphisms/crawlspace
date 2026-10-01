#!/bin/sh
set -eu

red='\033[1;31m'
green='\033[1;32m'
cyan='\033[1;36m'
yellow='\033[1;33m'
reset='\033[0m'

section() { printf '\n%b== %s ==%b\n' "$cyan" "$1" "$reset"; }
pass() { printf '%bPASS%b %s\n' "$green" "$reset" "$1"; }
warn() { printf '%bWARN%b %s\n' "$yellow" "$reset" "$1" >&2; }
fail() { printf '%bFAIL%b %s\n' "$red" "$reset" "$1" >&2; exit 1; }

usage() {
    cat <<'EOF'
usage: provision_shizuku_rish.sh [--dry-run|--apply] [--bundle DIR]

Install the Crawl Space-controlled Shizuku rish bundle into Termux-private
storage. Removable SD storage is never consulted.

Defaults:
  bundle       runtime/shizuku-rish, then out/shizuku-rish
  install      ~/opt/rish and ~/opt/rish_shizuku.dex
  command      ~/opt/bin/rish
EOF
}

mode=dry_run
bundle=
while [ "$#" -gt 0 ]; do
    case $1 in
        --dry-run) mode=dry_run ;;
        --apply) mode=apply ;;
        --bundle)
            [ "$#" -ge 2 ] || fail '--bundle requires a directory'
            bundle=$2
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; fail "unknown option: $1" ;;
    esac
    shift
done

: "${HOME:?HOME is required}"
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

if [ -z "$bundle" ]; then
    for candidate in "$repo_root/runtime/shizuku-rish" "$repo_root/out/shizuku-rish"; do
        if [ -f "$candidate/manifest.tsv" ]; then
            bundle=$candidate
            break
        fi
    done
fi

[ -n "$bundle" ] || {
    warn 'No Crawl Space-controlled Shizuku bundle is present yet'
    printf 'shizuku_rish\tpending\treason=no-controlled-bundle\n'
    exit 0
}

manifest=$bundle/manifest.tsv
rish_source=$bundle/rish
dex_source=$bundle/rish_shizuku.dex
[ -f "$manifest" ] || fail "missing bundle manifest: $manifest"
[ -s "$rish_source" ] || fail "missing bundle launcher: $rish_source"
[ -s "$dex_source" ] || fail "missing bundle DEX: $dex_source"

value() {
    awk -F '\t' -v key="$1" '$1 == key { print $2; found=1 } END { if (!found) exit 1 }' "$manifest"
}

schema=$(value schema)
[ "$schema" = crawlspace-shizuku-rish-v1 ] || fail "unknown bundle schema: $schema"
shizuku_commit=$(value shizuku_commit)
expected_rish_sha=$(value rish_sha256)
expected_dex_sha=$(value dex_sha256)
actual_rish_sha=$(sha256sum "$rish_source" | awk '{print $1}')
actual_dex_sha=$(sha256sum "$dex_source" | awk '{print $1}')
[ "$actual_rish_sha" = "$expected_rish_sha" ] || fail 'rish hash mismatch'
[ "$actual_dex_sha" = "$expected_dex_sha" ] || fail 'rish_shizuku.dex hash mismatch'

install_dir=${CRAWLSPACE_SHIZUKU_INSTALL_DIR:-"$HOME/opt"}
bin_dir=${CRAWLSPACE_SHIZUKU_BIN_DIR:-"$HOME/opt/bin"}
state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
state_dir=$state_home/crawlspace/shizuku
application_id=${CRAWLSPACE_RISH_APPLICATION_ID:-com.termux}

case $application_id in
    ''|*[!A-Za-z0-9._-]*) fail "invalid terminal application id: $application_id" ;;
esac

temporary=$(mktemp -d "${TMPDIR:-$HOME/.cache}/crawlspace-rish.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

launcher=$temporary/rish
if grep -F 'RISH_APPLICATION_ID="PKG"' "$rish_source" >/dev/null 2>&1; then
    sed "s/RISH_APPLICATION_ID=\"PKG\"/RISH_APPLICATION_ID=\"$application_id\"/"         "$rish_source" > "$launcher"
elif grep -F "RISH_APPLICATION_ID=\"$application_id\"" "$rish_source" >/dev/null 2>&1; then
    cp "$rish_source" "$launcher"
else
    fail 'controlled rish launcher lacks the expected application-id assignment'
fi
chmod 0500 "$launcher"

section 'Crawl Space controlled Shizuku rish'
printf 'mode=%s\n' "$mode"
printf 'bundle=%s\n' "$bundle"
printf 'shizuku_commit=%s\n' "$shizuku_commit"
printf 'install_dir=%s\n' "$install_dir"
printf 'removable_storage=not_required\n'

if [ "$mode" = dry_run ]; then
    printf 'would_install_rish\t%s\n' "$install_dir"
    printf 'would_install_rish_command\t%s/rish\n' "$bin_dir"
    pass 'controlled Shizuku rish bundle verified'
    exit 0
fi

mkdir -p "$install_dir" "$bin_dir" "$state_dir"
if [ -e "$bin_dir/rish" ] && ! grep -F '# crawlspace controlled shizuku rish' "$bin_dir/rish" >/dev/null 2>&1; then
    fail "$bin_dir/rish exists and is not Crawl Space's wrapper"
fi

rish_tmp=$install_dir/.rish.crawlspace.$$
dex_tmp=$install_dir/.rish_shizuku.dex.crawlspace.$$
wrapper_tmp=$bin_dir/.rish.crawlspace.$$
receipt_tmp=$state_dir/.installed.tsv.$$

cp "$launcher" "$rish_tmp"
cp "$dex_source" "$dex_tmp"
chmod 0500 "$rish_tmp"
chmod 0400 "$dex_tmp"

{
    printf '%s\n' '#!/system/bin/sh'
    printf '%s\n' '# crawlspace controlled shizuku rish'
    printf "exec /system/bin/sh '%s/rish' \"\$@\"\n" "$install_dir"
} > "$wrapper_tmp"
chmod 0500 "$wrapper_tmp"

mv "$rish_tmp" "$install_dir/rish"
mv "$dex_tmp" "$install_dir/rish_shizuku.dex"
mv "$wrapper_tmp" "$bin_dir/rish"

{
    printf 'schema\tcrawlspace-shizuku-install-v1\n'
    printf 'shizuku_commit\t%s\n' "$shizuku_commit"
    printf 'bundle\t%s\n' "$bundle"
    printf 'application_id\t%s\n' "$application_id"
    printf 'rish_sha256\t%s\n' "$actual_rish_sha"
    printf 'dex_sha256\t%s\n' "$actual_dex_sha"
} > "$receipt_tmp"
chmod 0600 "$receipt_tmp"
mv "$receipt_tmp" "$state_dir/installed.tsv"

pass "installed controlled rish pair in $install_dir"
pass "installed rish command at $bin_dir/rish"

if [ "${CRAWLSPACE_SHIZUKU_SKIP_RUNTIME_PROBE:-0}" = 1 ]; then
    printf 'shizuku_rish_runtime\tnot-probed\n'
    exit 0
fi

status=0
output=
if command -v timeout >/dev/null 2>&1; then
    output=$(timeout 8 "$bin_dir/rish" -c 'id -u' 2>&1) || status=$?
else
    output=$("$bin_dir/rish" -c 'id -u' 2>&1) || status=$?
fi

if [ "$status" -eq 0 ] && printf '%s\n' "$output" | grep -Fx 2000 >/dev/null 2>&1; then
    pass 'rish reached Shizuku shell uid 2000'
    printf 'shizuku_rish_runtime\tPASS\tuid=2000\n'
else
    first=$(printf '%s\n' "$output" | sed -n '1p')
    warn 'controlled rish is installed but Shizuku is not reachable yet; pair/start the manager and rerun'
    printf 'shizuku_rish_runtime\tpending\tstatus=%s\t%s\n' "$status" "$first"
fi
