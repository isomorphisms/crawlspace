module crawlspace.shizuku.android_boundary;

import crawlspace.shizuku.service;
import crawlspace.shizuku.types;

alias AndroidCallingUid = AndroidUid delegate();
alias AndroidCallingPid = AndroidPid delegate();

alias AndroidReadStrongBinder =
    bool delegate(ParcelHandle parcel, out BinderHandle binder);
alias AndroidReadInt32 =
    bool delegate(ParcelHandle parcel, out int value);

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

struct PublicNdkBinderOps
{
    AndroidCallingUid calling_uid;
    AndroidCallingPid calling_pid;
    AndroidReadStrongBinder read_strong_binder;
    AndroidReadInt32 read_int32;
    AndroidCreateParcel create_parcel;
    AndroidDeleteParcel delete_parcel;
    AndroidParcelPosition parcel_position;
    AndroidParcelSize parcel_size;
    AndroidAppendParcel append_parcel;
    AndroidBinderTransact transact;

    bool complete_for_remote_forwarding() const
        nothrow @nogc
    {
        return calling_uid !is null &&
            calling_pid !is null &&
            read_strong_binder !is null &&
            read_int32 !is null &&
            create_parcel !is null &&
            delete_parcel !is null &&
            parcel_position !is null &&
            parcel_size !is null &&
            append_parcel !is null &&
            transact !is null;
    }
}

/*
 * There is intentionally no "NDK fallback" for this pair. Public
 * libbinder_ndk exposes caller UID/PID but not Binder.clearCallingIdentity /
 * restoreCallingIdentity. Exact Shizuku forwarding needs this explicit bridge.
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
    incomplete_public_ndk,
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

BinderCaller binder_caller(PublicNdkBinderOps ndk)
{
    return BinderCaller(
        ndk.calling_uid(),
        ndk.calling_pid());
}

AndroidServiceAdapter build_android_service_adapter(
    PublicNdkBinderOps ndk,
    BinderIdentityBridge identity)
{
    AndroidServiceAdapter result;

    if (!ndk.complete_for_remote_forwarding)
    {
        result.error =
            AndroidBoundaryError.incomplete_public_ndk;
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
        if (!ndk.read_strong_binder(parcel, binder))
        {
            return BinderHandle.init;
        }
        return binder;
    }

    int read_int(ParcelHandle parcel)
    {
        int value;
        if (!ndk.read_int32(parcel, value))
        {
            return 0;
        }
        return value;
    }

    ParcelHandle obtain_parcel()
    {
        return ndk.create_parcel();
    }

    bool append_remaining(
        ParcelHandle source,
        ParcelHandle target)
    {
        auto start = ndk.parcel_position(source);
        auto end = ndk.parcel_size(source);

        if (start < 0 ||
            end < start)
        {
            return false;
        }

        return ndk.append_parcel(
            source,
            target,
            start,
            end - start);
    }

    void recycle_parcel(ParcelHandle parcel)
    {
        ndk.delete_parcel(parcel);
    }

    bool transact(
        BinderHandle target,
        TransactionCode code,
        ParcelHandle data,
        ParcelHandle reply,
        TransactionFlags flags)
    {
        return ndk.transact(
            target,
            code,
            data,
            reply,
            flags);
    }

    result.service_ops.read_binder = &read_binder;
    result.service_ops.read_int = &read_int;
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
