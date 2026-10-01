#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

home=$tmp/home
bundle=$tmp/bundle
mkdir -p "$home/.cache" "$bundle"

cat > "$bundle/rish" <<'EOF'
#!/system/bin/sh
BASEDIR=$(dirname "$0")
DEX="$BASEDIR"/rish_shizuku.dex
[ -z "$RISH_APPLICATION_ID" ] && export RISH_APPLICATION_ID="PKG"
exec /system/bin/app_process -Djava.class.path="$DEX" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "$@"
EOF
printf '%s\n' controlled-dex > "$bundle/rish_shizuku.dex"
rish_sha=$(sha256sum "$bundle/rish" | awk '{print $1}')
dex_sha=$(sha256sum "$bundle/rish_shizuku.dex" | awk '{print $1}')
cat > "$bundle/manifest.tsv" <<EOF
schema	crawlspace-shizuku-rish-v1
crawlspace_commit	test
shizuku_commit	b844bc491f1790c72328e1a8e5b2349f8978f0ea
rish_sha256	$rish_sha
dex_sha256	$dex_sha
EOF

dry=$(HOME="$home" TMPDIR="$home/.cache"     sh "$root/scripts/provision_shizuku_rish.sh" --dry-run --bundle "$bundle")
printf '%s\n' "$dry" | grep -F 'removable_storage=not_required' >/dev/null
printf '%s\n' "$dry" | grep -F 'would_install_rish' >/dev/null
test ! -e "$home/opt/rish"

HOME="$home" TMPDIR="$home/.cache" CRAWLSPACE_SHIZUKU_SKIP_RUNTIME_PROBE=1     sh "$root/scripts/provision_shizuku_rish.sh" --apply --bundle "$bundle" >/dev/null

test -f "$home/opt/rish"
test -f "$home/opt/rish_shizuku.dex"
test -x "$home/opt/bin/rish"
grep -F 'RISH_APPLICATION_ID="com.termux"' "$home/opt/rish" >/dev/null
test "$(stat -c '%a' "$home/opt/rish_shizuku.dex")" = 400
grep -F '# crawlspace controlled shizuku rish' "$home/opt/bin/rish" >/dev/null
grep -F "$(printf 'shizuku_commit\tb844bc491f1790c72328e1a8e5b2349f8978f0ea')"     "$home/.local/state/crawlspace/shizuku/installed.tsv" >/dev/null

before=$(sha256sum "$home/opt/rish" "$home/opt/rish_shizuku.dex")
HOME="$home" TMPDIR="$home/.cache" CRAWLSPACE_SHIZUKU_SKIP_RUNTIME_PROBE=1     sh "$root/scripts/provision_shizuku_rish.sh" --apply --bundle "$bundle" >/dev/null
after=$(sha256sum "$home/opt/rish" "$home/opt/rish_shizuku.dex")
test "$before" = "$after"

cp "$bundle/manifest.tsv" "$bundle/manifest.bad"
printf '%s\n' x >> "$bundle/rish_shizuku.dex"
if HOME="$home" TMPDIR="$home/.cache" CRAWLSPACE_SHIZUKU_SKIP_RUNTIME_PROBE=1     sh "$root/scripts/provision_shizuku_rish.sh" --apply --bundle "$bundle" >/dev/null 2>&1; then
    printf '%s\n' 'corrupt controlled bundle unexpectedly passed' >&2
    exit 1
fi

printf '%s\n' 'crawlspace controlled Shizuku provisioning passes'
