module crawlspace.shizuku.rish_client;

enum RishClientAction : ubyte
{
    run_shell,
    request_permission,
    deny_permission,
    reject_server
}

struct RishClientDecision
{
    RishClientAction action;
    int server_version;
}

RishClientDecision decide_rish_start(
    int server_version,
    bool permission_granted,
    bool should_show_rationale)
    nothrow @nogc
{
    if (server_version < 12)
    {
        return RishClientDecision(
            RishClientAction.reject_server,
            server_version);
    }

    if (permission_granted)
    {
        return RishClientDecision(
            RishClientAction.run_shell,
            server_version);
    }

    if (should_show_rationale)
    {
        return RishClientDecision(
            RishClientAction.deny_permission,
            server_version);
    }

    return RishClientDecision(
        RishClientAction.request_permission,
        server_version);
}

RishClientAction permission_result_action(
    bool granted)
    nothrow @nogc
{
    return granted
        ? RishClientAction.run_shell
        : RishClientAction.deny_permission;
}

enum ShellPackageError : ubyte
{
    none,
    application_id_required
}

struct ShellPackageSelection
{
    ShellPackageError error;
    string package_name;

    bool ok() const nothrow @nogc
    {
        return error == ShellPackageError.none;
    }
}

/*
 * ShizukuShellLoader uses the sole package for the caller UID when exactly one
 * exists. For shared UIDs, RISH_APPLICATION_ID must name the current terminal
 * package and the upstream placeholder "PKG" is rejected.
 */
ShellPackageSelection select_shell_package(
    string[] packages_for_uid,
    string rish_application_id)
{
    if (packages_for_uid.length == 1)
    {
        return ShellPackageSelection(
            ShellPackageError.none,
            packages_for_uid[0]);
    }

    if (rish_application_id.length == 0 ||
        rish_application_id == "PKG")
    {
        return ShellPackageSelection(
            ShellPackageError.application_id_required);
    }

    return ShellPackageSelection(
        ShellPackageError.none,
        rish_application_id);
}

enum BinderRequestPath : ubyte
{
    broadcast,
    android_8_activity_fallback,
    fail
}

/*
 * Only Android 8.0/8.1 with this exact framework failure falls back from
 * broadcastIntent to startActivityAsUser. Other failures propagate.
 */
BinderRequestPath binder_request_failure_path(
    int api_level,
    string exception_message)
{
    const android_o = 26;
    const android_o_mr1 = 27;

    if ((api_level == android_o ||
         api_level == android_o_mr1) &&
        exception_message ==
            "Calling application did not provide package name")
    {
        return BinderRequestPath.android_8_activity_fallback;
    }

    return BinderRequestPath.fail;
}
