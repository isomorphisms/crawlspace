# Shizuku logic in D

This branch translates the Shizuku behavior needed by Crawl Space into ordinary
D source.

Pinned upstream sources:

- `RikkaApps/Shizuku@b844bc491f1790c72328e1a8e5b2349f8978f0ea`
- `RikkaApps/Shizuku-API@a27f6e4151ba7b39965ca47edb2bf0aeed7102e5`

The Idriç files on the parent `shizuku` branch remain useful as a semantic map.
The files under `src/crawlspace/shizuku/` are the executable-language
translation.

## Current D inventory

### Core Binder/client policy

- `types.d` — Android UID/PID, caller identity, Binder/Parcel handles and
  shared transaction types.
- `clients.d` — attach, package/UID proof, initial permission state,
  exact-record Binder-death cleanup, and caller authorization.
- `service.d` — `transactRemote`, including API-13 flag placement, opaque
  payload copying and cleanup-safe identity restoration.
- `transaction_router.d` — private transaction 10001, remote transact,
  legacy attach code 14, rish codes 30000–30002, and the legacy version-12
  compatibility reply.

The D registry uses generation tokens for client and service identities so a
late death callback cannot delete a newer registration that reused the same
UID/PID or logical key.

### Binder delivery and activation

- `delivery.d` — temporary idle exemption, `<package>.shizuku` provider
  acquisition, liveness check, one force-stop/retry, Binder delivery, and
  unconditional provider release.
- `binder_sender.d` — process/UID observer deduplication and the exact
  manager-permission-before-client-permission package ordering.
- `applications.d` — manager application filtering and initial client Binder
  delivery target selection.

### Permission and configuration policy

- `permission.d` — allowed/denied bitmask semantics, live-client propagation,
  runtime permission grant/revoke behavior, and `getFlagsForUid` fallback.
- `permission_request.d` — `checkSelfPermission`, request/rationale state,
  immediate grant/deny behavior, and work-profile manager routing.
- `config_reconcile.d` — persisted UID/package validation, package-list
  deduplication, runtime-permission import, and Android-version-specific
  delayed-write scheduling.

The translation preserves two non-obvious upstream behaviors:

1. unchanged config flags return before adding new package names;
2. a persisted entry with an empty package list is removed during startup
   reconciliation even when the UID still exists.

### User services

- `user_service.d` — record creation/reuse/replacement, `noCreate`
  compatibility, daemon behavior, token attachment, death handling and
  connection cleanup.
- `user_service_apk.d` — package-upgrade observer retargeting and record
  removal when no installation remains.
- `user_service_entry.d` — ServiceStarter argument parsing, Android-user
  selection, process naming, and Context-constructor-before-no-arg constructor
  policy.
- `startup.d` — structured server and user-service `app_process` launch
  construction plus root/shell starter policy.

### Server lifecycle

- `server_lifecycle.d` — required system-service wait order, manager presence,
  manager APK removal exit behavior, BinderSender registration and initial
  client-before-manager Binder fan-out.
- `startup.d` — accepted launch UIDs, root cgroup/mount-namespace preparation,
  SELinux Binder call/transfer preflight, old-server replacement, APK selection
  and detached launch.

### rish

- `rish.d` — server-side host registry keyed by calling PID, TTY handling,
  window-size/exit-code transactions and environment-preservation rules.
- `rish_client.d` — server-version gate, permission flow, shared-UID terminal
  package selection and Android 8 binder-request fallback.

The shell-user environment rule is preserved exactly: root preserves the caller
environment by default, shell strips it by default, and the first
`RISH_PRESERVE_ENV=1` or `=0` entry overrides that default.

### Deprecated remote-process API

- `remote_process.d` — child creation, owner Binder-death destruction, cached
  stdin/stdout pipe bridges, uncached stderr bridge and timeout polling.

This path is included for fidelity even though upstream Shizuku documents
`newProcess` as planned for removal in favor of UserService.

## Deliberate semantic correction

The pinned Java `Service.transactRemote` restores Binder calling identity after
the target transaction but not from its `finally` block. A target exception can
therefore skip restoration.

The D translation treats identity restoration as a capability invariant and
uses cleanup semantics so restoration occurs on both success and failure.

## Android boundary

`android_boundary.d` makes the remaining platform boundary explicit.

Stable `libbinder_ndk` is useful for caller UID/PID, Binder liveness/death and
many Parcel primitives. It is not a drop-in implementation of Shizuku's
transparent forwarding path:

- `AIBinder_transact` requires an input Parcel created by
  `AIBinder_prepareTransaction`;
- `AIBinder_prepareTransaction` requires the target Binder to be associated
  with an NDK Binder class;
- Shizuku accepts an arbitrary target Binder and forwards the remaining opaque
  Parcel bytes;
- stable NDK exposes no equivalent of Java Binder
  `clearCallingIdentity()` / `restoreCallingIdentity()`.

Accordingly the D adapter refuses to construct a forwarding path unless a
`TransparentBinderBridge` and `BinderIdentityBridge` are explicitly supplied.
Those should be implemented by a narrow Java/framework JNI bridge or an
equivalent platform-libbinder bridge. A partial NDK adapter must not silently
change authority semantics.

Generic Android declarations remain in
`dilapidated-shed/ick:dmd-shizuku-android-touchpoints`. That branch now also
declares public Parcel position/size operations needed around the transparent
bridge.

## Acceptance status

`.github/workflows/shizuku-d.yml` compiles the complete translated policy set
with DMD and runs `tests/shizuku_d_logic.d` on the host.

Host acceptance proves the Shizuku state machines and compatibility rules; it
does **not** yet prove an Android-native runnable Shizuku replacement.

The remaining work is primarily:

1. implement the transparent Binder/identity Android bridge;
2. bind ContentProvider, PackageManager/PermissionManager, observer, Bundle /
   Intent and process operations to the D seams;
3. qualify the required external calls/relocations in Ick's Android DMD path;
4. run device acceptance on the MIRO A1, beginning with one harmless forwarded
   system-service transaction and Binder-death cleanup.

Compiler/ABI qualification belongs in Ick; Shizuku-specific policy remains in
Crawl Space.
