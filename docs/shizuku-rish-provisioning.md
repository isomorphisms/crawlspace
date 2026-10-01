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


## Runtime identity is separate from bundle provenance

A controlled `rish` pair is not proof that the installed manager or running
Shizuku server came from the same source. Longview needs those facts kept
separate.

Run:

```sh
sh scripts/shizuku_runtime_identity.sh
```

The report combines, without collapsing them:

- controlled bundle commit, pinned Shizuku source and bundle hashes when known;
- the actual provisioning receipt used on this phone;
- installed manager APK/version observations;
- one bounded live `rish` snapshot of shell UID/SELinux and the observed
  `shizuku_server` PID/start ticks/UID/SELinux when readable.

`server_source_relation=unverified` is intentional. PID plus process start ticks
are observations useful for detecting replacement; they are not a durable task
identity and are not evidence that the server binary matches the controlled
loader bundle.

The live information is gathered with one `rish -c` launch rather than one
privileged process launch per field. Removable storage is not consulted.
