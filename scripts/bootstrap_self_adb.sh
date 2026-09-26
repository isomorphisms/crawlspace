#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

port=${CRAWLSPACE_PORT:-49317}
remote=/data/local/tmp/crawlspace

abi=$(getprop ro.product.cpu.abi)
case "$abi" in
    armeabi-v7a|armeabi)
        abi=armeabi-v7a
        ;;
    arm64-v8a)
        abi=arm64-v8a
        ;;
    *)
        printf 'crawlspace: unsupported local ABI: %s\n' "$abi" >&2
        exit 2
        ;;
esac

binary=${CRAWLSPACE_BINARY:-$repo_root/build/$abi/crawlspace}
if [ ! -x "$binary" ]; then
    printf 'crawlspace: missing binary: %s\n' "$binary" >&2
    exit 2
fi

config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/crawlspace
token_file=$config_dir/token

mkdir -p "$config_dir"
chmod 700 "$config_dir"

if [ ! -s "$token_file" ]; then
    umask 077
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$token_file"
    printf '\n' >> "$token_file"
fi
chmod 600 "$token_file"

adb get-state >/dev/null

adb shell "mkdir -p '$remote' && chmod 700 '$remote'"
adb push "$binary" "$remote/crawlspace" >/dev/null
adb push "$token_file" "$remote/token" >/dev/null

adb shell "chmod 500 '$remote/crawlspace'; chmod 400 '$remote/token'"

old_pid=$(adb shell "cat '$remote/pid' 2>/dev/null || true" | tr -d '\r\n')
case "$old_pid" in
    ''|*[!0-9]*)
        ;;
    *)
        adb shell "kill '$old_pid' 2>/dev/null || true"
        ;;
esac

adb shell "cd '$remote'; ./crawlspace serve ./token '$port' >server.log 2>&1 </dev/null & echo \$! >pid"

install_dir=${PREFIX:-$HOME/.local}/bin
mkdir -p "$install_dir"
cp "$binary" "$install_dir/crawlspace"
chmod 700 "$install_dir/crawlspace"

i=0
while [ "$i" -lt 5 ]; do
    if CRAWLSPACE_PORT="$port" "$install_dir/crawlspace" run /system/bin/id; then
        printf 'crawlspace: ready on 127.0.0.1:%s\n' "$port"
        exit 0
    fi
    i=$((i + 1))
    sleep 1
done

printf '%s\n' 'crawlspace: daemon did not answer; remote log follows' >&2
adb shell "cat '$remote/server.log' 2>/dev/null || true" >&2
exit 1
