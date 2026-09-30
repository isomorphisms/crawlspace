# Shizuku → Idriç translation map

This branch keeps the pinned upstream Shizuku source as a submodule and translates
the mechanism needed by Crawl Space into Idriç-facing semantic boundaries.

Pinned sources:

- `RikkaApps/Shizuku@b844bc491f1790c72328e1a8e5b2349f8978f0ea`
- its `Shizuku-API` submodule at
  `RikkaApps/Shizuku-API@a27f6e4151ba7b39965ca47edb2bf0aeed7102e5`

The translation is intentionally not the manager UI. The useful core is a
privileged Binder broker plus client registration, Binder delivery, and optional
user-service processes.

## Current Idriç sketch

### `src/shizuku_broker.idric`

Top-level vocabulary and the main capability boundary:

- shell/root broker identity;
- Binder-authenticated callers;
- package ownership proof;
- attached/allowed clients;
- forwarded Binder transactions;
- user-service handles;
- broker death and reacquisition.

### `src/shizuku_protocol.idric`

The actual remote-Binder forwarding protocol:

- API < 13 flags come from the outer transaction;
- API >= 13 flags are carried in the forwarded payload;
- target Binder + transaction code + payload become a typed
  `RemoteTransaction`;
- caller UID/PID are obtained independently from Binder;
- target transactions run inside a scoped cleared-calling-identity capability;
- identity restoration is required on both success and failure;
- Binder liveness and death subscriptions are explicit.

This corresponds primarily to:

- `ShizukuBinderWrapper.transact`;
- `Service.transactRemote`;
- `Service.onTransact`.

### `src/shizuku_clients.idric`

Client attachment and authorization:

- the package named by the client is untrusted until it is proved to belong to
  Binder's calling UID;
- records are keyed by Binder UID/PID;
- callback Binder death removes the client record;
- permission state is separate from attachment;
- authorization retains why the caller was accepted instead of reducing the
  decision immediately to a Boolean.

This corresponds primarily to:

- `ShizukuService.attachApplication`;
- `ClientManager`;
- `ClientRecord`;
- `Service.enforceCallingPermission`.

### `src/shizuku_delivery.idric`

How an ordinary application receives the privileged broker Binder:

- package + `.shizuku` ContentProvider;
- temporary idle exemption;
- external provider acquisition;
- Binder liveness check;
- BinderContainer provider call;
- provider release;
- one force-stop/retry on a dead provider;
- process/UID observations as delivery triggers.

The null external-provider token is preserved as a semantic requirement of this
path, not an accidental constant: Shizuku documents that crossing Binder
produces a BinderProxy unsuitable for the map-key behavior used when the
provider is later removed.

This corresponds primarily to:

- `ShizukuService.sendBinderToUserApp`;
- `BinderSender`.

### `src/shizuku_user_service.idric`

Privileged user-service lifecycle:

- package ownership checked against caller app-id and Android user;
- service identity is package + tag-or-class;
- version mismatch or dead Binder replaces the old record;
- `noCreate` is represented as `ExistingOnly`;
- semantic bind results are separated from the API-version-specific integer
  reply encoding;
- service startup is a structured `app_process` command;
- service attachment is authorized by the generated service token.

This corresponds primarily to:

- `UserServiceManager`;
- `ShizukuUserServiceManager`;
- `ServiceStarter`.

### `src/shizuku_startup.idric`

Native server startup:

- reject launch identities other than root or Android shell;
- root cgroup preparation;
- root mount-namespace switch on newer Android;
- SELinux Binder call/transfer preflight;
- old-server replacement;
- manager APK discovery;
- detached `app_process` launch.

This corresponds to `manager/src/main/jni/starter.cpp`.

## What still needs implementation

The type/intent structure is now broad enough to describe the useful Shizuku
mechanism. The next work is lowering, not more manager-application translation.

### 1. Android Binder primitives

Idriç needs maintained Android/DEX bindings for:

- `Binder.getCallingUid`;
- `Binder.getCallingPid`;
- `Binder.clearCallingIdentity`;
- `Binder.restoreCallingIdentity`;
- `IBinder.transact`;
- `IBinder.pingBinder`;
- `IBinder.linkToDeath` / `unlinkToDeath`;
- `Parcel.obtain`, append/copy, position/available bytes, and recycle.

The scoped `with broker identity` operation should be lowered as cleanup-safe
code. Do not copy the Java placement of `restoreCallingIdentity` after
`transact`; restoration belongs in cleanup/finally semantics.

### 2. Android service and package primitives

Required hidden/platform API boundaries:

- `ServiceManager.getService`;
- packages for UID;
- package info / application info;
- permission checks;
- Android UID → app-id/user-id decomposition;
- process and UID observers.

### 3. ContentProvider Binder delivery

Required operations:

- external provider acquisition/release;
- provider Binder liveness;
- compatible provider `call`;
- Binder-in-Bundle transport.

### 4. Process startup

Required process/environment operations:

- current UID and PID;
- fork/detach or a deliberate Android equivalent;
- environment construction;
- `app_process` exec;
- root mount-namespace/cgroup setup if Crawl Space retains the Shizuku root
  starter path.

### 5. Executable acceptance

The present files are type/intent sketches; they do not yet claim current Idriç
parser or DEX-backend acceptance.

The first executable slice should be deliberately small:

1. obtain Binder caller UID/PID;
2. obtain a named system-service Binder;
3. forward one harmless transaction through a shell-started broker;
4. prove that system_server observes the broker identity;
5. kill the client and prove its registry record disappears through Binder
   death handling.

After that, add ContentProvider delivery and user services independently.

## Relationship to the existing Crawl Space daemon

The existing native Crawl Space daemon and this Binder broker solve different
boundaries:

```text
command bridge
Termux → authenticated socket → shell/root process → executable

Binder bridge
Android app → Binder → shell/root broker → system-service Binder
```

They should share the same authority vocabulary and eventually the same startup
policy, but neither needs to be disguised as the other. The command bridge
remains useful for programs and tests; the Binder bridge supplies the Shizuku
capability that ordinary Android apps need.
