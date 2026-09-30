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


## Generic Binder lowering home

The reusable Binder mechanics do not belong in Crawl Space itself. They now have
a dedicated working branch in `isomorphisms/android-NDK`:

```text
binder/idric-shizuku
```

That branch adds:

- `binder/README.md` — the generic Binder/system-service boundary and
  acceptance ladder;
- `dex/idric/src/Backend/DEX/Framework.idr` — typed DEX class/method
  references, invoke kinds, the opaque wide calling-identity token, and the
  exact first-slice instruction requirements;
- `dex/idric/tests/dex/FrameworkPlanTest.idr` — descriptor/type-plan checks.

The existing DEX encoder already has a narrow external-call precedent for
`String.equals`: it emits a method reference, `invoke-virtual`, and
`move-result`. The Binder work should generalize that machinery rather than
create a parallel encoder.

The first faithful DEX slice adds three things that precedent does not supply:

1. arbitrary typed external method references and static/interface invocation;
2. an opaque two-register `long` result for
   `Binder.clearCallingIdentity()`;
3. catch-all cleanup with `move-exception`, identity restoration, and rethrow.

The calling-identity token is target plumbing. It must not become a reason to
change Idriç's ordinary numeric defaults or expose a general host `Long`
through the application language.

### Native NDK alternative

A native Binder broker is also plausible. Public NDK Binder APIs cover local
Binder classes, caller UID/PID, parcels, transactions, liveness, and death
recipients. That lane is useful for Crawl Space and should remain available.

It is not currently treated as a drop-in implementation of Shizuku's transparent
remote-transaction path. Public NDK Binder does not expose the Java
`clearCallingIdentity` / `restoreCallingIdentity` pair, and its transaction
API uses an associated Binder class/interface descriptor rather than Shizuku's
arbitrary target-Binder + copied-Parcel forwarding shape. Those differences need
their own proof before claiming behavioral equivalence.

For the faithful first translation, direct DEX/framework lowering therefore
remains the narrower acceptance target. The NDK route is a parallel candidate,
not a fallback silently substituted for it.


## Lowering status

The generic Binder branch has moved beyond the initial type inventory.

### Direct DEX path

The production DEX writer now has target support for the first Shizuku
transaction slice:

- globally sorted generated and external method references;
- typed `invoke-static`, `invoke-virtual`, and `invoke-interface`;
- ordinary, object, and wide move-result instructions;
- `move-wide` for the opaque calling-identity token;
- reference, `long`, and `void` method descriptors;
- `outs_size` measured in DEX argument words;
- catch-all `try_item` metadata;
- `move-exception` and rethrow;
- a verifier-facing rule that a catch handler starts with
  `move-exception`.

The generated framework probe now describes the important cleanup shape
directly:

```text
identity ← Binder.clearCallingIdentity()

try:
    result ← target.transact(code, data, reply, flags)

success:
    Binder.restoreCallingIdentity(identity)

catch all exception:
    Binder.restoreCallingIdentity(identity)
    throw exception
```

This is still a target-plan acceptance slice, not yet a claim that ordinary
Idriç source lowers Binder calls automatically.

### Public NDK path

The public-NDK lane is narrower than the original experiment suggested.

The packaged NDK contains the stable Binder/parcel/JNI bridge headers used for:

- caller UID/PID while handling a Binder transaction;
- `AIBinder` liveness and class association;
- typed `AParcel` transactions;
- Java `android.os.IBinder` → native `AIBinder` conversion through
  `AIBinder_fromJavaBinder`.

The ordinary packaged NDK does **not** contain the platform
`binder_manager.h` or `binder_process.h` headers. Accordingly, the generic
public-NDK façade no longer claims ServiceManager lookup or Binder process
thread-pool control. It operates on a Binder handle delivered through an
explicit boundary, such as JNI, or returned by another transaction.

That lane also still lacks the Java clear/restore-calling-identity pair and the
opaque `Parcel.appendFrom` operation needed by Shizuku's transparent forwarding
mechanism. It remains useful, but it is not evidence for full Shizuku
equivalence.

### Checked-source path

Source-level lowering is being kept separate from the already working target
plan on branch:

```text
isomorphisms/android-NDK:binder/idric-shizuku-source
```

Its first contract is a checked foreign calling convention:

```text
dex:<static|virtual|interface>:<owner descriptor>:<method>:<DEX descriptor>
```

For example:

```text
dex:static:Landroid/os/Binder;:getCallingUid:()I
dex:static:Landroid/os/Binder;:restoreCallingIdentity:(J)V
dex:interface:Landroid/os/IBinder;:transact:(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
```

The backend parses the DEX descriptor and cross-checks it against the compiler's
checked foreign `CFType` signature. Binder caller identity is deliberately
treated as `PrimIO`: its `%World` argument and `IORes` result are part of the
source semantics even though the eventual DEX method boundary should erase the
world token and unwrap the newtype result.

That source contract is being typechecked before it is admitted into
`Lower.idr`. The next source-lowering step is therefore not name matching; it
is explicit `PrimIO`/world erasure plus width-aware local register placement.
