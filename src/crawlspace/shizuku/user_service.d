module crawlspace.shizuku.user_service;

import crawlspace.shizuku.types;

struct ConnectionHandle
{
    void* raw;

    bool valid() const nothrow @nogc
    {
        return raw !is null;
    }
}

struct UserServiceIdentity
{
    ulong generation;
    string token;
}

struct UserServiceOptions
{
    string package_name;
    string class_name;

    string tag;
    bool has_tag;

    int version_code = 1;
    bool daemon = true;
    bool no_create;

    string process_name_suffix;
    bool use_32_bit_app_process;
    bool debug;
}

struct StartRequest
{
    UserServiceIdentity identity;
    string key;
    string package_name;
    string class_name;
    string process_name_suffix;
    AndroidUid calling_uid;
    bool use_32_bit_app_process;
    bool debug;
}

struct UserServiceRecord
{
    UserServiceIdentity identity;
    string key;
    string package_name;
    string class_name;
    int version_code;
    bool daemon;
    bool starting;
    BinderHandle service;
    ConnectionHandle[] connections;
}

enum UserServiceError : ubyte
{
    none,
    package_not_owned,
    token_not_found
}

struct AddUserServiceResult
{
    UserServiceError error;
    int wire_result;
    bool start_requested;
    UserServiceIdentity identity;

    bool ok() const nothrow @nogc
    {
        return error == UserServiceError.none;
    }
}

alias PackageOwnedByCaller = bool delegate(
    string package_name,
    int app_id,
    int user_id);
alias PingServiceBinder = bool delegate(BinderHandle binder);
alias UserServiceTokenFactory = string delegate();
alias LinkServiceDeath = bool delegate(
    BinderHandle binder,
    UserServiceIdentity identity);
alias UnlinkServiceDeath = void delegate(
    BinderHandle binder,
    UserServiceIdentity identity);
alias DestroyServiceBinder = void delegate(BinderHandle binder);
alias NotifyConnected = void delegate(
    ConnectionHandle connection,
    BinderHandle binder);
alias ScheduleUserServiceStart = void delegate(StartRequest request);

struct UserServiceOps
{
    PackageOwnedByCaller package_owned_by_caller;
    PingServiceBinder ping_service_binder;
    UserServiceTokenFactory token_factory;
    LinkServiceDeath link_service_death;
    UnlinkServiceDeath unlink_service_death;
    DestroyServiceBinder destroy_service_binder;
    NotifyConnected notify_connected;
    ScheduleUserServiceStart schedule_start;
}

string user_service_key(UserServiceOptions options)
{
    return options.package_name ~ ":" ~
        (options.has_tag ? options.tag : options.class_name);
}

private bool same_connection(ConnectionHandle a, ConnectionHandle b)
    nothrow @nogc
{
    return a.raw is b.raw;
}

private void register_connection(
    ref UserServiceRecord record,
    ConnectionHandle connection)
{
    foreach (existing; record.connections)
    {
        if (same_connection(existing, connection))
        {
            return;
        }
    }
    record.connections ~= connection;
}

private bool unregister_connection(
    ref UserServiceRecord record,
    ConnectionHandle connection)
{
    foreach (i, existing; record.connections)
    {
        if (!same_connection(existing, connection))
        {
            continue;
        }

        for (size_t j = i; j + 1 < record.connections.length; ++j)
        {
            record.connections[j] = record.connections[j + 1];
        }
        record.connections.length = record.connections.length - 1;
        return true;
    }
    return false;
}

private bool service_alive(
    ref UserServiceRecord record,
    UserServiceOps ops)
{
    return record.service.valid &&
        ops.ping_service_binder !is null &&
        ops.ping_service_binder(record.service);
}

private void broadcast_connected(
    ref UserServiceRecord record,
    UserServiceOps ops)
{
    if (ops.notify_connected is null || !record.service.valid)
    {
        return;
    }

    foreach (connection; record.connections)
    {
        ops.notify_connected(connection, record.service);
    }
}

struct UserServiceRegistry
{
private:
    UserServiceRecord[] records;
    ulong next_generation = 1;

    size_t find_key_index(string key) const
    {
        foreach (i, record; records)
        {
            if (record.key == key)
            {
                return i;
            }
        }
        return size_t.max;
    }

    size_t find_identity_index(UserServiceIdentity identity) const
    {
        foreach (i, record; records)
        {
            if (record.identity.generation == identity.generation &&
                record.identity.token == identity.token)
            {
                return i;
            }
        }
        return size_t.max;
    }

    void erase_index(size_t i)
    {
        for (size_t j = i; j + 1 < records.length; ++j)
        {
            records[j] = records[j + 1];
        }
        records.length = records.length - 1;
    }

public:
    size_t length() const nothrow @nogc
    {
        return records.length;
    }

    UserServiceRecord* find_by_key(string key)
    {
        auto i = find_key_index(key);
        return i == size_t.max ? null : &records[i];
    }

    UserServiceRecord* find_by_token(string token)
    {
        foreach (i, ref record; records)
        {
            if (record.identity.token == token)
            {
                return &records[i];
            }
        }
        return null;
    }

    bool remove_exact(
        UserServiceIdentity identity,
        UserServiceOps ops)
    {
        auto i = find_identity_index(identity);
        if (i == size_t.max)
        {
            return false;
        }

        auto service = records[i].service;

        /*
         * UserServiceRecord.destroy first unlinks death, then sends the
         * one-way destroy transaction only when the Binder still answers ping.
         * Callback-list teardown is represented here by dropping the record.
         */
        if (service.valid)
        {
            if (ops.unlink_service_death !is null)
            {
                ops.unlink_service_death(service, identity);
            }

            if (ops.ping_service_binder !is null &&
                ops.ping_service_binder(service) &&
                ops.destroy_service_binder !is null)
            {
                ops.destroy_service_binder(service);
            }
        }

        erase_index(i);
        return true;
    }

    UserServiceRecord* create_or_reuse(
        UserServiceOptions options,
        UserServiceOps ops)
    {
        auto key = user_service_key(options);
        auto record = find_by_key(key);

        if (record !is null)
        {
            bool replace = record.version_code != options.version_code;

            if (!replace && !record.starting)
            {
                replace = !service_alive(*record, ops);
            }

            if (!replace)
            {
                record.daemon = options.daemon;
                return record;
            }

            auto old_identity = record.identity;
            remove_exact(old_identity, ops);
        }

        UserServiceRecord fresh;
        fresh.identity.generation = next_generation++;
        fresh.identity.token = ops.token_factory();
        fresh.key = key;
        fresh.package_name = options.package_name;
        fresh.class_name = options.class_name;
        fresh.version_code = options.version_code;
        fresh.daemon = options.daemon;

        records ~= fresh;
        return &records[$ - 1];
    }
}

private bool package_owned(
    AndroidUid calling_uid,
    UserServiceOptions options,
    UserServiceOps ops)
{
    if (ops.package_owned_by_caller is null)
    {
        return false;
    }

    return ops.package_owned_by_caller(
        options.package_name,
        android_app_id(calling_uid),
        android_user_id(calling_uid));
}

AddUserServiceResult add_user_service(
    ref UserServiceRegistry registry,
    ConnectionHandle connection,
    UserServiceOptions options,
    ApiVersion calling_api_version,
    AndroidUid calling_uid,
    UserServiceOps ops)
{
    if (!package_owned(calling_uid, options, ops))
    {
        return AddUserServiceResult(
            UserServiceError.package_not_owned);
    }

    auto key = user_service_key(options);

    if (options.no_create)
    {
        auto record = registry.find_by_key(key);

        if (record !is null)
        {
            register_connection(*record, connection);

            if (service_alive(*record, ops))
            {
                broadcast_connected(*record, ops);

                return AddUserServiceResult(
                    UserServiceError.none,
                    calling_api_version >= shizuku_api_v13
                        ? record.version_code
                        : 0,
                    false,
                    record.identity);
            }
        }

        return AddUserServiceResult(
            UserServiceError.none,
            calling_api_version >= shizuku_api_v13 ? -1 : 1,
            false,
            record is null
                ? UserServiceIdentity.init
                : record.identity);
    }

    auto record = registry.create_or_reuse(options, ops);
    register_connection(*record, connection);

    if (service_alive(*record, ops))
    {
        broadcast_connected(*record, ops);
    }
    else if (!record.starting)
    {
        /*
         * Upstream marks starting and installs a 30-second timeout before
         * queuing the shell/app_process start. Timeout machinery belongs at
         * the Android scheduler boundary; the state transition belongs here.
         */
        record.starting = true;

        if (ops.schedule_start !is null)
        {
            StartRequest request;
            request.identity = record.identity;
            request.key = record.key;
            request.package_name = options.package_name;
            request.class_name = options.class_name;
            request.process_name_suffix = options.process_name_suffix;
            request.calling_uid = calling_uid;
            request.use_32_bit_app_process =
                options.use_32_bit_app_process;
            request.debug = options.debug;
            ops.schedule_start(request);
        }

        return AddUserServiceResult(
            UserServiceError.none,
            0,
            true,
            record.identity);
    }

    return AddUserServiceResult(
        UserServiceError.none,
        0,
        false,
        record.identity);
}

int remove_user_service(
    ref UserServiceRegistry registry,
    ConnectionHandle connection,
    UserServiceOptions options,
    AndroidUid calling_uid,
    bool remove,
    UserServiceOps ops,
    out UserServiceError error)
{
    if (!package_owned(calling_uid, options, ops))
    {
        error = UserServiceError.package_not_owned;
        return 1;
    }

    auto record = registry.find_by_key(user_service_key(options));
    if (record is null)
    {
        error = UserServiceError.none;
        return 1;
    }

    if (remove)
    {
        auto identity = record.identity;
        registry.remove_exact(identity, ops);
    }
    else
    {
        unregister_connection(*record, connection);

        if (!record.daemon && record.connections.length == 0)
        {
            auto identity = record.identity;
            registry.remove_exact(identity, ops);
        }
    }

    error = UserServiceError.none;
    return 0;
}

UserServiceError attach_user_service(
    ref UserServiceRegistry registry,
    BinderHandle service,
    string token,
    UserServiceOps ops)
{
    auto record = registry.find_by_token(token);
    if (record is null)
    {
        return UserServiceError.token_not_found;
    }

    record.service = service;

    /*
     * Upstream logs linkToDeath failure but keeps the Binder and broadcasts it.
     * It also cancels the start timeout without clearing the starting bit.
     */
    if (ops.link_service_death !is null)
    {
        ops.link_service_death(service, record.identity);
    }

    broadcast_connected(*record, ops);
    return UserServiceError.none;
}

bool user_service_binder_died(
    ref UserServiceRegistry registry,
    UserServiceIdentity identity,
    UserServiceOps ops)
{
    return registry.remove_exact(identity, ops);
}

bool user_service_connection_died(
    ref UserServiceRegistry registry,
    UserServiceIdentity identity,
    ConnectionHandle connection,
    UserServiceOps ops)
{
    auto record = registry.find_by_token(identity.token);
    if (record is null ||
        record.identity.generation != identity.generation)
    {
        return false;
    }

    unregister_connection(*record, connection);

    if (!record.daemon && record.connections.length == 0)
    {
        registry.remove_exact(identity, ops);
    }

    return true;
}
