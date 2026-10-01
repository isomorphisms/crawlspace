module crawlspace.shizuku.server_lifecycle;

import crawlspace.shizuku.types;

enum int manager_app_not_found_exit = 50;
enum uint system_service_retry_delay_ms = 1_000;

enum string manager_application_id =
    "moe.shizuku.privileged.api";

enum RequiredSystemService : ubyte
{
    package_manager,
    activity_manager,
    user_manager,
    app_ops
}

string required_system_service_name(
    RequiredSystemService service)
{
    final switch (service)
    {
        case RequiredSystemService.package_manager:
            return "package";

        case RequiredSystemService.activity_manager:
            return "activity";

        case RequiredSystemService.user_manager:
            return "user";

        case RequiredSystemService.app_ops:
            return "appops";
    }
}

RequiredSystemService[] required_system_services()
{
    return [
        RequiredSystemService.package_manager,
        RequiredSystemService.activity_manager,
        RequiredSystemService.user_manager,
        RequiredSystemService.app_ops
    ];
}

struct ManagerApplication
{
    bool present;
    AndroidUid uid;
    string source_dir;
}

enum ServerInitAction : ubyte
{
    wait_for_system_service,
    exit_manager_missing,
    initialize_managers,
    register_manager_apk_observer,
    register_binder_sender,
    post_initial_binder_delivery,
    ready
}

struct ServerInitStep
{
    ServerInitAction action;
    string service_name;
    uint retry_delay_ms;
    int exit_code;
}

ServerInitStep wait_step(
    RequiredSystemService service)
{
    ServerInitStep step;
    step.action =
        ServerInitAction.wait_for_system_service;
    step.service_name =
        required_system_service_name(service);
    step.retry_delay_ms =
        system_service_retry_delay_ms;
    return step;
}

ServerInitStep manager_application_step(
    ManagerApplication manager)
{
    ServerInitStep step;

    if (!manager.present)
    {
        step.action =
            ServerInitAction.exit_manager_missing;
        step.exit_code =
            manager_app_not_found_exit;
        return step;
    }

    step.action =
        ServerInitAction.initialize_managers;
    return step;
}

/*
 * Once ShizukuService has observed all required system services and found the
 * manager APK, constructor-side work occurs in this order.
 */
ServerInitAction[] post_manager_initialization_order()
{
    return [
        ServerInitAction.initialize_managers,
        ServerInitAction.register_manager_apk_observer,
        ServerInitAction.register_binder_sender,
        ServerInitAction.post_initial_binder_delivery,
        ServerInitAction.ready
    ];
}

enum ManagerApkChangeAction : ubyte
{
    keep_running,
    exit_manager_missing
}

/*
 * The ApkChangedObserver does not restart or rediscover a replacement image.
 * It checks whether the manager still exists in user 0 and exits with 50 only
 * when it has disappeared.
 */
ManagerApkChangeAction manager_apk_changed(
    bool manager_application_still_present)
    nothrow @nogc
{
    return manager_application_still_present
        ? ManagerApkChangeAction.keep_running
        : ManagerApkChangeAction.exit_manager_missing;
}

enum InitialBinderDelivery : ubyte
{
    clients,
    manager
}

InitialBinderDelivery[] initial_binder_delivery_order()
{
    /*
     * ShizukuService posts one main-thread runnable that sends to ordinary
     * clients first, then the manager.
     */
    return [
        InitialBinderDelivery.clients,
        InitialBinderDelivery.manager
    ];
}

struct ServerLifecycleState
{
    bool managers_initialized;
    bool manager_apk_observer_registered;
    bool binder_sender_registered;
    bool initial_delivery_posted;
    bool ready;
}

void apply_init_action(
    ref ServerLifecycleState state,
    ServerInitAction action)
{
    final switch (action)
    {
        case ServerInitAction.wait_for_system_service:
        case ServerInitAction.exit_manager_missing:
            return;

        case ServerInitAction.initialize_managers:
            state.managers_initialized = true;
            return;

        case ServerInitAction.register_manager_apk_observer:
            state.manager_apk_observer_registered = true;
            return;

        case ServerInitAction.register_binder_sender:
            state.binder_sender_registered = true;
            return;

        case ServerInitAction.post_initial_binder_delivery:
            state.initial_delivery_posted = true;
            return;

        case ServerInitAction.ready:
            state.ready =
                state.managers_initialized &&
                state.manager_apk_observer_registered &&
                state.binder_sender_registered &&
                state.initial_delivery_posted;
            return;
    }
}
