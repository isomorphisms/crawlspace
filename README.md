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

GitHub Actions also builds `armeabi-v7a` and `arm64-v8a` binaries.

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

## Use

```sh
crawlspace run /system/bin/id
crawlspace run /system/bin/getprop ro.build.version.release
crawlspace run /data/local/tmp/tmovvm voicemail list
```

Commands must currently use an absolute executable path.

See [`docs/design.md`](docs/design.md) for the boundary and intentional limitations of this first cut.
