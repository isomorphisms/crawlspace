module shizuku_d_logic_test;

import crawlspace.shizuku.clients;
import crawlspace.shizuku.delivery;
import crawlspace.shizuku.service;
import crawlspace.shizuku.types;

private BinderHandle binder_handle(size_t value)
{
    return BinderHandle(cast(void*) value);
}

private ParcelHandle parcel_handle(size_t value)
{
    return ParcelHandle(cast(void*) value);
}

unittest
{
    ClientRegistry clients;
    BinderCaller caller = BinderCaller(10_123, 77);

    bool linked;
    ClientToken death_token;

    bool owns_package(AndroidUid uid, string package_name)
    {
        return uid == caller.uid && package_name == "example.client";
    }

    bool initially_allowed(AndroidUid uid)
    {
        return uid == caller.uid;
    }

    bool link_death(BinderHandle callback, ClientToken token)
    {
        linked = callback.valid;
        death_token = token;
        return true;
    }

    auto attached = attach_application(
        clients,
        caller,
        "example.client",
        binder_handle(1),
        13,
        &owns_package,
        &initially_allowed,
        &link_death);

    assert(attached.ok);
    assert(!attached.already_attached);
    assert(linked);
    assert(clients.length == 1);

    auto record = clients.find_client(client_key(caller));
    assert(record !is null);
    assert(record.allowed);
    assert(record.api_version == 13);
    assert(record.token == death_token);

    auto again = attach_application(
        clients,
        caller,
        "example.client",
        binder_handle(2),
        13,
        &owns_package,
        &initially_allowed,
        &link_death);

    assert(again.ok);
    assert(again.already_attached);
    assert(clients.length == 1);

    const old_token = record.token;
    assert(clients.remove_exact(old_token));
    assert(clients.length == 0);

    auto replacement = attach_application(
        clients,
        caller,
        "example.client",
        binder_handle(3),
        13,
        &owns_package,
        &initially_allowed,
        &link_death);

    assert(replacement.ok);
    assert(replacement.token.generation != old_token.generation);

    // A delayed death notification from the old registration is harmless.
    assert(!clients.remove_exact(old_token));
    assert(clients.length == 1);
}

unittest
{
    ClientRegistry clients;
    BinderCaller caller = BinderCaller(10_321, 88);

    bool wrong_package(AndroidUid, string)
    {
        return false;
    }

    bool initial(AndroidUid)
    {
        return false;
    }

    bool link(BinderHandle, ClientToken)
    {
        assert(0, "linkToDeath must not run before package ownership proof");
        return true;
    }

    auto result = attach_application(
        clients,
        caller,
        "other.package",
        binder_handle(1),
        13,
        &wrong_package,
        &initial,
        &link);

    assert(!result.ok);
    assert(result.error == AttachError.package_not_owned_by_uid);
    assert(clients.length == 0);
}

unittest
{
    ClientRegistry clients;
    BinderCaller caller = BinderCaller(11_111, 99);

    bool runtime_permission(BinderCaller)
    {
        return true;
    }

    auto before_attach = authorize_caller(
        clients,
        caller,
        2_000,
        12_345,
        &runtime_permission);

    assert(before_attach.allowed);
    assert(
        before_attach.reason ==
        AuthorizationReason.runtime_permission_unattached);

    bool owns(AndroidUid, string)
    {
        return true;
    }

    bool denied(AndroidUid)
    {
        return false;
    }

    bool link(BinderHandle, ClientToken)
    {
        return true;
    }

    auto attached = attach_application(
        clients,
        caller,
        "example.denied",
        binder_handle(1),
        13,
        &owns,
        &denied,
        &link);

    assert(attached.ok);

    auto after_attach = authorize_caller(
        clients,
        caller,
        2_000,
        12_345,
        &runtime_permission);

    // This is the somewhat non-obvious upstream Shizuku rule.
    assert(!after_attach.allowed);
    assert(after_attach.error == AuthorizationError.permission_denied);
}

private class ServiceFake
{
    int read_count;
    TransactionFlags seen_flags;
    bool recycled;
    bool restored;
    bool throw_from_target;

    BinderHandle read_binder(ParcelHandle)
    {
        return binder_handle(20);
    }

    int read_int(ParcelHandle)
    {
        ++read_count;
        return read_count == 1 ? 73 : 9;
    }

    ParcelHandle obtain_parcel()
    {
        return parcel_handle(30);
    }

    bool append_remaining(ParcelHandle, ParcelHandle)
    {
        return true;
    }

    void recycle_parcel(ParcelHandle)
    {
        recycled = true;
    }

    ulong clear_calling_identity()
    {
        return 0x1234;
    }

    void restore_calling_identity(ulong identity)
    {
        assert(identity == 0x1234);
        restored = true;
    }

    bool binder_transact(
        BinderHandle,
        TransactionCode code,
        ParcelHandle,
        ParcelHandle,
        TransactionFlags flags)
    {
        assert(code == 73);
        seen_flags = flags;

        if (throw_from_target)
        {
            throw new Exception("target Binder threw");
        }

        return true;
    }
}

private ServiceOps service_ops(ServiceFake fake)
{
    ServiceOps ops;
    ops.read_binder = &fake.read_binder;
    ops.read_int = &fake.read_int;
    ops.obtain_parcel = &fake.obtain_parcel;
    ops.append_remaining = &fake.append_remaining;
    ops.recycle_parcel = &fake.recycle_parcel;
    ops.clear_calling_identity = &fake.clear_calling_identity;
    ops.restore_calling_identity = &fake.restore_calling_identity;
    ops.binder_transact = &fake.binder_transact;
    return ops;
}

private void add_allowed_client(
    ref ClientRegistry clients,
    BinderCaller caller,
    ApiVersion api_version)
{
    bool owns(AndroidUid, string)
    {
        return true;
    }

    bool allowed(AndroidUid)
    {
        return true;
    }

    bool link(BinderHandle, ClientToken)
    {
        return true;
    }

    const result = attach_application(
        clients,
        caller,
        "example.client",
        binder_handle(1),
        api_version,
        &owns,
        &allowed,
        &link);

    assert(result.ok);
}

unittest
{
    ClientRegistry clients;
    BinderCaller caller = BinderCaller(12_001, 101);
    add_allowed_client(clients, caller, 13);

    auto fake = new ServiceFake;
    auto result = transact_remote(
        clients,
        caller,
        2_000,
        50_000,
        null,
        parcel_handle(40),
        parcel_handle(41),
        3,
        service_ops(fake));

    assert(result.ok);
    assert(result.target_accepted);
    assert(fake.seen_flags == 9);
    assert(fake.restored);
    assert(fake.recycled);
}

unittest
{
    ClientRegistry clients;
    BinderCaller caller = BinderCaller(12_002, 102);
    add_allowed_client(clients, caller, 12);

    auto fake = new ServiceFake;
    auto result = transact_remote(
        clients,
        caller,
        2_000,
        50_000,
        null,
        parcel_handle(40),
        parcel_handle(41),
        3,
        service_ops(fake));

    assert(result.ok);
    assert(fake.seen_flags == 3);
    assert(fake.read_count == 1);
}

unittest
{
    ClientRegistry clients;
    BinderCaller caller = BinderCaller(12_003, 103);
    add_allowed_client(clients, caller, 13);

    auto fake = new ServiceFake;
    fake.throw_from_target = true;

    bool threw;
    try
    {
        transact_remote(
            clients,
            caller,
            2_000,
            50_000,
            null,
            parcel_handle(40),
            parcel_handle(41),
            3,
            service_ops(fake));
    }
    catch (Exception)
    {
        threw = true;
    }

    assert(threw);
    assert(fake.restored);
    assert(fake.recycled);
}

private class DeliveryFake
{
    int opened;
    int closed;
    int liveness_checks;
    int force_stops;
    int sleeps;
    int sends;

    bool temp_whitelist(string, int, uint milliseconds)
    {
        assert(milliseconds == 30_000);
        return true;
    }

    ProviderHandle open_external_provider(string provider_name, int)
    {
        assert(provider_name == "example.client.shizuku");
        ++opened;
        return ProviderHandle(cast(void*) (100 + opened));
    }

    bool provider_alive(ProviderHandle)
    {
        ++liveness_checks;
        return liveness_checks >= 2;
    }

    bool send_broker_binder(ProviderHandle, BinderHandle, string provider_name)
    {
        assert(provider_name == "example.client.shizuku");
        ++sends;
        return true;
    }

    void close_external_provider(string provider_name)
    {
        assert(provider_name == "example.client.shizuku");
        ++closed;
    }

    void force_stop_package(string package_name, int)
    {
        assert(package_name == "example.client");
        ++force_stops;
    }

    void sleep_milliseconds(uint milliseconds)
    {
        assert(milliseconds == 1_000);
        ++sleeps;
    }
}

private DeliveryOps delivery_ops(DeliveryFake fake)
{
    DeliveryOps ops;
    ops.temp_whitelist = &fake.temp_whitelist;
    ops.open_external_provider = &fake.open_external_provider;
    ops.provider_alive = &fake.provider_alive;
    ops.send_broker_binder = &fake.send_broker_binder;
    ops.close_external_provider = &fake.close_external_provider;
    ops.force_stop_package = &fake.force_stop_package;
    ops.sleep_milliseconds = &fake.sleep_milliseconds;
    return ops;
}

unittest
{
    auto fake = new DeliveryFake;

    const result = deliver_broker_binder(
        binder_handle(200),
        "example.client",
        0,
        delivery_ops(fake));

    assert(result == DeliveryResult.delivered);
    assert(fake.opened == 2);
    assert(fake.liveness_checks == 2);
    assert(fake.force_stops == 1);
    assert(fake.sleeps == 1);
    assert(fake.sends == 1);
    assert(fake.closed == 2);
}

void main()
{
}
