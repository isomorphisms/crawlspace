module crawlspace.shizuku.startup;

import crawlspace.shizuku.types;
import crawlspace.shizuku.user_service;

enum LaunchAuthority : ubyte
{
    adb_shell,
    root
}

enum StartupError : ubyte
{
    none,
    unsupported_uid,
    binder_blocked_by_selinux,
    existing_server_cannot_be_killed,
    manager_apk_not_found,
    manager_apk_unreadable,
    launch_failed
}

enum SelinuxBinderAccess : ubyte
{
    call,
    transfer
}

struct ProcessLaunch
{
    string executable;
    string class_path;
    string library_path;
    string working_directory;
    string process_name;
    string main_class;
    string[] vm_arguments;
    string[] arguments;
    bool detached;
}

struct StartupResult
{
    StartupError error;
    LaunchAuthority authority;
    AndroidPid pid;
    ProcessLaunch launch;

    bool ok() const nothrow @nogc
    {
        return error == StartupError.none;
    }
}

alias CurrentUid = AndroidUid delegate();
alias AndroidApiLevel = int delegate();
alias SwitchCgroupBestEffort = bool delegate();
alias SwitchMountNamespaceToInit = bool delegate();
alias CurrentSelinuxContext = string delegate();
alias SelinuxAllowsBinder = bool delegate(
    string source_context,
    string target_context,
    SelinuxBinderAccess access);
alias KillOldServer = bool delegate(string process_name);
alias FindManagerApk = string delegate(string package_name);
alias PathReadable = bool delegate(string path);
alias DeviceAbi = string delegate();
alias LaunchDetached = AndroidPid delegate(ProcessLaunch launch);

struct StartupOps
{
    CurrentUid current_uid;
    AndroidApiLevel android_api_level;
    SwitchCgroupBestEffort switch_cgroup_best_effort;
    SwitchMountNamespaceToInit switch_mount_namespace_to_init;
    CurrentSelinuxContext current_selinux_context;
    SelinuxAllowsBinder selinux_allows_binder;
    KillOldServer kill_old_server;
    FindManagerApk find_manager_apk;
    PathReadable path_readable;
    DeviceAbi device_abi;
    LaunchDetached launch_detached;
}

LaunchAuthority authority_for_uid(
    AndroidUid uid,
    out StartupError error)
{
    if (uid == 0)
    {
        error = StartupError.none;
        return LaunchAuthority.root;
    }

    if (uid == 2_000)
    {
        error = StartupError.none;
        return LaunchAuthority.adb_shell;
    }

    error = StartupError.unsupported_uid;
    return LaunchAuthority.adb_shell;
}

private string parent_directory(string path)
{
    if (path.length == 0)
    {
        return "";
    }

    size_t end = path.length;
    while (end > 1 && path[end - 1] == '/')
    {
        --end;
    }

    size_t slash = end;
    while (slash > 0 && path[slash - 1] != '/')
    {
        --slash;
    }

    if (slash == 0)
    {
        return ".";
    }

    if (slash == 1)
    {
        return "/";
    }

    return path[0 .. slash - 1];
}

string[] debug_vm_arguments(int api_level)
{
    string[] args;
    args ~= "-Xcompiler-option";
    args ~= "--debuggable";

    if (api_level >= 30)
    {
        args ~= "-XjdwpProvider:adbconnection";
        args ~= "-XjdwpOptions:suspend=n,server=y";
    }
    else if (api_level >= 28)
    {
        args ~= "-XjdwpProvider:internal";
        args ~= "-XjdwpOptions:transport=dt_android_adb,suspend=n,server=y";
    }
    else
    {
        args ~= "-agentlib:jdwp=transport=dt_android_adb,suspend=n,server=y";
    }

    return args;
}

ProcessLaunch build_server_launch(
    string apk_path,
    string abi,
    int api_level,
    bool debuggable = false)
{
    ProcessLaunch launch;
    launch.executable = "/system/bin/app_process";
    launch.class_path = apk_path;
    launch.library_path =
        parent_directory(apk_path) ~ "/lib/" ~ abi;
    launch.working_directory = "/";
    launch.process_name = "shizuku_server";
    launch.main_class = "rikka.shizuku.server.ShizukuService";
    launch.detached = true;

    launch.vm_arguments ~=
        "-Djava.class.path=" ~ apk_path;
    launch.vm_arguments ~=
        "-Dshizuku.library.path=" ~ launch.library_path;

    if (debuggable)
    {
        launch.vm_arguments ~= debug_vm_arguments(api_level);
        launch.arguments ~= "--debug";
    }

    return launch;
}

ProcessLaunch build_user_service_launch(
    StartRequest request,
    string manager_apk_path,
    bool app_process32_available,
    int api_level)
{
    ProcessLaunch launch;
    launch.executable =
        request.use_32_bit_app_process && app_process32_available
            ? "/system/bin/app_process32"
            : "/system/bin/app_process";
    launch.class_path = manager_apk_path;
    launch.working_directory = "/system/bin";
    launch.process_name =
        request.package_name ~ ":" ~ request.process_name_suffix;
    launch.main_class = "moe.shizuku.starter.ServiceStarter";
    launch.detached = true;

    if (request.debuggable)
    {
        launch.vm_arguments ~= debug_vm_arguments(api_level);
    }

    launch.arguments ~= "--token=" ~ request.identity.token;
    launch.arguments ~= "--package=" ~ request.package_name;
    launch.arguments ~= "--class=" ~ request.class_name;
    launch.arguments ~= "--uid=" ~ request.calling_uid.stringof;

    if (request.debuggable)
    {
        launch.arguments ~= "--debug-name=" ~ launch.process_name;
    }

    return launch;
}

StartupResult start_broker(
    string supplied_apk_path,
    bool debuggable,
    StartupOps ops)
{
    auto uid = ops.current_uid();

    StartupError authority_error;
    auto authority = authority_for_uid(uid, authority_error);
    if (authority_error != StartupError.none)
    {
        StartupResult failed;
        failed.error = authority_error;
        return failed;
    }

    auto api_level = ops.android_api_level();

    if (authority == LaunchAuthority.root)
    {
        /*
         * Upstream treats cgroup and mount-namespace switching as preparation,
         * not as fatal gates.
         */
        if (ops.switch_cgroup_best_effort !is null)
        {
            ops.switch_cgroup_best_effort();
        }

        if (api_level >= 29 &&
            ops.switch_mount_namespace_to_init !is null)
        {
            ops.switch_mount_namespace_to_init();
        }

        if (ops.current_selinux_context !is null)
        {
            auto context = ops.current_selinux_context();

            /*
             * starter.cpp performs the Binder call/transfer preflight only
             * when getcon succeeds. Empty here represents no available
             * context and preserves that behavior.
             */
            if (context.length != 0)
            {
                auto source = "u:r:untrusted_app:s0";

                if (!ops.selinux_allows_binder(
                        source,
                        context,
                        SelinuxBinderAccess.call) ||
                    !ops.selinux_allows_binder(
                        source,
                        context,
                        SelinuxBinderAccess.transfer))
                {
                    StartupResult failed;
                    failed.error =
                        StartupError.binder_blocked_by_selinux;
                    failed.authority = authority;
                    return failed;
                }
            }
        }
    }

    if (!ops.kill_old_server("shizuku_server"))
    {
        StartupResult failed;
        failed.error =
            StartupError.existing_server_cannot_be_killed;
        failed.authority = authority;
        return failed;
    }

    auto apk_path = supplied_apk_path;

    /*
     * A non-empty --apk path is authoritative in upstream starter.cpp.
     * If it is unreadable, Shizuku does not silently fall back to pm path.
     */
    if (apk_path.length == 0)
    {
        apk_path =
            ops.find_manager_apk("moe.shizuku.privileged.api");
    }

    if (apk_path.length == 0)
    {
        StartupResult failed;
        failed.error = StartupError.manager_apk_not_found;
        failed.authority = authority;
        return failed;
    }

    if (!ops.path_readable(apk_path))
    {
        StartupResult failed;
        failed.error = StartupError.manager_apk_unreadable;
        failed.authority = authority;
        return failed;
    }

    auto launch = build_server_launch(
        apk_path,
        ops.device_abi(),
        api_level,
        debuggable);

    auto pid = ops.launch_detached(launch);
    if (pid <= 0)
    {
        StartupResult failed;
        failed.error = StartupError.launch_failed;
        failed.authority = authority;
        failed.launch = launch;
        return failed;
    }

    StartupResult result;
    result.error = StartupError.none;
    result.authority = authority;
    result.pid = pid;
    result.launch = launch;
    return result;
}
