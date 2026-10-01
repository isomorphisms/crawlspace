module crawlspace.shizuku.permission;

import crawlspace.shizuku.clients;
import crawlspace.shizuku.types;

enum int flag_allowed = 1 << 1;
enum int flag_denied = 1 << 2;
enum int mask_permission = flag_allowed | flag_denied;

struct ConfigEntry
{
    AndroidUid uid;
    int flags;
    string[] packages;

    bool allowed() const nothrow @nogc
    {
        return (flags & flag_allowed) != 0;
    }

    bool denied() const nothrow @nogc
    {
        return (flags & flag_denied) != 0;
    }
}

private void append_unique(ref string[] values, string value)
{
    foreach (existing; values)
    {
        if (existing == value)
        {
            return;
        }
    }
    values ~= value;
}

struct ConfigStore
{
private:
    ConfigEntry[] entries;

public:
    ConfigEntry* find(AndroidUid uid)
    {
        foreach (ref entry; entries)
        {
            if (entry.uid == uid)
            {
                return &entry;
            }
        }
        return null;
    }

    const(ConfigEntry)* find(AndroidUid uid) const
    {
        foreach (ref const entry; entries)
        {
            if (entry.uid == uid)
            {
                return &entry;
            }
        }
        return null;
    }

    bool update(
        AndroidUid uid,
        string[] packages,
        int mask,
        int values)
    {
        auto entry = find(uid);

        if (entry is null)
        {
            ConfigEntry fresh;
            fresh.uid = uid;
            fresh.flags = mask & values;
            foreach (package_name; packages)
            {
                append_unique(fresh.packages, package_name);
            }
            entries ~= fresh;
            return true;
        }

        auto new_value =
            (entry.flags & ~mask) |
            (mask & values);

        /*
         * This matches ShizukuConfigManager.updateLocked exactly: when the
         * flags do not change, it returns before merging package names.
         */
        if (new_value == entry.flags)
        {
            return false;
        }

        entry.flags = new_value;
        foreach (package_name; packages)
        {
            append_unique(entry.packages, package_name);
        }
        return true;
    }

    bool remove(AndroidUid uid)
    {
        foreach (i, entry; entries)
        {
            if (entry.uid != uid)
            {
                continue;
            }

            for (size_t j = i; j + 1 < entries.length; ++j)
            {
                entries[j] = entries[j + 1];
            }
            entries.length = entries.length - 1;
            return true;
        }
        return false;
    }

    ConfigEntry[] snapshot() const
    {
        ConfigEntry[] result;
        foreach (entry; entries)
        {
            ConfigEntry copy;
            copy.uid = entry.uid;
            copy.flags = entry.flags;
            copy.packages = entry.packages.dup;
            result ~= copy;
        }
        return result;
    }

    bool replace_packages(
        AndroidUid uid,
        string[] packages)
    {
        auto entry = find(uid);
        if (entry is null)
        {
            return false;
        }

        entry.packages = packages.dup;
        return true;
    }

    size_t length() const nothrow @nogc
    {
        return entries.length;
    }
}

alias PackagesForUid = string[] delegate(AndroidUid uid);
alias PackageRequestsPermission = bool delegate(
    string package_name,
    int user_id);
alias RuntimePermissionGranted = bool delegate(AndroidUid uid);
alias GrantRuntimePermission = void delegate(
    string package_name,
    int user_id);
alias RevokeRuntimePermission = void delegate(
    string package_name,
    int user_id);
alias ForceStopPackageForPermission = void delegate(
    string package_name,
    int user_id);
alias RemoveUserServicesForPackage = void delegate(
    string package_name);
alias DispatchPermissionResult = void delegate(
    BinderHandle callback,
    int request_code,
    bool allowed);

struct PermissionOps
{
    PackagesForUid packages_for_uid;
    PackageRequestsPermission package_requests_permission;
    RuntimePermissionGranted runtime_permission_granted;
    GrantRuntimePermission grant_runtime_permission;
    RevokeRuntimePermission revoke_runtime_permission;
    ForceStopPackageForPermission force_stop_package;
    RemoveUserServicesForPackage remove_user_services_for_package;
    DispatchPermissionResult dispatch_permission_result;
}

bool initial_client_allowed(
    ref ConfigStore config,
    AndroidUid uid)
{
    auto entry = config.find(uid);
    return entry !is null && entry.allowed;
}

int get_flags_for_uid(
    ref ConfigStore config,
    AndroidUid uid,
    int mask,
    bool allow_runtime_permission,
    PermissionOps ops)
{
    auto entry = config.find(uid);
    if (entry !is null)
    {
        return entry.flags & mask;
    }

    if (!allow_runtime_permission ||
        (mask & mask_permission) == 0 ||
        ops.packages_for_uid is null ||
        ops.package_requests_permission is null ||
        ops.runtime_permission_granted is null)
    {
        return 0;
    }

    auto user_id = android_user_id(uid);

    foreach (package_name; ops.packages_for_uid(uid))
    {
        if (!ops.package_requests_permission(package_name, user_id))
        {
            continue;
        }

        if (ops.runtime_permission_granted(uid))
        {
            return flag_allowed;
        }
    }

    return 0;
}

bool dispatch_permission_confirmation_result(
    ref ClientRegistry clients,
    ref ConfigStore config,
    AndroidUid request_uid,
    AndroidPid request_pid,
    int request_code,
    bool allowed,
    bool onetime,
    PermissionOps ops)
{
    string[] packages;

    foreach (record; clients.find_clients(request_uid))
    {
        packages ~= record.package_name;
        record.allowed = allowed;

        if (record.token.key.pid == request_pid &&
            ops.dispatch_permission_result !is null)
        {
            ops.dispatch_permission_result(
                record.callback,
                request_code,
                allowed);
        }
    }

    bool config_changed;

    if (!onetime)
    {
        config_changed = config.update(
            request_uid,
            packages,
            mask_permission,
            allowed ? flag_allowed : flag_denied);
    }

    /*
     * Pinned Shizuku grants the runtime permission after a persistent
     * approval. The denial path here does not revoke it; manager-driven
     * updateFlagsForUid handles revocation separately.
     */
    if (!onetime &&
        allowed &&
        ops.packages_for_uid !is null &&
        ops.package_requests_permission !is null &&
        ops.grant_runtime_permission !is null)
    {
        auto user_id = android_user_id(request_uid);

        foreach (package_name; ops.packages_for_uid(request_uid))
        {
            if (ops.package_requests_permission(package_name, user_id))
            {
                ops.grant_runtime_permission(package_name, user_id);
            }
        }
    }

    return config_changed;
}

bool update_flags_for_uid(
    ref ClientRegistry clients,
    ref ConfigStore config,
    AndroidUid uid,
    int mask,
    int value,
    PermissionOps ops)
{
    if ((mask & mask_permission) != 0)
    {
        auto allowed = (value & flag_allowed) != 0;

        foreach (record; clients.find_clients(uid))
        {
            record.allowed = allowed;

            if (!allowed)
            {
                auto user_id = android_user_id(record.token.key.uid);

                if (ops.force_stop_package !is null)
                {
                    ops.force_stop_package(
                        record.package_name,
                        user_id);
                }

                if (ops.remove_user_services_for_package !is null)
                {
                    ops.remove_user_services_for_package(
                        record.package_name);
                }
            }
        }

        if (ops.packages_for_uid !is null &&
            ops.package_requests_permission !is null)
        {
            auto user_id = android_user_id(uid);

            foreach (package_name; ops.packages_for_uid(uid))
            {
                if (!ops.package_requests_permission(
                        package_name,
                        user_id))
                {
                    continue;
                }

                if (allowed)
                {
                    if (ops.grant_runtime_permission !is null)
                    {
                        ops.grant_runtime_permission(
                            package_name,
                            user_id);
                    }
                }
                else
                {
                    if (ops.revoke_runtime_permission !is null)
                    {
                        ops.revoke_runtime_permission(
                            package_name,
                            user_id);
                    }
                }
            }
        }
    }

    return config.update(uid, null, mask, value);
}
