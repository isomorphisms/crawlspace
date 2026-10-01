# Shizuku logic in D

This branch translates the Shizuku behavior needed by Crawl Space into ordinary
D source.

Pinned upstream sources:

- `RikkaApps/Shizuku@b844bc491f1790c72328e1a8e5b2349f8978f0ea`
- `RikkaApps/Shizuku-API@a27f6e4151ba7b39965ca47edb2bf0aeed7102e5`

The Idriç files on the parent `shizuku` branch remain useful as a semantic map.
The files under `src/crawlspace/shizuku/` are the executable-language
translation.

## Implemented D slice

### `types.d`

Shared Shizuku-facing types:

- Android UID/PID;
- Binder caller identity;
- client keys;
- Binder/Parcel opaque handles;
- API and transaction types;
- Android app-id/user-id decomposition.

### `clients.d`

Translation of the important `ClientManager`, `ClientRecord`, and
`ShizukuService.attachApplication` policy:

- prove the requested package belongs to Binder's calling UID before attach;
- do not create a second record for an already attached UID/PID;
- initialize `allowed` from persistent configuration;
- link callback Binder death before publishing a new client;
- remove by exact registration identity rather than merely UID/PID;
- preserve Shizuku's permission ordering;
- allow the runtime Shizuku permission to bypass attachment only when no client
  record exists.

The D registry uses a monotonically increasing generation in `ClientToken`.
That corresponds to the Java death-recipient closure capturing one exact
`ClientRecord`: a delayed death callback from an old registration cannot
delete a newer process record with the same UID/PID.

### `service.d`

Translation of `Service.transactRemote`:

1. authorize the Binder caller;
2. read target Binder and transaction code;
3. for attached API >= 13 clients, read target flags from the forwarded payload;
   older/unattached callers use the outer Binder flags;
4. obtain a fresh Parcel and append the unread input bytes;
5. clear Binder calling identity;
6. transact on the target Binder;
7. restore calling identity;
8. recycle the temporary Parcel.

The D implementation deliberately uses `scope(exit)` for both identity
restoration and Parcel recycling. The pinned Java source recycles in `finally`
but places `restoreCallingIdentity` before the `finally`; an exception from
the target transaction can therefore skip restoration. Crawl Space treats
identity restoration as part of the capability boundary and makes it
cleanup-safe.

## Android boundary

These files contain Shizuku logic, not another private Binder implementation.
The concrete Android operations should be supplied by the D Android seam in
`dilapidated-shed/ick:dmd-shizuku-android-touchpoints`.

That branch already defines D declarations for Binder, Parcel, Binder death,
transactions, JNI Binder conversion, status handling, and Android logging.

The next translation slices in Crawl Space are:

- Binder-delivery / ContentProvider retry policy;
- permission-result/config propagation;
- user-service records and version compatibility;
- process startup and server lifecycle;
- the rish service-facing logic.

Compiler/ABI qualification belongs in Ick; Shizuku policy remains here.
