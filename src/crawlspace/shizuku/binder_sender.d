module crawlspace.shizuku.binder_sender;

import crawlspace.shizuku.types;

enum string shizuku_manager_permission =
    "moe.shizuku.manager.permission.MANAGER";
enum string shizuku_client_permission =
    "moe.shizuku.manager.permission.API_V23";

struct BinderSenderPackage
{
    string package_name;
    bool declares_manager_permission;
    bool declares_client_permission;
}

enum BinderDeliveryKind : ubyte
{
    none,
    manager,
    client
}

struct BinderDeliveryDecision
{
    BinderDeliveryKind kind;
    string package_name;
    int user_id;
}

alias ManagerPermissionGranted =
    bool delegate(AndroidUid uid, AndroidPid pid);

BinderDeliveryDecision select_binder_delivery(
    AndroidUid uid,
    AndroidPid pid,
    BinderSenderPackage[] packages,
    ManagerPermissionGranted manager_permission_granted)
{
    BinderDeliveryDecision none;
    none.kind = BinderDeliveryKind.none;
    none.user_id = android_user_id(uid);

    foreach (package_info; packages)
    {
        /*
         * This is deliberately if/else-if, matching BinderSender.java.
         * A package declaring the manager permission does not fall through to
         * the ordinary API branch when manager permission is denied.
         */
        if (package_info.declares_manager_permission)
        {
            bool granted =
                manager_permission_granted !is null &&
                manager_permission_granted(uid, pid);

            if (granted)
            {
                BinderDeliveryDecision result;
                result.kind = BinderDeliveryKind.manager;
                result.package_name = package_info.package_name;
                result.user_id = android_user_id(uid);
                return result;
            }
        }
        else if (package_info.declares_client_permission)
        {
            BinderDeliveryDecision result;
            result.kind = BinderDeliveryKind.client;
            result.package_name = package_info.package_name;
            result.user_id = android_user_id(uid);
            return result;
        }
    }

    return none;
}

struct BinderSenderState
{
private:
    AndroidPid[] seen_pids;
    AndroidUid[] seen_uids;

    static bool contains_pid(
        const AndroidPid[] values,
        AndroidPid pid)
        nothrow @nogc
    {
        foreach (value; values)
        {
            if (value == pid)
            {
                return true;
            }
        }
        return false;
    }

    static bool contains_uid(
        const AndroidUid[] values,
        AndroidUid uid)
        nothrow @nogc
    {
        foreach (value; values)
        {
            if (value == uid)
            {
                return true;
            }
        }
        return false;
    }

    static void remove_pid(
        ref AndroidPid[] values,
        AndroidPid pid)
    {
        foreach (i, value; values)
        {
            if (value != pid)
            {
                continue;
            }

            for (size_t j = i; j + 1 < values.length; ++j)
            {
                values[j] = values[j + 1];
            }
            values.length = values.length - 1;
            return;
        }
    }

    static void remove_uid(
        ref AndroidUid[] values,
        AndroidUid uid)
    {
        foreach (i, value; values)
        {
            if (value != uid)
            {
                continue;
            }

            for (size_t j = i; j + 1 < values.length; ++j)
            {
                values[j] = values[j + 1];
            }
            values.length = values.length - 1;
            return;
        }
    }

public:
    bool foreground_activities_changed(
        AndroidPid pid,
        bool foreground_activities)
    {
        if (!foreground_activities ||
            contains_pid(seen_pids, pid))
        {
            return false;
        }

        seen_pids ~= pid;
        return true;
    }

    bool process_state_changed(AndroidPid pid)
    {
        if (contains_pid(seen_pids, pid))
        {
            return false;
        }

        seen_pids ~= pid;
        return true;
    }

    void process_died(AndroidPid pid)
    {
        remove_pid(seen_pids, pid);
    }

    bool uid_active(AndroidUid uid)
    {
        return uid_starts(uid);
    }

    bool uid_cached_changed(
        AndroidUid uid,
        bool cached)
    {
        return !cached && uid_starts(uid);
    }

    /*
     * Upstream calls uidStarts from onUidIdle as well. That looks surprising
     * but is intentional here: if the UID has not previously been observed,
     * an idle callback can still trigger the one-time Binder delivery.
     */
    bool uid_idle(AndroidUid uid)
    {
        return uid_starts(uid);
    }

    void uid_gone(AndroidUid uid)
    {
        remove_uid(seen_uids, uid);
    }

    bool uid_starts(AndroidUid uid)
    {
        if (contains_uid(seen_uids, uid))
        {
            return false;
        }

        seen_uids ~= uid;
        return true;
    }

    bool has_pid(AndroidPid pid) const nothrow @nogc
    {
        return contains_pid(seen_pids, pid);
    }

    bool has_uid(AndroidUid uid) const nothrow @nogc
    {
        return contains_uid(seen_uids, uid);
    }
}

struct UidObserverRegistration
{
    bool enabled;
    bool observe_gone;
    bool observe_idle;
    bool observe_active;
    bool observe_cached;
}

UidObserverRegistration uid_observer_registration(
    int android_api_level)
    nothrow @nogc
{
    UidObserverRegistration plan;

    if (android_api_level < 26)
    {
        return plan;
    }

    plan.enabled = true;
    plan.observe_gone = true;
    plan.observe_idle = true;
    plan.observe_active = true;
    plan.observe_cached = android_api_level >= 27;
    return plan;
}
