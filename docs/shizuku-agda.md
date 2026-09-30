# Shizuku in Agda

This branch translates the privileged core of Shizuku into a small Agda model so the security boundary can be read as types and state transitions rather than as Android framework plumbing.

Reference snapshot:

- RikkaApps/Shizuku: `b844bc491f1790c72328e1a8e5b2349f8978f0ea`
- Shizuku-API submodule: `a27f6e4151ba7b39965ca47edb2bf0aeed7102e5`

The translation deliberately uses only Agda builtins. It does not depend on the Agda standard library.

## Map

| Upstream piece | Agda module | What is represented |
| --- | --- | --- |
| `IShizukuService.aidl` | `Shizuku.Protocol` | Typed calls and the exact AIDL transaction numbers |
| `Service.java`, `ShizukuService.java` | `Shizuku.Policy`, `Shizuku.Server` | Caller classes, permission gates, client records, permission state, user-service state |
| `UserServiceManager.java` | `Shizuku.Server` | User-service records, attach, death, package revocation |
| `ShizukuProvider.java` | `Shizuku.Provider` | Binder receipt, liveness, retrieval, multi-process broadcast decision |
| `Shizuku.java` | `Shizuku.Client` | Client binding state and server metadata received with the binder |
| `ServiceStarter.java` | `Shizuku.Starter` | ADB/root bootstrap and the server startup stages |
| Android hidden/framework APIs | `Shizuku.Android` | Abstract effect boundary that a real Android backend must implement |

## Permission shape

The important distinction in Shizuku is retained explicitly.

- An unattached process may enter through `attach-application`, but package ownership must be checked.
- An attached but denied client can ask about or request its own permission.
- Privileged operations such as starting a process, reading or setting system properties, and managing user services require an allowed attached client, the manager, the server itself, or the manifest-permission path used by Shizuku.
- Manager-only operations remain separate: exit, attaching a user-service binder, permission-result dispatch, and flag administration.
- The Sui-only transaction slots in standalone Shizuku are represented as placeholders rather than pretending they carry behavior here.

## State model

`Shizuku.Server` makes the mutable Java bookkeeping explicit:

```text
ServerState
  server identity  shell | root
  clients          uid/pid/package/api/grant
  services         package/class/tag/token/version/lifetime
  permissions      persisted uid/package/grant entries
```

Permission results update all client records for the UID, as the Java server does. Persistent results additionally update the permission table; one-time results do not. Package revocation has an explicit operation for removing that package's user services.

## Android boundary

Agda is not replacing Binder, PackageManager, ActivityManager, app_process, or ContentProvider by magic. `Shizuku.Android.AndroidOps` names those effects and facts without baking Java/Kotlin into the model.

That gives Crawl Space a usable split:

```text
Agda
  protocol
  policy
  state
  proofs/invariants
        |
        v
Android backend
  Binder / app_process / PackageManager / ActivityManager
```

The backend can later be C/NDK, Idriç, or another low-level implementation while keeping the same typed policy.

## Check

With Agda installed:

```sh
sh scripts/check_agda.sh
```

which runs:

```sh
agda -i agda agda/Shizuku.agda
```

The current branch is a translation of the privileged runtime architecture, not the Shizuku Manager UI.
