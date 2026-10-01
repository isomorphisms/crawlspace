module crawlspace.shizuku.permission_request;

import crawlspace.shizuku.clients;
import crawlspace.shizuku.permission;
import crawlspace.shizuku.types;

enum PermissionRequestAction : ubyte
{
    server_self_noop,
    not_attached,
    already_granted,
    persistently_denied,
    show_confirmation
}

struct PermissionRequestDecision
{
    PermissionRequestAction action;
    ClientToken client;
    int request_code;
}

bool caller_is_server_self(
    BinderCaller caller,
    AndroidUid server_uid,
    AndroidPid server_pid)
    nothrow @nogc
{
    /*
     * requestPermission/checkSelfPermission use UID OR PID equality upstream.
     */
    return caller.uid == server_uid ||
        caller.pid == server_pid;
}

bool check_self_permission(
    ref ClientRegistry clients,
    BinderCaller caller,
    AndroidUid server_uid,
    AndroidPid server_pid)
{
    if (caller_is_server_self(
            caller,
            server_uid,
            server_pid))
    {
        return true;
    }

    auto record =
        clients.find_client(client_key(caller));

    return record !is null &&
        record.allowed;
}

PermissionRequestDecision request_permission_decision(
    ref ClientRegistry clients,
    ref ConfigStore config,
    BinderCaller caller,
    AndroidUid server_uid,
    AndroidPid server_pid,
    int request_code)
{
    PermissionRequestDecision result;
    result.request_code = request_code;

    if (caller_is_server_self(
            caller,
            server_uid,
            server_pid))
    {
        result.action =
            PermissionRequestAction.server_self_noop;
        return result;
    }

    auto record =
        clients.find_client(client_key(caller));

    if (record is null)
    {
        result.action =
            PermissionRequestAction.not_attached;
        return result;
    }

    result.client = record.token;

    if (record.allowed)
    {
        result.action =
            PermissionRequestAction.already_granted;
        return result;
    }

    auto entry = config.find(caller.uid);
    if (entry !is null && entry.denied)
    {
        result.action =
            PermissionRequestAction.persistently_denied;
        return result;
    }

    result.action =
        PermissionRequestAction.show_confirmation;
    return result;
}

enum PermissionRationaleResult : ubyte
{
    server_self_true,
    not_attached,
    show,
    do_not_show
}

PermissionRationaleResult permission_rationale(
    ref ClientRegistry clients,
    ref ConfigStore config,
    BinderCaller caller,
    AndroidUid server_uid,
    AndroidPid server_pid)
{
    /*
     * Upstream returns true for the server's own UID/PID.
     */
    if (caller_is_server_self(
            caller,
            server_uid,
            server_pid))
    {
        return PermissionRationaleResult.server_self_true;
    }

    auto record =
        clients.find_client(client_key(caller));

    if (record is null)
    {
        return PermissionRationaleResult.not_attached;
    }

    auto entry = config.find(caller.uid);
    return entry !is null && entry.denied
        ? PermissionRationaleResult.show
        : PermissionRationaleResult.do_not_show;
}

enum ConfirmationAction : ubyte
{
    no_application,
    dispatch_denied,
    start_manager_activity
}

struct PermissionConfirmationPlan
{
    ConfirmationAction action;
    int activity_user_id;
}

/*
 * ShizukuService.showPermissionConfirmation policy after Android lookups have
 * resolved whether the client app exists, manager exists in this user, and the
 * target user is a managed work profile.
 */
PermissionConfirmationPlan permission_confirmation_plan(
    int client_user_id,
    bool client_application_exists,
    bool manager_exists_in_user,
    bool is_work_profile)
    nothrow @nogc
{
    PermissionConfirmationPlan result;

    if (!client_application_exists)
    {
        result.action =
            ConfirmationAction.no_application;
        return result;
    }

    if (!manager_exists_in_user &&
        !is_work_profile)
    {
        result.action =
            ConfirmationAction.dispatch_denied;
        return result;
    }

    result.action =
        ConfirmationAction.start_manager_activity;

    /*
     * Managed profiles use the manager in user 0.
     */
    result.activity_user_id =
        is_work_profile
            ? 0
            : client_user_id;

    return result;
}
