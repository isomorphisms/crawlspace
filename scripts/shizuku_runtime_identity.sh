#!/bin/sh
set -eu

fail() {
    printf 'crawlspace shizuku identity: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
usage: shizuku_runtime_identity.sh

Report three identities separately:
  - the controlled rish bundle/provisioning source;
  - the installed Shizuku manager package;
  - the currently observed Shizuku shell/server process state.

The report is read-only. A running server PID is an observation, not a durable
identity, and the report does not claim the running server came from the
controlled rish bundle.
EOF
}

case ${1:-} in
    '') ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

: "${HOME:?HOME is required}"

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

manager_package=moe.shizuku.privileged.api
rish=${CRAWLSPACE_SHIZUKU_RISH_PATH:-"$HOME/opt/bin/rish"}
manifest=${CRAWLSPACE_SHIZUKU_MANIFEST:-}
receipt=${CRAWLSPACE_SHIZUKU_RECEIPT:-}

if [ -z "$manifest" ] && [ -f "$repo_root/runtime/shizuku-rish/manifest.tsv" ]; then
    manifest=$repo_root/runtime/shizuku-rish/manifest.tsv
fi

if [ -z "$receipt" ]; then
    for candidate in         "${XDG_STATE_HOME:-$HOME/.local/state}/crawlspace/shizuku/installed.tsv"         "${XDG_STATE_HOME:-$HOME/.local/state}/catfood/shizuku/installed.tsv"
    do
        if [ -f "$candidate" ]; then
            receipt=$candidate
            break
        fi
    done
fi

tsv_value() {
    file=$1
    key=$2
    [ -f "$file" ] || return 1
    awk -F '\t' -v key="$key" '
        $1 == key {
            if (seen++) exit 2
            value=$2
        }
        END {
            if (!seen) exit 1
            print value
        }
    ' "$file"
}

print_or_unknown() {
    key=$1
    value=$2
    if [ -n "$value" ]; then
        printf '%s=%s\n' "$key" "$value"
    else
        printf '%s=unknown\n' "$key"
    fi
}

printf '%s\n' 'schema=crawlspace-shizuku-runtime-v1'
printf '%s\n' 'report_scope=controlled-bundle+installed-manager+live-runtime'
printf '%s\n' 'removable_storage=not_consulted'

if [ -n "$manifest" ] && [ -f "$manifest" ]; then
    print_or_unknown bundle_manifest "$manifest"
    print_or_unknown bundle_crawlspace_commit "$(tsv_value "$manifest" crawlspace_commit 2>/dev/null || true)"
    print_or_unknown bundle_shizuku_commit "$(tsv_value "$manifest" shizuku_commit 2>/dev/null || true)"
    print_or_unknown bundle_rish_sha256 "$(tsv_value "$manifest" rish_sha256 2>/dev/null || true)"
    print_or_unknown bundle_dex_sha256 "$(tsv_value "$manifest" dex_sha256 2>/dev/null || true)"
else
    printf '%s\n' 'bundle_manifest=unavailable'
    printf '%s\n' 'bundle_crawlspace_commit=unknown'
    printf '%s\n' 'bundle_shizuku_commit=unknown'
    printf '%s\n' 'bundle_rish_sha256=unknown'
    printf '%s\n' 'bundle_dex_sha256=unknown'
fi

if [ -n "$receipt" ] && [ -f "$receipt" ]; then
    print_or_unknown provision_receipt "$receipt"
    print_or_unknown provision_schema "$(tsv_value "$receipt" schema 2>/dev/null || true)"
    print_or_unknown provision_source "$(tsv_value "$receipt" source 2>/dev/null || tsv_value "$receipt" bundle 2>/dev/null || true)"
    print_or_unknown provision_source_kind "$(tsv_value "$receipt" source_kind 2>/dev/null || true)"
    print_or_unknown provision_application_id "$(tsv_value "$receipt" application_id 2>/dev/null || true)"
    print_or_unknown provision_rish_sha256 "$(tsv_value "$receipt" rish_sha256 2>/dev/null || true)"
    print_or_unknown provision_dex_sha256 "$(tsv_value "$receipt" dex_sha256 2>/dev/null || true)"
else
    printf '%s\n' 'provision_receipt=unavailable'
    printf '%s\n' 'provision_schema=unknown'
    printf '%s\n' 'provision_source=unknown'
    printf '%s\n' 'provision_source_kind=unknown'
    printf '%s\n' 'provision_application_id=unknown'
    printf '%s\n' 'provision_rish_sha256=unknown'
    printf '%s\n' 'provision_dex_sha256=unknown'
fi

if [ ! -x "$rish" ]; then
    printf '%s\n' 'runtime_status=unavailable'
    printf '%s\n' 'runtime_reason=rish-missing'
    printf '%s\n' 'server_source_relation=unverified'
    exit 0
fi

snapshot='
toy=/system/bin/toybox
pkg=moe.shizuku.privileged.api

printf "runtime_uid\t"
/system/bin/id -u 2>/dev/null || printf "unknown"
printf "\n"

printf "runtime_selinux\t"
/system/bin/id -Z 2>/dev/null || printf "unknown"
printf "\n"

printf "manager_apk\t"
/system/bin/pm path "$pkg" 2>/dev/null | "$toy" sed -n "1s/^package://p"
printf "\n"

package_dump=$(/system/bin/dumpsys package "$pkg" 2>/dev/null || true)
printf "manager_version_name\t"
printf "%s\n" "$package_dump" | "$toy" grep -m 1 "versionName=" | "$toy" sed "s/.*versionName=//" || true
printf "\n"

printf "manager_version_code\t"
printf "%s\n" "$package_dump" | "$toy" grep -m 1 "versionCode=" | "$toy" sed "s/.*versionCode=//; s/ .*//" || true
printf "\n"

server_pid=$(/system/bin/pidof shizuku_server 2>/dev/null | "$toy" awk "{print \$1}")
printf "server_pid\t%s\n" "${server_pid:-unknown}"

if [ -n "$server_pid" ] && [ -r "/proc/$server_pid/stat" ]; then
    printf "server_start_ticks\t"
    "$toy" awk "{print \$22}" "/proc/$server_pid/stat" 2>/dev/null || printf "unknown"
    printf "\n"

    printf "server_uid\t"
    "$toy" awk "/^Uid:/ {print \$2}" "/proc/$server_pid/status" 2>/dev/null || printf "unknown"
    printf "\n"

    printf "server_selinux\t"
    /system/bin/cat "/proc/$server_pid/attr/current" 2>/dev/null || printf "unknown"
    printf "\n"
else
    printf "server_start_ticks\tunknown\n"
    printf "server_uid\tunknown\n"
    printf "server_selinux\tunknown\n"
fi
'

timeout_seconds=${CRAWLSPACE_SHIZUKU_IDENTITY_TIMEOUT_SECONDS:-8}
case $timeout_seconds in
    ''|*[!0-9]*) fail "invalid timeout seconds: $timeout_seconds" ;;
esac
[ "$timeout_seconds" -ge 1 ] && [ "$timeout_seconds" -le 60 ] ||     fail "timeout seconds must be 1 through 60"

runtime_output=
runtime_status=0
if command -v timeout >/dev/null 2>&1; then
    runtime_output=$(timeout "$timeout_seconds" "$rish" -c "$snapshot" 2>&1) || runtime_status=$?
    printf '%s\n' 'runtime_probe_bound=timeout-command'
else
    runtime_output=$("$rish" -c "$snapshot" 2>&1) || runtime_status=$?
    printf '%s\n' 'runtime_probe_bound=unavailable'
fi

if [ "$runtime_status" -ne 0 ]; then
    printf '%s\n' 'runtime_status=unavailable'
    printf 'runtime_exit_status=%s\n' "$runtime_status"
    first=$(printf '%s\n' "$runtime_output" | sed -n '1p')
    print_or_unknown runtime_reason "$first"
    printf '%s\n' 'server_source_relation=unverified'
    exit 0
fi

printf '%s\n' 'runtime_status=ready'
printf '%s\n' "$runtime_output" | while IFS='	' read -r key value; do
    case $key in
        runtime_uid|runtime_selinux|manager_apk|manager_version_name|manager_version_code|server_pid|server_start_ticks|server_uid|server_selinux)
            print_or_unknown "$key" "$value"
            ;;
    esac
done

printf 'manager_package=%s\n' "$manager_package"
printf '%s\n' 'server_source_relation=unverified'
printf '%s\n' 'server_identity_note=pid+start_ticks_are_observations_not_durable_identity'
