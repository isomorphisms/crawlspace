module crawlspace.shizuku.service;

import crawlspace.shizuku.clients;
import crawlspace.shizuku.types;

enum TransactRemoteError : ubyte
{
    none,
    permission_denied,
    append_failed
}

struct TransactRemoteResult
{
    TransactRemoteError error;
    bool target_accepted;

    bool ok() const nothrow @nogc
    {
        return error == TransactRemoteError.none;
    }
}

alias ReadBinder = BinderHandle delegate(ParcelHandle parcel);
alias ReadInt = int delegate(ParcelHandle parcel);
alias ReleaseBinder = void delegate(BinderHandle binder);
alias ObtainParcel = ParcelHandle delegate();
alias AppendRemaining = bool delegate(ParcelHandle source, ParcelHandle target);
alias RecycleParcel = void delegate(ParcelHandle parcel);
alias ClearCallingIdentity = ulong delegate();
alias RestoreCallingIdentity = void delegate(ulong identity);
alias BinderTransact = bool delegate(
    BinderHandle target,
    TransactionCode code,
    ParcelHandle data,
    ParcelHandle reply,
    TransactionFlags flags);

struct ServiceOps
{
    ReadBinder read_binder;
    ReadInt read_int;
    ReleaseBinder release_binder;
    ObtainParcel obtain_parcel;
    AppendRemaining append_remaining;
    RecycleParcel recycle_parcel;
    ClearCallingIdentity clear_calling_identity;
    RestoreCallingIdentity restore_calling_identity;
    BinderTransact binder_transact;
}

TransactionFlags target_flags_for_client(
    const(ClientRecord)* client,
    TransactionFlags outer_flags,
    ParcelHandle input,
    ReadInt read_int)
{
    if (client !is null && client.api_version >= shizuku_api_v13)
    {
        return read_int(input);
    }
    return outer_flags;
}

TransactRemoteResult transact_remote(
    ref ClientRegistry clients,
    BinderCaller caller,
    AndroidUid server_uid,
    int manager_app_id,
    RuntimePermissionCheck runtime_permission,
    ParcelHandle input,
    ParcelHandle reply,
    TransactionFlags outer_flags,
    ServiceOps ops)
{
    const authorization = authorize_caller(
        clients,
        caller,
        server_uid,
        manager_app_id,
        runtime_permission);

    if (!authorization.allowed)
    {
        return TransactRemoteResult(
            TransactRemoteError.permission_denied,
            false);
    }

    auto target = ops.read_binder(input);

    if (target.valid && ops.release_binder !is null)
    {
        scope (exit)
        {
            ops.release_binder(target);
        }
    }

    auto target_code = cast(TransactionCode) ops.read_int(input);
    auto client = clients.find_client(client_key(caller));
    auto target_flags = target_flags_for_client(
        client,
        outer_flags,
        input,
        ops.read_int);

    auto forwarded_data = ops.obtain_parcel();
    scope (exit)
    {
        ops.recycle_parcel(forwarded_data);
    }

    if (!ops.append_remaining(input, forwarded_data))
    {
        return TransactRemoteResult(
            TransactRemoteError.append_failed,
            false);
    }

    auto identity = ops.clear_calling_identity();

    /*
     * Upstream currently restores identity after transact but before its
     * finally block. In D, make the intended capability boundary explicit:
     * restore the Binder identity on both success and exception.
     */
    scope (exit)
    {
        ops.restore_calling_identity(identity);
    }

    auto accepted = ops.binder_transact(
        target,
        target_code,
        forwarded_data,
        reply,
        target_flags);

    return TransactRemoteResult(
        TransactRemoteError.none,
        accepted);
}
