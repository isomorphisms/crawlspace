module crawlspace.shizuku.transaction_router;

import crawlspace.shizuku.rish;

enum string shizuku_binder_descriptor =
    "moe.shizuku.server.IShizukuService";

enum int shizuku_transaction_remote = 1;
enum int shizuku_transaction_legacy_attach_application = 14;
enum int shizuku_transaction_get_applications = 10_001;
enum int shizuku_rish_transaction_start = 30_000;

enum int legacy_attach_api_version = -1;
enum int legacy_attach_reported_server_version = 12;

enum ShizukuTransactionRoute : ubyte
{
    generated_aidl_or_unknown,
    get_applications,
    remote_transact,
    legacy_attach_application,
    rish_create_host,
    rish_set_window_size,
    rish_get_exit_code
}

ShizukuTransactionRoute classify_shizuku_transaction(
    int binder_code)
    nothrow @nogc
{
    /*
     * ShizukuService.onTransact checks its private manager transaction before
     * delegating to Service.onTransact.
     */
    if (binder_code == shizuku_transaction_get_applications)
    {
        return ShizukuTransactionRoute.get_applications;
    }

    if (binder_code == shizuku_transaction_remote)
    {
        return ShizukuTransactionRoute.remote_transact;
    }

    /*
     * API <= 12 used transaction 14 for the old attachApplication wire shape.
     * Modern attachApplication is generated AIDL (currently transaction 18)
     * and is intentionally left to the generated-AIDL path.
     */
    if (binder_code == shizuku_transaction_legacy_attach_application)
    {
        return ShizukuTransactionRoute.legacy_attach_application;
    }

    RishConfig rish;
    rish.interface_token = shizuku_binder_descriptor;
    rish.transaction_code_start = shizuku_rish_transaction_start;

    final switch (classify_rish_transaction(rish, binder_code))
    {
        case RishDispatchKind.create_host:
            return ShizukuTransactionRoute.rish_create_host;

        case RishDispatchKind.set_window_size:
            return ShizukuTransactionRoute.rish_set_window_size;

        case RishDispatchKind.get_exit_code:
            return ShizukuTransactionRoute.rish_get_exit_code;

        case RishDispatchKind.not_rish:
            return ShizukuTransactionRoute.generated_aidl_or_unknown;
    }
}

bool transaction_enforces_shizuku_interface(
    ShizukuTransactionRoute route)
    nothrow @nogc
{
    final switch (route)
    {
        case ShizukuTransactionRoute.get_applications:
        case ShizukuTransactionRoute.remote_transact:
        case ShizukuTransactionRoute.legacy_attach_application:
            return true;

        case ShizukuTransactionRoute.rish_create_host:
        case ShizukuTransactionRoute.rish_set_window_size:
        case ShizukuTransactionRoute.rish_get_exit_code:
            /*
             * Rish enforces the same configured interface token internally
             * after its own permission check.
             */
            return true;

        case ShizukuTransactionRoute.generated_aidl_or_unknown:
            return false;
    }
}

int attached_api_version_for_wire(
    ShizukuTransactionRoute route,
    int modern_api_version)
    nothrow @nogc
{
    return route ==
        ShizukuTransactionRoute.legacy_attach_application
        ? legacy_attach_api_version
        : modern_api_version;
}

int server_version_for_attached_client(
    int client_api_version,
    int current_server_version)
    nothrow @nogc
{
    /*
     * Shizuku API 12.2.0 had a v13-aware Binder wrapper while still sending
     * the old attachApplication format. Reporting version 12 for api == -1
     * forces that client to keep using the old outer-flags wire format.
     */
    return client_api_version == legacy_attach_api_version
        ? legacy_attach_reported_server_version
        : current_server_version;
}
