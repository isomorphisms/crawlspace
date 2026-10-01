module crawlspace.shizuku.clients;

import crawlspace.shizuku.types;

enum AttachError : ubyte
{
    none,
    package_not_owned_by_uid,
    link_to_death_failed
}

enum AuthorizationError : ubyte
{
    none,
    not_attached,
    permission_denied
}

struct ClientToken
{
    ClientKey key;
    ulong generation;
}

struct ClientRecord
{
    ClientToken token;
    BinderHandle callback;
    string package_name;
    ApiVersion api_version;
    bool allowed;
}

struct AttachResult
{
    AttachError error;
    ClientToken token;
    bool already_attached;

    bool ok() const nothrow @nogc
    {
        return error == AttachError.none;
    }
}

struct Authorization
{
    AuthorizationError error;
    AuthorizationReason reason;

    bool allowed() const nothrow @nogc
    {
        return error == AuthorizationError.none;
    }
}

alias PackageBelongsToUid = bool delegate(AndroidUid uid, string package_name);
alias InitialPermission = bool delegate(AndroidUid uid);
alias LinkToDeath = bool delegate(BinderHandle callback, ClientToken token);
alias RuntimePermissionCheck = bool delegate(BinderCaller caller);

struct ClientRegistry
{
private:
    ClientRecord[] records;
    ulong next_generation = 1;

    size_t find_index(ClientKey key) const nothrow @nogc
    {
        foreach (i, ref const record; records)
        {
            if (record.token.key == key)
            {
                return i;
            }
        }
        return size_t.max;
    }

public:
    size_t length() const nothrow @nogc
    {
        return records.length;
    }

    ClientRecord* find_client(ClientKey key) nothrow @nogc
    {
        const i = find_index(key);
        if (i == size_t.max)
        {
            return null;
        }
        return &records[i];
    }

    const(ClientRecord)* find_client(ClientKey key) const nothrow @nogc
    {
        const i = find_index(key);
        if (i == size_t.max)
        {
            return null;
        }
        return &records[i];
    }

    ClientRecord*[] find_clients(AndroidUid uid)
    {
        ClientRecord*[] result;
        foreach (ref record; records)
        {
            if (record.token.key.uid == uid)
            {
                result ~= &record;
            }
        }
        return result;
    }

    bool remove_exact(ClientToken token)
    {
        foreach (i, ref record; records)
        {
            if (record.token == token)
            {
                for (size_t j = i; j + 1 < records.length; ++j)
                {
                    records[j] = records[j + 1];
                }
                records.length = records.length - 1;
                return true;
            }
        }
        return false;
    }

    ClientToken add_client(
        BinderCaller caller,
        BinderHandle callback,
        string package_name,
        ApiVersion api_version,
        InitialPermission initial_permission,
        LinkToDeath link_to_death,
        out AttachError error)
    {
        ClientRecord record;
        record.token = ClientToken(client_key(caller), next_generation++);
        record.callback = callback;
        record.package_name = package_name;
        record.api_version = api_version;
        record.allowed =
            initial_permission !is null && initial_permission(caller.uid);

        /*
         * Upstream Shizuku links callback death before publishing the record.
         * The death callback captures the exact ClientRecord object. The
         * generation token preserves that identity property without relying on
         * a moving D array address.
         */
        if (link_to_death is null || !link_to_death(callback, record.token))
        {
            error = AttachError.link_to_death_failed;
            return ClientToken.init;
        }

        records ~= record;
        error = AttachError.none;
        return record.token;
    }
}

AttachResult attach_application(
    ref ClientRegistry registry,
    BinderCaller caller,
    string requested_package,
    BinderHandle callback,
    ApiVersion api_version,
    PackageBelongsToUid package_belongs_to_uid,
    InitialPermission initial_permission,
    LinkToDeath link_to_death)
{
    if (package_belongs_to_uid is null ||
        !package_belongs_to_uid(caller.uid, requested_package))
    {
        return AttachResult(AttachError.package_not_owned_by_uid);
    }

    auto existing = registry.find_client(client_key(caller));
    if (existing !is null)
    {
        return AttachResult(
            AttachError.none,
            existing.token,
            true);
    }

    AttachError error;
    const token = registry.add_client(
        caller,
        callback,
        requested_package,
        api_version,
        initial_permission,
        link_to_death,
        error);

    return AttachResult(error, token, false);
}

Authorization authorize_caller(
    ref ClientRegistry registry,
    BinderCaller caller,
    AndroidUid server_uid,
    int manager_app_id,
    RuntimePermissionCheck runtime_permission)
{
    if (caller.uid == server_uid)
    {
        return Authorization(
            AuthorizationError.none,
            AuthorizationReason.server_uid);
    }

    if (android_app_id(caller.uid) == manager_app_id)
    {
        return Authorization(
            AuthorizationError.none,
            AuthorizationReason.manager_app_id);
    }

    auto record = registry.find_client(client_key(caller));

    /*
     * This matches ShizukuService.checkCallerPermission: the runtime API
     * permission bypass applies only before attachment. Once a client record
     * exists, its explicit allowed bit controls access.
     */
    if (record is null)
    {
        if (runtime_permission !is null && runtime_permission(caller))
        {
            return Authorization(
                AuthorizationError.none,
                AuthorizationReason.runtime_permission_unattached);
        }

        return Authorization(AuthorizationError.not_attached);
    }

    if (record.allowed)
    {
        return Authorization(
            AuthorizationError.none,
            AuthorizationReason.attached_permission);
    }

    return Authorization(AuthorizationError.permission_denied);
}
