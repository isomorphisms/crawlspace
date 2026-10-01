module shizuku_d_logic_test;

import crawlspace.shizuku.android_boundary;
import crawlspace.shizuku.applications;
import crawlspace.shizuku.binder_sender;
import crawlspace.shizuku.clients;
import crawlspace.shizuku.delivery;
import crawlspace.shizuku.permission;
import crawlspace.shizuku.rish;
import crawlspace.shizuku.rish_client;
import crawlspace.shizuku.service;
import crawlspace.shizuku.startup;
import crawlspace.shizuku.transaction_router;
import crawlspace.shizuku.types;
import crawlspace.shizuku.user_service;

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

private ConnectionHandle connection_handle(size_t value)
{
    return ConnectionHandle(cast(void*) value);
}

private class UserServiceFake
{
    int token_counter;
    int pings;
    int links;
    int unlinks;
    int destroys;
    int connected;
    int starts;
    StartRequest last_start;

    bool package_owned_by_caller(string package_name, int app_id, int user_id)
    {
        return package_name == "example.client" &&
            app_id == 12_345 &&
            user_id == 1;
    }

    bool ping_service_binder(BinderHandle binder)
    {
        ++pings;
        return binder.valid;
    }

    string token_factory()
    {
        ++token_counter;
        return token_counter == 1 ? "token-1" : "token-2";
    }

    bool link_service_death(BinderHandle, UserServiceIdentity)
    {
        ++links;
        return true;
    }

    void unlink_service_death(BinderHandle, UserServiceIdentity)
    {
        ++unlinks;
    }

    void destroy_service_binder(BinderHandle)
    {
        ++destroys;
    }

    void notify_connected(ConnectionHandle, BinderHandle)
    {
        ++connected;
    }

    void schedule_start(StartRequest request)
    {
        ++starts;
        last_start = request;
    }
}

private UserServiceOps user_service_ops(UserServiceFake fake)
{
    UserServiceOps ops;
    ops.package_owned_by_caller = &fake.package_owned_by_caller;
    ops.ping_service_binder = &fake.ping_service_binder;
    ops.token_factory = &fake.token_factory;
    ops.link_service_death = &fake.link_service_death;
    ops.unlink_service_death = &fake.unlink_service_death;
    ops.destroy_service_binder = &fake.destroy_service_binder;
    ops.notify_connected = &fake.notify_connected;
    ops.schedule_start = &fake.schedule_start;
    return ops;
}

private UserServiceOptions service_options(
    int version_code = 7,
    bool daemon = true,
    bool no_create = false)
{
    UserServiceOptions options;
    options.package_name = "example.client";
    options.class_name = "example.Service";
    options.version_code = version_code;
    options.daemon = daemon;
    options.no_create = no_create;
    return options;
}

unittest
{
    UserServiceRegistry registry;
    auto fake = new UserServiceFake;
    auto ops = user_service_ops(fake);
    auto options = service_options();

    auto created = add_user_service(
        registry,
        connection_handle(1),
        options,
        13,
        112_345,
        ops);

    assert(created.ok);
    assert(created.wire_result == 0);
    assert(created.start_requested);
    assert(fake.starts == 1);
    assert(fake.last_start.identity == created.identity);
    assert(registry.length == 1);

    auto record = registry.find_by_key(user_service_key(options));
    assert(record !is null);
    assert(record.starting);
    assert(record.identity.token == "token-1");

    auto attach_error = attach_user_service(
        registry,
        binder_handle(300),
        record.identity.token,
        ops);

    assert(attach_error == UserServiceError.none);
    assert(fake.links == 1);
    assert(fake.connected == 1);

    options.no_create = true;
    auto existing = add_user_service(
        registry,
        connection_handle(2),
        options,
        13,
        112_345,
        ops);

    assert(existing.ok);
    assert(existing.wire_result == 7);
    assert(!existing.start_requested);
    assert(fake.connected == 3);
}

unittest
{
    UserServiceRegistry registry;
    auto fake = new UserServiceFake;
    auto ops = user_service_ops(fake);

    auto options = service_options();
    options.no_create = true;

    auto modern = add_user_service(
        registry,
        connection_handle(1),
        options,
        13,
        112_345,
        ops);
    assert(modern.wire_result == -1);

    auto legacy = add_user_service(
        registry,
        connection_handle(1),
        options,
        12,
        112_345,
        ops);
    assert(legacy.wire_result == 1);
}

unittest
{
    UserServiceRegistry registry;
    auto fake = new UserServiceFake;
    auto ops = user_service_ops(fake);

    auto options = service_options(7);
    auto first = add_user_service(
        registry,
        connection_handle(1),
        options,
        13,
        112_345,
        ops);
    assert(first.start_requested);

    auto record = registry.find_by_key(user_service_key(options));
    assert(record !is null);
    assert(
        attach_user_service(
            registry,
            binder_handle(400),
            record.identity.token,
            ops) == UserServiceError.none);

    options.version_code = 8;
    auto replacement = add_user_service(
        registry,
        connection_handle(2),
        options,
        13,
        112_345,
        ops);

    assert(replacement.start_requested);
    assert(replacement.identity.generation != first.identity.generation);
    assert(fake.unlinks == 1);
    assert(fake.destroys == 1);
    assert(fake.starts == 2);
    assert(registry.length == 1);
}

unittest
{
    UserServiceRegistry registry;
    auto fake = new UserServiceFake;
    auto ops = user_service_ops(fake);

    auto options = service_options(7, false);
    auto created = add_user_service(
        registry,
        connection_handle(1),
        options,
        13,
        112_345,
        ops);

    auto record = registry.find_by_key(user_service_key(options));
    assert(record !is null);

    assert(
        attach_user_service(
            registry,
            binder_handle(500),
            record.identity.token,
            ops) == UserServiceError.none);

    assert(user_service_connection_died(
        registry,
        created.identity,
        connection_handle(1),
        ops));

    assert(registry.length == 0);
    assert(fake.destroys == 1);
}

private bool contains_string(string[] values, string expected)
{
    foreach (value; values)
    {
        if (value == expected)
        {
            return true;
        }
    }
    return false;
}

private class StartupFake
{
    AndroidUid uid = 2_000;
    int api_level = 34;
    int cgroups;
    int mount_switches;
    int selinux_checks;
    int kills;
    int finds;
    int launches;
    bool allow_call = true;
    bool allow_transfer = true;
    bool kill_ok = true;
    bool readable = true;
    string context = "";
    string manager_apk = "/data/app/manager/base.apk";
    string abi = "arm";
    AndroidPid launch_pid = 777;
    ProcessLaunch last_launch;

    AndroidUid current_uid()
    {
        return uid;
    }

    int android_api_level()
    {
        return api_level;
    }

    bool switch_cgroup_best_effort()
    {
        ++cgroups;
        return true;
    }

    bool switch_mount_namespace_to_init()
    {
        ++mount_switches;
        return true;
    }

    string current_selinux_context()
    {
        return context;
    }

    bool selinux_allows_binder(
        string source,
        string target,
        SelinuxBinderAccess access)
    {
        assert(source == "u:r:untrusted_app:s0");
        assert(target == context);
        ++selinux_checks;
        return access == SelinuxBinderAccess.call
            ? allow_call
            : allow_transfer;
    }

    bool kill_old_server(string process_name)
    {
        assert(process_name == "shizuku_server");
        ++kills;
        return kill_ok;
    }

    string find_manager_apk(string package_name)
    {
        assert(package_name == "moe.shizuku.privileged.api");
        ++finds;
        return manager_apk;
    }

    bool path_readable(string)
    {
        return readable;
    }

    string device_abi()
    {
        return abi;
    }

    AndroidPid launch_detached(ProcessLaunch launch)
    {
        ++launches;
        last_launch = launch;
        return launch_pid;
    }
}

private StartupOps startup_ops(StartupFake fake)
{
    StartupOps ops;
    ops.current_uid = &fake.current_uid;
    ops.android_api_level = &fake.android_api_level;
    ops.switch_cgroup_best_effort = &fake.switch_cgroup_best_effort;
    ops.switch_mount_namespace_to_init =
        &fake.switch_mount_namespace_to_init;
    ops.current_selinux_context = &fake.current_selinux_context;
    ops.selinux_allows_binder = &fake.selinux_allows_binder;
    ops.kill_old_server = &fake.kill_old_server;
    ops.find_manager_apk = &fake.find_manager_apk;
    ops.path_readable = &fake.path_readable;
    ops.device_abi = &fake.device_abi;
    ops.launch_detached = &fake.launch_detached;
    return ops;
}

unittest
{
    auto fake = new StartupFake;
    auto result = start_broker("", false, startup_ops(fake));

    assert(result.ok);
    assert(result.authority == LaunchAuthority.adb_shell);
    assert(fake.cgroups == 0);
    assert(fake.mount_switches == 0);
    assert(fake.selinux_checks == 0);
    assert(fake.kills == 1);
    assert(fake.finds == 1);
    assert(fake.launches == 1);
    assert(
        fake.last_launch.executable ==
        "/system/bin/app_process");
    assert(
        fake.last_launch.library_path ==
        "/data/app/manager/lib/arm");
    assert(
        fake.last_launch.main_class ==
        "rikka.shizuku.server.ShizukuService");
}

unittest
{
    auto fake = new StartupFake;
    fake.uid = 0;
    fake.context = "u:r:su:s0";
    fake.allow_transfer = false;

    auto result = start_broker("", false, startup_ops(fake));

    assert(!result.ok);
    assert(
        result.error ==
        StartupError.binder_blocked_by_selinux);
    assert(fake.cgroups == 1);
    assert(fake.mount_switches == 1);
    assert(fake.selinux_checks == 2);
    assert(fake.kills == 0);
    assert(fake.launches == 0);
}

unittest
{
    auto fake = new StartupFake;
    fake.readable = false;

    auto result = start_broker(
        "/explicit/unreadable.apk",
        false,
        startup_ops(fake));

    assert(!result.ok);
    assert(result.error == StartupError.manager_apk_unreadable);
    assert(fake.finds == 0);
    assert(fake.launches == 0);
}

unittest
{
    StartRequest request;
    request.identity = UserServiceIdentity(9, "service-token");
    request.package_name = "example.client";
    request.class_name = "example.Service";
    request.process_name_suffix = "worker";
    request.calling_uid = 112_345;
    request.use_32_bit_app_process = true;
    request.debuggable = true;

    auto launch = build_user_service_launch(
        request,
        "/data/app/manager/base.apk",
        true,
        34);

    assert(launch.executable == "/system/bin/app_process32");
    assert(launch.process_name == "example.client:worker");
    assert(
        launch.main_class ==
        "moe.shizuku.starter.ServiceStarter");
    assert(contains_string(
        launch.arguments,
        "--token=service-token"));
    assert(contains_string(
        launch.arguments,
        "--package=example.client"));
    assert(contains_string(
        launch.arguments,
        "--class=example.Service"));
    assert(contains_string(
        launch.arguments,
        "--uid=112345"));
    assert(contains_string(
        launch.arguments,
        "--debug-name=example.client:worker"));
    assert(contains_string(
        launch.vm_arguments,
        "-XjdwpProvider:adbconnection"));
}

private class PermissionFake
{
    bool runtime_granted;
    int grants;
    int revokes;
    int force_stops;
    int service_removals;
    int dispatches;
    int last_request_code;
    bool last_allowed;

    string[] packages_for_uid(AndroidUid)
    {
        return ["example.one", "example.two"];
    }

    bool package_requests_permission(string package_name, int user_id)
    {
        assert(user_id == 1);
        return package_name == "example.one" ||
            package_name == "example.two";
    }

    bool runtime_permission_granted(AndroidUid)
    {
        return runtime_granted;
    }

    void grant_runtime_permission(string, int)
    {
        ++grants;
    }

    void revoke_runtime_permission(string, int)
    {
        ++revokes;
    }

    void force_stop_package(string, int)
    {
        ++force_stops;
    }

    void remove_user_services_for_package(string)
    {
        ++service_removals;
    }

    void dispatch_permission_result(
        BinderHandle,
        int request_code,
        bool allowed)
    {
        ++dispatches;
        last_request_code = request_code;
        last_allowed = allowed;
    }
}

private PermissionOps permission_ops(PermissionFake fake)
{
    PermissionOps ops;
    ops.packages_for_uid = &fake.packages_for_uid;
    ops.package_requests_permission =
        &fake.package_requests_permission;
    ops.runtime_permission_granted =
        &fake.runtime_permission_granted;
    ops.grant_runtime_permission =
        &fake.grant_runtime_permission;
    ops.revoke_runtime_permission =
        &fake.revoke_runtime_permission;
    ops.force_stop_package = &fake.force_stop_package;
    ops.remove_user_services_for_package =
        &fake.remove_user_services_for_package;
    ops.dispatch_permission_result =
        &fake.dispatch_permission_result;
    return ops;
}

private void add_permission_client(
    ref ClientRegistry clients,
    AndroidUid uid,
    AndroidPid pid,
    string package_name,
    bool initially_allowed)
{
    bool owns(AndroidUid, string)
    {
        return true;
    }

    bool initial(AndroidUid)
    {
        return initially_allowed;
    }

    bool link(BinderHandle, ClientToken)
    {
        return true;
    }

    auto result = attach_application(
        clients,
        BinderCaller(uid, pid),
        package_name,
        binder_handle(cast(size_t) pid),
        13,
        &owns,
        &initial,
        &link);

    assert(result.ok);
}

unittest
{
    ConfigStore config;

    assert(config.update(
        112_345,
        ["example.one"],
        mask_permission,
        flag_allowed));

    // Exact upstream behavior: unchanged flags return before package merge.
    assert(!config.update(
        112_345,
        ["example.two"],
        mask_permission,
        flag_allowed));

    auto entry = config.find(112_345);
    assert(entry !is null);
    assert(entry.packages.length == 1);
    assert(entry.packages[0] == "example.one");
}

unittest
{
    ClientRegistry clients;
    ConfigStore config;
    auto fake = new PermissionFake;
    auto ops = permission_ops(fake);

    add_permission_client(
        clients,
        112_345,
        11,
        "example.one",
        false);
    add_permission_client(
        clients,
        112_345,
        12,
        "example.two",
        false);

    auto changed = dispatch_permission_confirmation_result(
        clients,
        config,
        112_345,
        12,
        55,
        true,
        false,
        ops);

    assert(changed);
    assert(fake.dispatches == 1);
    assert(fake.last_request_code == 55);
    assert(fake.last_allowed);
    assert(fake.grants == 2);
    assert(fake.revokes == 0);

    foreach (record; clients.find_clients(112_345))
    {
        assert(record.allowed);
    }

    auto entry = config.find(112_345);
    assert(entry !is null);
    assert(entry.allowed);
    assert(entry.packages.length == 2);
}

unittest
{
    ClientRegistry clients;
    ConfigStore config;
    auto fake = new PermissionFake;
    auto ops = permission_ops(fake);

    add_permission_client(
        clients,
        112_345,
        21,
        "example.one",
        false);

    auto changed = dispatch_permission_confirmation_result(
        clients,
        config,
        112_345,
        21,
        7,
        true,
        true,
        ops);

    assert(!changed);
    assert(config.length == 0);
    assert(fake.grants == 0);
    assert(fake.dispatches == 1);
    assert(clients.find_clients(112_345)[0].allowed);
}

unittest
{
    ClientRegistry clients;
    ConfigStore config;
    auto fake = new PermissionFake;
    auto ops = permission_ops(fake);

    add_permission_client(
        clients,
        112_345,
        31,
        "example.one",
        true);
    add_permission_client(
        clients,
        112_345,
        32,
        "example.two",
        true);

    config.update(
        112_345,
        ["example.one", "example.two"],
        mask_permission,
        flag_allowed);

    auto changed = update_flags_for_uid(
        clients,
        config,
        112_345,
        mask_permission,
        flag_denied,
        ops);

    assert(changed);
    assert(fake.force_stops == 2);
    assert(fake.service_removals == 2);
    assert(fake.revokes == 2);

    foreach (record; clients.find_clients(112_345))
    {
        assert(!record.allowed);
    }

    auto entry = config.find(112_345);
    assert(entry !is null);
    assert(entry.denied);
    assert(!entry.allowed);
}

unittest
{
    ConfigStore config;
    auto fake = new PermissionFake;
    fake.runtime_granted = true;
    auto ops = permission_ops(fake);

    auto flags = get_flags_for_uid(
        config,
        112_345,
        mask_permission,
        true,
        ops);

    assert(flags == flag_allowed);
}

private class RishFake
{
    int starts;
    int sizes;
    int exit_requests;
    int destroys;
    ulong last_size;
    RishHostSpec last_spec;

    RishHostHandle start_host(
        AndroidPid owner_pid,
        RishHostSpec spec,
        ulong generation)
    {
        ++starts;
        last_spec = spec;

        RishHostHandle handle;
        handle.generation = generation;
        handle.owner_pid = owner_pid;
        handle.child_pid = 7_000 + starts;
        handle.ptmx = 100 + starts;
        return handle;
    }

    void set_window_size(
        RishHostHandle,
        ulong packed_size)
    {
        ++sizes;
        last_size = packed_size;
    }

    int get_exit_code(RishHostHandle host)
    {
        ++exit_requests;
        return host.child_pid == 7_001 ? 17 : 23;
    }

    void destroy_host(RishHostHandle)
    {
        ++destroys;
    }
}

private RishHostOps rish_ops(RishFake fake)
{
    RishHostOps ops;
    ops.start_host = &fake.start_host;
    ops.set_window_size = &fake.set_window_size;
    ops.get_exit_code = &fake.get_exit_code;
    ops.destroy_host = &fake.destroy_host;
    return ops;
}

private class RishPermissionFake
{
    bool allow(string)
    {
        return true;
    }
}

private EnforceRishPermission allow_rish_permission()
{
    auto permission = new RishPermissionFake;
    return &permission.allow;
}

unittest
{
    assert(!rish_preserve_environment(
        false,
        ["PATH=/termux/bin"]));

    assert(rish_preserve_environment(
        false,
        [
            "PATH=/termux/bin",
            "RISH_PRESERVE_ENV=1"
        ]));

    assert(rish_preserve_environment(
        true,
        ["PATH=/termux/bin"]));

    assert(!rish_preserve_environment(
        true,
        [
            "RISH_PRESERVE_ENV=0",
            "RISH_PRESERVE_ENV=1"
        ]));

    assert(rish_preserve_environment(
        false,
        [
            "RISH_PRESERVE_ENV=1",
            "RISH_PRESERVE_ENV=0"
        ]));
}

unittest
{
    RishHostRegistry hosts;
    auto fake = new RishFake;
    auto ops = rish_ops(fake);

    RishHostSpec request;
    request.arguments = ["-c", "id"];
    request.environment = [
        "PATH=/data/data/com.termux/files/usr/bin"
    ];
    request.directory = "/data/data/com.termux/files/home";
    request.tty = atty_out | atty_err;
    request.stdin_fd = FileDescriptorHandle(3);
    request.stdout_fd = FileDescriptorHandle(4);
    request.stderr_fd = FileDescriptorHandle(5);

    auto created = dispatch_rish_create_host(
        hosts,
        901,
        false,
        true,
        0,
        request,
        allow_rish_permission(),
        ops);

    assert(created.handled);
    assert(created.host_created);
    assert(fake.starts == 1);
    assert(hosts.length == 1);
    assert(!fake.last_spec.environment_preserved);
    assert(fake.last_spec.environment.length == 0);

    // stderr is on the PTY when ATTY_ERR is set.
    assert(!fake.last_spec.stderr_fd.valid);

    auto size = dispatch_rish_set_window_size(
        hosts,
        901,
        0x1122334455667788UL,
        allow_rish_permission(),
        ops);

    assert(size.host_found);
    assert(fake.sizes == 1);
    assert(fake.last_size == 0x1122334455667788UL);

    auto exit = dispatch_rish_get_exit_code(
        hosts,
        901,
        allow_rish_permission(),
        ops);

    assert(exit.host_found);
    assert(exit.exit_code == 17);
    assert(fake.exit_requests == 1);
}

unittest
{
    RishHostRegistry hosts;
    auto fake = new RishFake;
    auto ops = rish_ops(fake);

    RishHostSpec request;
    request.arguments = ["-c", "printf x"];
    request.environment = ["RISH_PRESERVE_ENV=1"];

    auto oneway = dispatch_rish_create_host(
        hosts,
        902,
        false,
        true,
        binder_flag_oneway,
        request,
        allow_rish_permission(),
        ops);

    assert(oneway.handled);
    assert(!oneway.host_created);
    assert(fake.starts == 0);
    assert(hosts.length == 0);

    auto no_reply = dispatch_rish_create_host(
        hosts,
        902,
        false,
        false,
        0,
        request,
        allow_rish_permission(),
        ops);

    assert(no_reply.handled);
    assert(!no_reply.host_created);
    assert(fake.starts == 0);
}

unittest
{
    RishHostRegistry hosts;
    auto fake = new RishFake;
    auto ops = rish_ops(fake);

    RishHostSpec first;
    first.arguments = ["-c", "first"];

    auto a = dispatch_rish_create_host(
        hosts,
        903,
        true,
        true,
        0,
        first,
        allow_rish_permission(),
        ops);
    assert(a.host_created);

    RishHostSpec second;
    second.arguments = ["-c", "second"];

    auto b = dispatch_rish_create_host(
        hosts,
        903,
        true,
        true,
        0,
        second,
        allow_rish_permission(),
        ops);
    assert(b.host_created);

    assert(fake.starts == 2);
    assert(hosts.length == 1);
    assert(hosts.find(903).spec.arguments[1] == "second");

    // Upstream replaces HOSTS[pid] without explicitly destroying the old host.
    assert(fake.destroys == 0);

    auto exit = dispatch_rish_get_exit_code(
        hosts,
        903,
        allow_rish_permission(),
        ops);
    assert(exit.exit_code == 23);
}

unittest
{
    RishConfig config;
    config.interface_token = "moe.shizuku.server.IShizukuService";
    config.transaction_code_start = 30_000;

    assert(
        classify_rish_transaction(config, 30_000) ==
        RishDispatchKind.create_host);
    assert(
        classify_rish_transaction(config, 30_001) ==
        RishDispatchKind.set_window_size);
    assert(
        classify_rish_transaction(config, 30_002) ==
        RishDispatchKind.get_exit_code);
    assert(
        classify_rish_transaction(config, 29_999) ==
        RishDispatchKind.not_rish);
}

unittest
{
    auto too_old = decide_rish_start(11, true, false);
    assert(too_old.action == RishClientAction.reject_server);

    auto granted = decide_rish_start(12, true, false);
    assert(granted.action == RishClientAction.run_shell);

    auto rationale = decide_rish_start(12, false, true);
    assert(rationale.action == RishClientAction.deny_permission);

    auto request = decide_rish_start(12, false, false);
    assert(request.action == RishClientAction.request_permission);

    assert(
        permission_result_action(true) ==
        RishClientAction.run_shell);
    assert(
        permission_result_action(false) ==
        RishClientAction.deny_permission);
}

unittest
{
    auto one = select_shell_package(
        ["com.termux"],
        "");
    assert(one.ok);
    assert(one.package_name == "com.termux");

    auto shared_missing = select_shell_package(
        ["one", "two"],
        "PKG");
    assert(!shared_missing.ok);
    assert(
        shared_missing.error ==
        ShellPackageError.application_id_required);

    auto shared_selected = select_shell_package(
        ["one", "two"],
        "com.termux");
    assert(shared_selected.ok);
    assert(shared_selected.package_name == "com.termux");
}

unittest
{
    assert(
        binder_request_failure_path(
            26,
            "Calling application did not provide package name") ==
        BinderRequestPath.android_8_activity_fallback);

    assert(
        binder_request_failure_path(
            27,
            "Calling application did not provide package name") ==
        BinderRequestPath.android_8_activity_fallback);

    assert(
        binder_request_failure_path(
            28,
            "Calling application did not provide package name") ==
        BinderRequestPath.fail);

    assert(
        binder_request_failure_path(
            26,
            "some other failure") ==
        BinderRequestPath.fail);
}

unittest
{
    assert(
        classify_shizuku_transaction(10_001) ==
        ShizukuTransactionRoute.get_applications);
    assert(
        classify_shizuku_transaction(1) ==
        ShizukuTransactionRoute.remote_transact);
    assert(
        classify_shizuku_transaction(14) ==
        ShizukuTransactionRoute.legacy_attach_application);
    assert(
        classify_shizuku_transaction(30_000) ==
        ShizukuTransactionRoute.rish_create_host);
    assert(
        classify_shizuku_transaction(30_001) ==
        ShizukuTransactionRoute.rish_set_window_size);
    assert(
        classify_shizuku_transaction(30_002) ==
        ShizukuTransactionRoute.rish_get_exit_code);

    // Modern generated-AIDL attachApplication remains on the AIDL path.
    assert(
        classify_shizuku_transaction(18) ==
        ShizukuTransactionRoute.generated_aidl_or_unknown);
}

unittest
{
    assert(
        attached_api_version_for_wire(
            ShizukuTransactionRoute.legacy_attach_application,
            13) == -1);

    assert(
        attached_api_version_for_wire(
            ShizukuTransactionRoute.generated_aidl_or_unknown,
            13) == 13);

    assert(server_version_for_attached_client(-1, 13) == 12);
    assert(server_version_for_attached_client(13, 13) == 13);
}

private InstalledApplication installed_application(
    string package_name,
    AndroidUid uid,
    int user_id,
    bool permission,
    bool v3)
{
    InstalledApplication app;
    app.package_name = package_name;
    app.uid = uid;
    app.user_id = user_id;
    app.has_application_info = true;
    app.declares_shizuku_permission = permission;
    app.supports_v3 = v3;
    return app;
}

unittest
{
    ConfigStore config;

    auto v3 = installed_application(
        "example.v3",
        112_345,
        1,
        true,
        true);

    assert(application_visible_to_manager(config, v3));

    auto old = installed_application(
        "example.old",
        112_346,
        1,
        true,
        false);

    assert(!application_visible_to_manager(config, old));

    config.update(
        112_346,
        ["example.old"],
        mask_permission,
        flag_denied);

    assert(application_visible_to_manager(config, old));
}

unittest
{
    ConfigStore config;
    config.update(
        112_400,
        ["example.allowed"],
        mask_permission,
        flag_allowed);

    auto allowed = installed_application(
        "example.allowed",
        112_400,
        1,
        false,
        false);

    auto sibling = installed_application(
        "example.sibling",
        112_400,
        1,
        true,
        true);

    assert(application_visible_to_manager(config, allowed));
    assert(!application_visible_to_manager(config, sibling));
}

unittest
{
    ConfigStore config;

    auto manager = installed_application(
        shizuku_manager_package,
        100_000,
        1,
        true,
        true);

    auto user_one = installed_application(
        "example.one",
        112_500,
        1,
        true,
        true);

    auto user_two = installed_application(
        "example.two",
        212_500,
        2,
        true,
        true);

    auto visible = visible_applications(
        config,
        [manager, user_one, user_two],
        -1);

    assert(visible.length == 2);

    auto one_only = visible_applications(
        config,
        [manager, user_one, user_two],
        1);

    assert(one_only.length == 1);
    assert(one_only[0].package_name == "example.one");
}

unittest
{
    auto permission_only = installed_application(
        "example.permission-only",
        112_600,
        1,
        true,
        false);

    auto no_permission = installed_application(
        "example.no-permission",
        112_601,
        1,
        false,
        true);

    auto targets = binder_delivery_targets(
        [permission_only, no_permission],
        1);

    assert(targets.length == 1);
    assert(
        targets[0].package_name ==
        "example.permission-only");
}

private class AndroidBoundaryFake
{
    AndroidUid uid = 2_000;
    AndroidPid pid = 444;
    int position = 7;
    int size = 19;
    int append_start;
    int append_size;
    int deletes;
    int clears;
    int restores;
    bool transacted;

    AndroidUid calling_uid()
    {
        return uid;
    }

    AndroidPid calling_pid()
    {
        return pid;
    }

    bool read_strong_binder(
        ParcelHandle,
        out BinderHandle binder)
    {
        binder = binder_handle(600);
        return true;
    }

    bool read_int32(
        ParcelHandle,
        out int value)
    {
        value = 91;
        return true;
    }

    ParcelHandle create_parcel()
    {
        return parcel_handle(700);
    }

    void delete_parcel(ParcelHandle)
    {
        ++deletes;
    }

    int parcel_position(ParcelHandle)
    {
        return position;
    }

    int parcel_size(ParcelHandle)
    {
        return size;
    }

    bool append_parcel(
        ParcelHandle,
        ParcelHandle,
        int start,
        int count)
    {
        append_start = start;
        append_size = count;
        return true;
    }

    bool transact(
        BinderHandle,
        TransactionCode code,
        ParcelHandle,
        ParcelHandle,
        TransactionFlags flags)
    {
        assert(code == 91);
        assert(flags == 5);
        transacted = true;
        return true;
    }

    ulong clear_identity()
    {
        ++clears;
        return 0x55AA;
    }

    void restore_identity(ulong token)
    {
        assert(token == 0x55AA);
        ++restores;
    }
}

private StableNdkCallerOps stable_ndk_caller_ops(AndroidBoundaryFake fake)
{
    StableNdkCallerOps ops;
    ops.calling_uid = &fake.calling_uid;
    ops.calling_pid = &fake.calling_pid;
    return ops;
}

private TransparentBinderBridge transparent_bridge(AndroidBoundaryFake fake)
{
    TransparentBinderBridge ops;
    ops.read_strong_binder = &fake.read_strong_binder;
    ops.read_int32 = &fake.read_int32;
    ops.create_parcel = &fake.create_parcel;
    ops.delete_parcel = &fake.delete_parcel;
    ops.parcel_position = &fake.parcel_position;
    ops.parcel_size = &fake.parcel_size;
    ops.append_parcel = &fake.append_parcel;
    ops.transact = &fake.transact;
    return ops;
}

private BinderIdentityBridge identity_bridge(AndroidBoundaryFake fake)
{
    BinderIdentityBridge bridge;
    bridge.clear_calling_identity = &fake.clear_identity;
    bridge.restore_calling_identity = &fake.restore_identity;
    return bridge;
}

unittest
{
    TransparentBinderBridge incomplete;
    BinderIdentityBridge identity;

    auto result = build_android_service_adapter(
        incomplete,
        identity);

    assert(!result.ready);
    assert(
        result.error ==
        AndroidBoundaryError.incomplete_transparent_bridge);
}

unittest
{
    auto fake = new AndroidBoundaryFake;
    auto bridge = transparent_bridge(fake);
    BinderIdentityBridge missing_identity;

    auto result = build_android_service_adapter(
        bridge,
        missing_identity);

    assert(!result.ready);
    assert(
        result.error ==
        AndroidBoundaryError.missing_identity_bridge);
}

unittest
{
    auto fake = new AndroidBoundaryFake;
    auto adapter = build_android_service_adapter(
        transparent_bridge(fake),
        identity_bridge(fake));

    assert(adapter.ready);

    auto caller = binder_caller(stable_ndk_caller_ops(fake));
    assert(caller.uid == 2_000);
    assert(caller.pid == 444);

    ClientRegistry clients;
    BinderCaller remote_caller = BinderCaller(2_000, 444);

    auto result = transact_remote(
        clients,
        remote_caller,
        2_000,
        50_000,
        null,
        parcel_handle(800),
        parcel_handle(801),
        5,
        adapter.service_ops);

    assert(result.ok);
    assert(result.target_accepted);
    assert(fake.append_start == 7);
    assert(fake.append_size == 12);
    assert(fake.clears == 1);
    assert(fake.restores == 1);
    assert(fake.deletes == 1);
    assert(fake.transacted);
}

private class BinderSenderPermissionFake
{
    bool granted;
    int checks;
    AndroidUid last_uid;
    AndroidPid last_pid;

    bool manager_permission_granted(
        AndroidUid uid,
        AndroidPid pid)
    {
        ++checks;
        last_uid = uid;
        last_pid = pid;
        return granted;
    }
}

unittest
{
    BinderSenderState state;

    assert(state.foreground_activities_changed(10, true));
    assert(!state.foreground_activities_changed(10, true));
    assert(!state.foreground_activities_changed(11, false));

    state.process_died(10);
    assert(!state.has_pid(10));
    assert(state.process_state_changed(10));
    assert(state.has_pid(10));

    assert(state.uid_active(112_345));
    assert(!state.uid_cached_changed(112_345, false));
    state.uid_gone(112_345);
    assert(!state.has_uid(112_345));

    // An unseen idle UID still triggers upstream uidStarts().
    assert(state.uid_idle(112_345));
    assert(state.has_uid(112_345));
}

unittest
{
    auto api25 = uid_observer_registration(25);
    assert(!api25.enabled);

    auto api26 = uid_observer_registration(26);
    assert(api26.enabled);
    assert(api26.observe_gone);
    assert(api26.observe_idle);
    assert(api26.observe_active);
    assert(!api26.observe_cached);

    auto api27 = uid_observer_registration(27);
    assert(api27.observe_cached);
}

unittest
{
    auto fake = new BinderSenderPermissionFake;

    BinderSenderPackage manager;
    manager.package_name = "managerish";
    manager.declares_manager_permission = true;
    manager.declares_client_permission = true;

    BinderSenderPackage client;
    client.package_name = "client";
    client.declares_client_permission = true;

    auto denied_manager_then_client = select_binder_delivery(
        112_345,
        77,
        [manager, client],
        &fake.manager_permission_granted);

    // Denied manager branch does not fall through within the same package,
    // but iteration continues to later packages.
    assert(
        denied_manager_then_client.kind ==
        BinderDeliveryKind.client);
    assert(
        denied_manager_then_client.package_name ==
        "client");
    assert(fake.checks == 1);
    assert(fake.last_uid == 112_345);
    assert(fake.last_pid == 77);

    fake.granted = true;
    auto manager_result = select_binder_delivery(
        112_345,
        -1,
        [manager, client],
        &fake.manager_permission_granted);

    assert(
        manager_result.kind ==
        BinderDeliveryKind.manager);
    assert(manager_result.package_name == "managerish");
    assert(manager_result.user_id == 1);
    assert(fake.last_pid == -1);
}

unittest
{
    auto fake = new BinderSenderPermissionFake;

    BinderSenderPackage both;
    both.package_name = "both";
    both.declares_manager_permission = true;
    both.declares_client_permission = true;

    auto result = select_binder_delivery(
        112_345,
        88,
        [both],
        &fake.manager_permission_granted);

    assert(result.kind == BinderDeliveryKind.none);
}

void main()
{
}
