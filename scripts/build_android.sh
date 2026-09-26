#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

ndk=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}
if [ -z "$ndk" ]; then
    printf '%s\n' 'ANDROID_NDK_HOME is not set' >&2
    exit 2
fi

prebuilt=$ndk/toolchains/llvm/prebuilt
toolchain=
for candidate in "$prebuilt"/*; do
    if [ -d "$candidate/bin" ]; then
        toolchain=$candidate
        break
    fi
done

if [ -z "$toolchain" ]; then
    printf 'cannot find an NDK toolchain under %s\n' "$prebuilt" >&2
    exit 2
fi

build_one() {
    abi=$1

    case "$abi" in
        armeabi-v7a)
            cc=$toolchain/bin/armv7a-linux-androideabi21-clang
            ;;
        arm64-v8a)
            cc=$toolchain/bin/aarch64-linux-android21-clang
            ;;
        *)
            printf 'unknown ABI: %s\n' "$abi" >&2
            exit 2
            ;;
    esac

    out=$repo_root/build/$abi
    mkdir -p "$out"

    "$cc" \
        -std=c11 \
        -D_GNU_SOURCE \
        -Os \
        -fPIE -pie \
        -Wall -Wextra -Werror \
        "$repo_root/src/crawlspace.c" \
        -o "$out/crawlspace"

    printf '%s\n' "$out/crawlspace"
}

case "${1:-all}" in
    all)
        build_one armeabi-v7a
        build_one arm64-v8a
        ;;
    armeabi-v7a|arm64-v8a)
        build_one "$1"
        ;;
    *)
        printf 'usage: %s [all|armeabi-v7a|arm64-v8a]\n' "$0" >&2
        exit 2
        ;;
esac
