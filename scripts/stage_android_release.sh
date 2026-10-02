#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
ndk=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}

[ -n "$ndk" ] || {
    printf '%s\n' 'ANDROID_NDK_HOME is not set' >&2
    exit 2
}

prebuilt=$ndk/toolchains/llvm/prebuilt
toolchain=
for candidate in "$prebuilt"/*; do
    if [ -x "$candidate/bin/llvm-strip" ] &&
       [ -x "$candidate/bin/llvm-readelf" ]; then
        toolchain=$candidate
        break
    fi
done
[ -n "$toolchain" ] || {
    printf 'cannot find llvm-strip/readelf under %s\n' "$prebuilt" >&2
    exit 2
}

strip=$toolchain/bin/llvm-strip
readelf=$toolchain/bin/llvm-readelf
source_commit=$(git -C "$repo_root" rev-parse HEAD)
out=$repo_root/dist
mkdir -p "$out"

receipt=$out/BUILD-RECEIPT.tsv
printf 'schema\tsource_commit\tabi\tndk\tstrip_tool\tpre_strip_bytes\tpost_strip_bytes\tpackage_bytes\tsha256\n' > "$receipt"

stage_one() {
    abi=$1
    asset=$2
    source=$repo_root/build/$abi/crawlspace
    destination=$out/$asset

    [ -x "$source" ] || {
        printf 'missing unstripped Android build: %s\n' "$source" >&2
        exit 3
    }

    pre=$(wc -c < "$source" | tr -d ' ')
    cp "$source" "$destination"
    "$strip" --strip-all "$destination"
    chmod 0755 "$destination"
    post=$(wc -c < "$destination" | tr -d ' ')

    [ "$post" -lt "$pre" ] || {
        printf 'strip did not reduce %s: before=%s after=%s\n' "$abi" "$pre" "$post" >&2
        exit 3
    }

    if "$readelf" -S "$destination" |
       grep -E '[.]symtab|[.]strtab|[.]debug_' >/dev/null 2>&1; then
        printf 'stripped release still contains debug/static symbol sections: %s\n' "$destination" >&2
        exit 3
    fi

    sha=$(sha256sum "$destination" | awk '{print $1}')
    printf 'crawlspace-android-release-v1\t%s\t%s\t%s\tllvm-strip\t%s\t%s\t%s\t%s\n' \
        "$source_commit" "$abi" "27.2.12479018" "$pre" "$post" "$post" "$sha" >> "$receipt"

    printf '%s\tpre=%s\tpost=%s\tsha256=%s\n' "$abi" "$pre" "$post" "$sha"
}

stage_one armeabi-v7a crawlspace-armeabi-v7a
stage_one arm64-v8a crawlspace-arm64-v8a

(
    cd "$out"
    sha256sum crawlspace-armeabi-v7a crawlspace-arm64-v8a > SHA256SUMS
)
