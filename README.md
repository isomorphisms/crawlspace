# Crawl Space

Get underneath Android without making every program privileged.

Crawl Space is the umbrella for experiments and permanent changes below Android application level: privileged access, boot integration, kernel/filesystem work, storage semantics, and related system primitives.

The first piece is intentionally smaller: a native bridge from ordinary Termux into Android's `shell` identity. ADB starts the daemon; after that, commands can originate from Termux through `crawlspace run`.

```text
Termux
   |
   | authenticated loopback request
   v
crawlspace daemon       uid=2000(shell)
   |
   +--> /system/bin/...
   +--> app_process-based tools
   +--> /data/local/tmp/tmovvm
```

The interface is meant to survive later changes underneath it. A rooted or boot-integrated version can start the same daemon with greater privilege instead of requiring ADB.

## Build

The implementation is one small C program. There is no Android app or Gradle project.

With an Android NDK installed:

```sh
export ANDROID_NDK_HOME=/path/to/android-ndk
sh scripts/build_android.sh armeabi-v7a
```

or build both ARM targets:

```sh
sh scripts/build_android.sh all
```

GitHub Actions also builds `armeabi-v7a` and `arm64-v8a` binaries. Release binaries are stripped with the exact NDK `llvm-strip`; the unstripped build outputs remain only as debugging artifacts. `dist/BUILD-RECEIPT.tsv` records exact source commit, ABI, NDK, pre-strip size, post-strip size, final package size, and SHA-256.

## First bootstrap

The initial bootstrap assumes `adb` in Termux is paired/connected to the same phone through Android Wireless debugging.

```sh
sh scripts/bootstrap_self_adb.sh
```

The script creates a random token in Termux private storage, pushes the daemon and token into `/data/local/tmp/crawlspace`, starts the daemon from ADB shell, installs the client in Termux, and runs the first acceptance check.

Successful acceptance includes:

```text
uid=2000(shell)
```

## Discover the current boundary

The discovery request is separate from command execution:

```sh
crawlspace discover
```

It returns a bounded, line-oriented record such as:

```text
status=ready
transport_version=2
discovery_version=1
daemon_identity=0123456789abcdef0123456789abcdef
daemon_uid=2000
authorization_scope=local-bearer-token
capability=crawlspace.discovery.v1
capability=crawlspace.run.absolute-path.v1
capability=crawlspace.runtime-identity.v1
```

For the identity of the process that owns the listening control plane:

```sh
crawlspace identify
```

A current response separates continuity, process identity, authority, role, and
the exact source build:

```text
status=ready
transport_version=2
identity_version=1
daemon_start_identity=0123456789abcdef0123456789abcdef
daemon_pid=1234
daemon_uid=2000
daemon_authority=shell
daemon_role=native-command-bridge
build_id=81587108d3eab33cec5f1470ac86d0c453f1ff1b
authorization_scope=local-bearer-token
```

The random start identity is a continuity marker. The build ID identifies the
compiled Crawl Space source. Neither field claims that an installed Shizuku
manager/server has the same identity.

Pass the last observed identity to detect a daemon replacement:

```sh
crawlspace discover 0123456789abcdef0123456789abcdef
```

The response says `status=restarted` and supplies the new identity when a
different daemon instance answers. The identity is a continuity marker, not a
cryptographic identity or proof of the daemon executable.

## Use

```sh
crawlspace run /system/bin/id
crawlspace run /system/bin/getprop ro.build.version.release
crawlspace run /data/local/tmp/tmovvm voicemail list
crawlspace run-bounded 5000 65536 65536 /system/bin/id
```

`run-bounded` adds a server-enforced execution timeout, separate stdout/stderr,
and retained-output limits while remaining synchronous. It is a mechanism for
future Longview workers, not itself a durable worker or retained-result API.

Commands must currently use an absolute executable path.

See [`docs/design.md`](docs/design.md) for the boundary and
[`docs/protocol.md`](docs/protocol.md) for the exact discovery, authentication,
timeout, and restart contracts.


## Longview control acceptance

After installing the exact Android binary on a phone, the non-disruptive
Longview control check is:

```sh
sh scripts/longview_control_acceptance.sh
```

It verifies the listener identity and `run-bounded` capability, exercises a
real server-enforced timeout and output truncation, proves stdout/stderr remain
separate, then proves `crawlspace discover` remains responsive while a bounded
command is still active.

The stronger lifetime test is intentionally explicit because it stops the
listener:

```sh
sh scripts/longview_control_acceptance.sh --kill-listener
```

That test proves the listener endpoint disappears while an already accepted
bounded command still reaches its result. It leaves Crawl Space stopped; use the
normal bootstrap/start path afterwards.

This is process/transport evidence only. It is not evidence that an IB task was
retained, that a committed result can be reopened, or that Shizuku survived a
restart.
