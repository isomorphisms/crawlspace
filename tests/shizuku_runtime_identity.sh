#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

home=$tmp/home
mkdir -p "$home"

manifest=$tmp/manifest.tsv
cat > "$manifest" <<'EOF'
schema	crawlspace-shizuku-rish-v1
crawlspace_commit	bundle-commit
shizuku_commit	upstream-shizuku-commit
rish_sha256	rish-hash
dex_sha256	dex-hash
EOF

receipt=$tmp/installed.tsv
cat > "$receipt" <<'EOF'
schema	crawlspace-shizuku-install-v1
shizuku_commit	upstream-shizuku-commit
bundle	/tmp/bundle
application_id	com.termux
rish_sha256	installed-rish-hash
dex_sha256	installed-dex-hash
EOF

fake=$tmp/rish
cat > "$fake" <<'EOF'
#!/bin/sh
[ "${1:-}" = -c ] || exit 2
cat <<'OUT'
runtime_uid	2000
runtime_selinux	u:r:shell:s0
manager_apk	/data/app/shizuku/base.apk
manager_version_name	13.6.0.test
manager_version_code	12345
server_pid	4321
server_start_ticks	987654
server_uid	2000
server_selinux	u:r:shell:s0
OUT
EOF
chmod 0755 "$fake"

out=$(HOME="$home"     CRAWLSPACE_SHIZUKU_RISH_PATH="$fake"     CRAWLSPACE_SHIZUKU_MANIFEST="$manifest"     CRAWLSPACE_SHIZUKU_RECEIPT="$receipt"     sh "$root/scripts/shizuku_runtime_identity.sh")

printf '%s\n' "$out" | grep -Fx 'schema=crawlspace-shizuku-runtime-v1' >/dev/null
printf '%s\n' "$out" | grep -Fx 'bundle_crawlspace_commit=bundle-commit' >/dev/null
printf '%s\n' "$out" | grep -Fx 'bundle_shizuku_commit=upstream-shizuku-commit' >/dev/null
printf '%s\n' "$out" | grep -Fx 'provision_schema=crawlspace-shizuku-install-v1' >/dev/null
printf '%s\n' "$out" | grep -Fx 'runtime_status=ready' >/dev/null
printf '%s\n' "$out" | grep -Fx 'runtime_uid=2000' >/dev/null
printf '%s\n' "$out" | grep -Fx 'manager_version_name=13.6.0.test' >/dev/null
printf '%s\n' "$out" | grep -Fx 'server_pid=4321' >/dev/null
printf '%s\n' "$out" | grep -Fx 'server_start_ticks=987654' >/dev/null
printf '%s\n' "$out" | grep -Fx 'server_source_relation=unverified' >/dev/null
printf '%s\n' "$out" | grep -Fx 'removable_storage=not_consulted' >/dev/null

bad=$tmp/bad-rish
cat > "$bad" <<'EOF'
#!/bin/sh
printf '%s\n' 'server not running' >&2
exit 1
EOF
chmod 0755 "$bad"

unavailable=$(HOME="$home"     CRAWLSPACE_SHIZUKU_RISH_PATH="$bad"     CRAWLSPACE_SHIZUKU_MANIFEST="$manifest"     CRAWLSPACE_SHIZUKU_RECEIPT="$receipt"     sh "$root/scripts/shizuku_runtime_identity.sh")
printf '%s\n' "$unavailable" | grep -Fx 'runtime_status=unavailable' >/dev/null
printf '%s\n' "$unavailable" | grep -Fx 'runtime_exit_status=1' >/dev/null
printf '%s\n' "$unavailable" | grep -Fx 'server_source_relation=unverified' >/dev/null

printf '%s\n' 'crawlspace Shizuku runtime identity report passes'
