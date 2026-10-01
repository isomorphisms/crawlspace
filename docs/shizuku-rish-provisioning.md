# Controlled Shizuku rish provisioning

Crawl Space owns the Shizuku source identity used here through the pinned
`shizuku` gitlink. The current pin is
`RikkaApps/Shizuku@b844bc491f1790c72328e1a8e5b2349f8978f0ea`.

This is different from copying whichever Shizuku happens to be installed on a
phone. The host-side bundle job builds `:shell:assembleRelease` from that exact
pinned source, then records hashes for `rish` and `rish_shizuku.dex`.

The device-side provisioner accepts only such a bundle. It does not scan
removable storage or silently substitute an arbitrary installed manager APK.

On a phone:

```sh
sh scripts/provision_shizuku_rish.sh --apply --bundle /path/to/shizuku-rish
```

It installs the pair under `~/opt`, rewrites the upstream terminal placeholder
to `com.termux`, keeps the DEX read-only for Android 14+, exposes
`~/opt/bin/rish`, and probes for shell UID 2000.

Pairing/starting Shizuku is still an Android bootstrap action. A stopped service
is reported as a runtime-pending state; it is not misdiagnosed as an SD-card or
file-layout problem.
