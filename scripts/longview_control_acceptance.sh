#!/bin/sh
set -eu

fail() {
    printf 'crawlspace longview acceptance: FAIL: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
usage: longview_control_acceptance.sh [--kill-listener]

Default mode is non-disruptive:
  - verify the native control-plane identity;
  - start one bounded shell worker;
  - prove discover remains responsive while that worker runs.

--kill-listener adds the disruptive lifetime test:
  - start another bounded worker;
  - kill the listener PID reported by crawlspace identify;
  - prove the listening endpoint disappears;
  - prove the already accepted worker still completes.

The disruptive mode leaves the Crawl Space listener stopped. Re-run the normal
bootstrap/start path afterwards.
EOF
}

kill_listener=0
while [ "$#" -gt 0 ]; do
    case $1 in
        --kill-listener) kill_listener=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

crawlspace=${CRAWLSPACE_COMMAND:-crawlspace}
if ! command -v "$crawlspace" >/dev/null 2>&1 && [ ! -x "$crawlspace" ]; then
    fail "crawlspace command not found: $crawlspace"
fi

field() {
    key=$1
    text=$2
    printf '%s\n' "$text" | awk -F '=' -v key="$key" '
        $1 == key {
            if (seen++) exit 2
            value=substr($0, length(key) + 2)
        }
        END {
            if (!seen) exit 1
            print value
        }
    '
}

identity=$("$crawlspace" identify)
status=$(field status "$identity") || fail 'identity response lacks status'
[ "$status" = ready ] || fail "identity status is $status"

start_identity=$(field daemon_start_identity "$identity") ||     fail 'identity response lacks daemon_start_identity'
daemon_pid=$(field daemon_pid "$identity") || fail 'identity response lacks daemon_pid'
daemon_uid=$(field daemon_uid "$identity") || fail 'identity response lacks daemon_uid'
daemon_role=$(field daemon_role "$identity") || fail 'identity response lacks daemon_role'
build_id=$(field build_id "$identity") || fail 'identity response lacks build_id'

case $daemon_pid in
    ''|*[!0-9]*) fail "invalid daemon PID: $daemon_pid" ;;
esac
[ "$daemon_pid" -gt 1 ] || fail "refusing unsafe daemon PID: $daemon_pid"
case $daemon_uid in 0|2000) ;; *) fail "unexpected daemon UID: $daemon_uid" ;; esac
[ "$daemon_role" = native-command-bridge ] ||     fail "unexpected daemon role: $daemon_role"

tmp=${TMPDIR:-"$HOME/.cache"}
mkdir -p "$tmp"
first=$tmp/crawlspace-longview-first.$$.out
second=$tmp/crawlspace-longview-second.$$.out
absence=$tmp/crawlspace-longview-absence.$$.out
trap 'rm -f "$first" "$second" "$absence"' EXIT HUP INT TERM

printf '%s\n' 'phase=concurrent-control'
"$crawlspace" run /system/bin/sh -c     'sleep 3; printf "longview-worker-finished\n"' >"$first" 2>&1 &
first_client=$!

sleep 1
during=$("$crawlspace" discover "$start_identity") || {
    kill "$first_client" 2>/dev/null || true
    wait "$first_client" 2>/dev/null || true
    fail 'discover did not respond while worker was active'
}
[ "$(field status "$during")" = ready ] ||     fail 'daemon identity changed during bounded worker'

wait "$first_client" || fail 'bounded worker client failed'
grep -Fqx 'longview-worker-finished' "$first" ||     fail 'bounded worker result is missing'
printf '%s\n' 'concurrent_control=PASS'

if [ "$kill_listener" -eq 1 ]; then
    printf '%s\n' 'phase=listener-death'
    "$crawlspace" run /system/bin/sh -c         'sleep 3; printf "longview-worker-survived-listener\n"' >"$second" 2>&1 &
    second_client=$!

    sleep 1
    "$crawlspace" run /system/bin/toybox kill "$daemon_pid" >/dev/null || {
        kill "$second_client" 2>/dev/null || true
        wait "$second_client" 2>/dev/null || true
        fail 'could not kill reported listener PID'
    }

    set +e
    "$crawlspace" discover >"$absence" 2>&1
    absent_status=$?
    set -e
    [ "$absent_status" -eq 69 ] || {
        cat "$absence" >&2
        fail "listener did not become unavailable; discover exit=$absent_status"
    }
    grep -Fqx 'reason=daemon-absent' "$absence" || {
        cat "$absence" >&2
        fail 'listener disappearance was not reported as daemon-absent'
    }

    wait "$second_client" || fail 'accepted worker failed after listener death'
    grep -Fqx 'longview-worker-survived-listener' "$second" ||         fail 'accepted worker result missing after listener death'
    printf '%s\n' 'listener_disappearance=PASS'
    printf '%s\n' 'accepted_worker_after_listener_death=PASS'
    printf '%s\n' 'listener_restart_required=yes'
fi

printf 'daemon_start_identity=%s\n' "$start_identity"
printf 'daemon_pid=%s\n' "$daemon_pid"
printf 'daemon_uid=%s\n' "$daemon_uid"
printf 'daemon_role=%s\n' "$daemon_role"
printf 'build_id=%s\n' "$build_id"
printf '%s\n' 'physical_device_evidence=local-run-required'
