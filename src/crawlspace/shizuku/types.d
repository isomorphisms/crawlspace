module crawlspace.shizuku.types;

alias AndroidUid = int;
alias AndroidPid = int;
alias ApiVersion = int;
alias TransactionCode = int;
alias TransactionFlags = int;

enum int android_uid_per_user_range = 100_000;
enum int shizuku_api_v13 = 13;

struct BinderHandle
{
    void* raw;

    bool valid() const nothrow @nogc
    {
        return raw !is null;
    }
}

struct ParcelHandle
{
    void* raw;

    bool valid() const nothrow @nogc
    {
        return raw !is null;
    }
}

struct BinderCaller
{
    AndroidUid uid;
    AndroidPid pid;
}

struct ClientKey
{
    AndroidUid uid;
    AndroidPid pid;
}

ClientKey client_key(BinderCaller caller) nothrow @nogc
{
    return ClientKey(caller.uid, caller.pid);
}

int android_app_id(AndroidUid uid) nothrow @nogc
{
    return uid % android_uid_per_user_range;
}

int android_user_id(AndroidUid uid) nothrow @nogc
{
    return uid / android_uid_per_user_range;
}

enum AuthorizationReason : ubyte
{
    server_uid,
    manager_app_id,
    runtime_permission_unattached,
    attached_permission
}
