module crawlspace.shizuku.android_boundary;

import crawlspace.shizuku.service;
import crawlspace.shizuku.types;

alias AndroidCallingUid = AndroidUid delegate();
alias AndroidCallingPid = AndroidPid delegate();

struct StableNdkCallerOps
{
    AndroidCallingUid calling_uid;
    AndroidCallingPid calling_pid;

    bool complete() const nothrow @nogc
    {
        return calling_uid !is null &&
            calling_pid !is null;
    }
}

BinderCaller binder_caller(StableNdkCallerOps ndk)
{
    return BinderCaller(
        ndk.calling_uid(),
        ndk.calling_pid());
}

alias AndroidReadStrongBinder =
    bool delegate(ParcelHandle parcel, out BinderHandle binder);
alias AndroidReadInt32 =
    bool delegate(ParcelHandle parcel, out int value);
alias AndroidReleaseBinder =
    void delegate(BinderHandle binder);

alias AndroidCreateParcel = ParcelHandle delegate();
alias AndroidDeleteParcel = void delegate(ParcelHandle parcel);
alias AndroidParcelPosition = int delegate(ParcelHandle parcel);
alias AndroidParcelSize = int delegate(ParcelHandle parcel);
alias AndroidAppendParcel =
    bool delegate(
        ParcelHandle source,
        ParcelHandle target,
        int start,
        int size);

alias AndroidBinderTransact =
    bool delegate(
        BinderHandle target,
        TransactionCode code,
        ParcelHandle data,
        ParcelHandle reply,
        TransactionFlags flags);

/*
 * Transparent Shizuku forwarding is deliberately a separate bridge.
 *
 * Stable libbinder_ndk exposes many of these individual primitives, but its
 * AIBinder_transact contract is not transparent: the input must come from
 * AIBinder_prepareTransaction, and prepareTransaction requires the target to be
 * associated with an NDK Binder class. Shizuku instead receives an arbitrary
 * target Binder and copies the caller's remaining opaque Parcel bytes.
 *
 * Therefore this bridge must be backed by either:
 *   - a narrow Java/framework JNI bridge using android.os.Parcel/IBinder; or
 *   - a platform-libbinder bridge with equivalent opaque transact semantics.
 *
 * Do not implement AndroidBinderTransact by directly passing an AParcel_create
 * parcel to AIBinder_transact.
 */
struct TransparentBinderBridge
{
    AndroidReadStrongBinder read_strong_binder;
    AndroidReadInt32 read_int32;
    AndroidReleaseBinder release_binder;
    AndroidCreateParcel create_parcel;
    AndroidDeleteParcel delete_parcel;
    AndroidParcelPosition parcel_position;
    AndroidParcelSize parcel_size;
    AndroidAppendParcel append_parcel;
    AndroidBinderTransact transact;

    bool complete() const nothrow @nogc
    {
        return read_strong_binder !is null &&
            read_int32 !is null &&
            release_binder !is null &&
            create_parcel !is null &&
            delete_parcel !is null &&
            parcel_position !is null &&
            parcel_size !is null &&
            append_parcel !is null &&
            transact !is null;
    }
}

/*
 * Public libbinder_ndk exposes caller UID/PID but not the Java Binder
 * clearCallingIdentity / restoreCallingIdentity pair. Exact Shizuku forwarding
 * needs this capability explicitly.
 */
struct BinderIdentityBridge
{
    ClearCallingIdentity clear_calling_identity;
    RestoreCallingIdentity restore_calling_identity;

    bool complete() const nothrow @nogc
    {
        return clear_calling_identity !is null &&
            restore_calling_identity !is null;
    }
}

enum AndroidBoundaryError : ubyte
{
    none,
    incomplete_transparent_bridge,
    missing_identity_bridge
}

struct AndroidServiceAdapter
{
    AndroidBoundaryError error;
    ServiceOps service_ops;

    bool ready() const nothrow @nogc
    {
        return error == AndroidBoundaryError.none;
    }
}

AndroidServiceAdapter build_android_service_adapter(
    TransparentBinderBridge bridge,
    BinderIdentityBridge identity)
{
    AndroidServiceAdapter result;

    if (!bridge.complete)
    {
        result.error =
            AndroidBoundaryError.incomplete_transparent_bridge;
        return result;
    }

    if (!identity.complete)
    {
        result.error =
            AndroidBoundaryError.missing_identity_bridge;
        return result;
    }

    BinderHandle read_binder(ParcelHandle parcel)
    {
        BinderHandle binder;
        if (!bridge.read_strong_binder(parcel, binder))
        {
            return BinderHandle.init;
        }
        return binder;
    }

    int read_int(ParcelHandle parcel)
    {
        int value;
        if (!bridge.read_int32(parcel, value))
        {
            return 0;
        }
        return value;
    }

    ParcelHandle obtain_parcel()
    {
        return bridge.create_parcel();
    }

    bool append_remaining(
        ParcelHandle source,
        ParcelHandle target)
    {
        auto start = bridge.parcel_position(source);
        auto end = bridge.parcel_size(source);

        if (start < 0 ||
            end < start)
        {
            return false;
        }

        return bridge.append_parcel(
            source,
            target,
            start,
            end - start);
    }

    void recycle_parcel(ParcelHandle parcel)
    {
        bridge.delete_parcel(parcel);
    }

    bool transact(
        BinderHandle target,
        TransactionCode code,
        ParcelHandle data,
        ParcelHandle reply,
        TransactionFlags flags)
    {
        return bridge.transact(
            target,
            code,
            data,
            reply,
            flags);
    }

    result.service_ops.read_binder = &read_binder;
    result.service_ops.read_int = &read_int;
    result.service_ops.release_binder =
        bridge.release_binder;
    result.service_ops.obtain_parcel = &obtain_parcel;
    result.service_ops.append_remaining = &append_remaining;
    result.service_ops.recycle_parcel = &recycle_parcel;
    result.service_ops.clear_calling_identity =
        identity.clear_calling_identity;
    result.service_ops.restore_calling_identity =
        identity.restore_calling_identity;
    result.service_ops.binder_transact = &transact;
    result.error = AndroidBoundaryError.none;

    return result;
}
