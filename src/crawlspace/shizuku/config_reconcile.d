module crawlspace.shizuku.config_reconcile;

import crawlspace.shizuku.permission;
import crawlspace.shizuku.types;

alias CurrentPackagesForUid =
    string[] delegate(AndroidUid uid);

struct InstalledPermissionState
{
    AndroidUid uid;
    string package_name;
    bool check_succeeded;
    bool permission_granted;
}

struct ConfigReconcileResult
{
    bool changed;
    size_t removed_entries;
    size_t deduplicated_entries;
    size_t imported_permission_packages;
}

private bool contains(
    const string[] values,
    string value)
{
    foreach (candidate; values)
    {
        if (candidate == value)
        {
            return true;
        }
    }
    return false;
}

private string[] deduplicate(
    const string[] values)
{
    string[] result;

    foreach (value; values)
    {
        if (!contains(result, value))
        {
            result ~= value;
        }
    }

    return result;
}

private bool arrays_equal(
    const string[] a,
    const string[] b)
{
    if (a.length != b.length)
    {
        return false;
    }

    foreach (i, value; a)
    {
        if (value != b[i])
        {
            return false;
        }
    }

    return true;
}

ConfigReconcileResult reconcile_config(
    ref ConfigStore config,
    CurrentPackagesForUid current_packages_for_uid,
    InstalledPermissionState[] installed_permission_packages)
{
    ConfigReconcileResult result;

    /*
     * First pass: validate persisted UID/package associations.
     */
    foreach (entry; config.snapshot())
    {
        auto current_packages =
            current_packages_for_uid is null
                ? null
                : current_packages_for_uid(entry.uid);

        if (current_packages.length == 0)
        {
            if (config.remove(entry.uid))
            {
                result.changed = true;
                ++result.removed_entries;
            }
            continue;
        }

        bool packages_changed = true;

        foreach (stored_package; entry.packages)
        {
            if (contains(
                    current_packages,
                    stored_package))
            {
                packages_changed = false;
                break;
            }
        }

        auto unique_packages =
            deduplicate(entry.packages);

        if (!arrays_equal(
                unique_packages,
                entry.packages))
        {
            /*
             * Upstream mutates the list and logs the shrink but does not set
             * its local 'changed' flag solely for this deduplication.
             */
            config.replace_packages(
                entry.uid,
                unique_packages);
            ++result.deduplicated_entries;
        }

        /*
         * An empty persisted package list leaves packages_changed == true,
         * so the entry is removed even when the UID still exists.
         */
        if (packages_changed)
        {
            if (config.remove(entry.uid))
            {
                result.changed = true;
                ++result.removed_entries;
            }
        }
    }

    /*
     * Second pass: import current Android runtime-permission state for every
     * installed package that requested the Shizuku API permission.
     *
     * ShizukuConfigManager sets changed=true for every successful permission
     * check, even if updateLocked returns early because the flags were already
     * identical.
     */
    foreach (state; installed_permission_packages)
    {
        if (!state.check_succeeded)
        {
            continue;
        }

        config.update(
            state.uid,
            [state.package_name],
            mask_permission,
            state.permission_granted
                ? flag_allowed
                : 0);

        result.changed = true;
        ++result.imported_permission_packages;
    }

    return result;
}

enum ConfigWriteScheduleAction : ubyte
{
    post,
    keep_existing,
    remove_then_post
}

/*
 * ShizukuConfigManager.scheduleWriteLocked:
 * - API >= 29: if the write callback is already queued, leave it alone;
 * - API < 29: remove the old callback then post a fresh delayed callback.
 */
ConfigWriteScheduleAction config_write_schedule_action(
    int android_api_level,
    bool write_callback_pending)
    nothrow @nogc
{
    if (android_api_level >= 29)
    {
        return write_callback_pending
            ? ConfigWriteScheduleAction.keep_existing
            : ConfigWriteScheduleAction.post;
    }

    return write_callback_pending
        ? ConfigWriteScheduleAction.remove_then_post
        : ConfigWriteScheduleAction.post;
}

enum uint shizuku_config_write_delay_ms = 10_000;
enum string shizuku_config_path =
    "/data/user_de/0/com.android.shell/shizuku.json";
