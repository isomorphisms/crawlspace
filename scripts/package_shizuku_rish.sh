#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
source_dir=$repo_root/shizuku
output_dir=${1:-$repo_root/out/shizuku-rish}

fail() {
    printf 'crawlspace shizuku bundle: %s\n' "$*" >&2
    exit 1
}

[ -d "$source_dir/.git" ] || [ -f "$source_dir/.git" ] ||     fail 'Shizuku submodule is not initialized; checkout with submodules'

expected=$(git -C "$repo_root" ls-tree HEAD shizuku | awk '{print $3}')
actual=$(git -C "$source_dir" rev-parse HEAD)
[ -n "$expected" ] || fail 'cannot read pinned Shizuku gitlink'
[ "$actual" = "$expected" ] ||     fail "Shizuku submodule drift: expected $expected, found $actual"

gradlew=$source_dir/gradlew
[ -x "$gradlew" ] || fail "missing executable Gradle wrapper: $gradlew"

(
    cd "$source_dir"
    ./gradlew --no-daemon :shell:assembleRelease
)

rish=$source_dir/manager/src/main/assets/rish
dex=$source_dir/manager/src/main/assets/rish_shizuku.dex
[ -s "$rish" ] || fail "missing built launcher: $rish"
[ -s "$dex" ] || fail "missing built DEX: $dex"

rm -rf "$output_dir"
mkdir -p "$output_dir"
cp "$rish" "$output_dir/rish"
cp "$dex" "$output_dir/rish_shizuku.dex"
chmod 0500 "$output_dir/rish"
chmod 0400 "$output_dir/rish_shizuku.dex"

rish_sha=$(sha256sum "$output_dir/rish" | awk '{print $1}')
dex_sha=$(sha256sum "$output_dir/rish_shizuku.dex" | awk '{print $1}')
crawlspace_commit=$(git -C "$repo_root" log -1 --format=%H -- shizuku .gitmodules scripts/package_shizuku_rish.sh)

{
    printf 'schema\tcrawlspace-shizuku-rish-v1\n'
    printf 'crawlspace_commit\t%s\n' "$crawlspace_commit"
    printf 'shizuku_commit\t%s\n' "$actual"
    printf 'rish_sha256\t%s\n' "$rish_sha"
    printf 'dex_sha256\t%s\n' "$dex_sha"
} > "$output_dir/manifest.tsv"

printf 'crawlspace shizuku bundle\t%s\n' "$output_dir"
printf 'shizuku_commit\t%s\n' "$actual"
printf 'rish_sha256\t%s\n' "$rish_sha"
printf 'dex_sha256\t%s\n' "$dex_sha"
