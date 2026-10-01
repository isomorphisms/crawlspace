module crawlspace.shizuku.applications;

import crawlspace.shizuku.permission;
import crawlspace.shizuku.types;

enum string shizuku_manager_package =
    "moe.shizuku.privileged.api";
enum string shizuku_api_permission =
    "moe.shizuku.manager.permission.API_V23";
enum string shizuku_v3_metadata =
    "moe.shizuku.client.V3_SUPPORT";

struct InstalledApplication
{
    string package_name;
    AndroidUid uid;
    int user_id;
    bool has_application_info;
    bool declares_shizuku_permission;
    bool supports_v3;
}

private bool contains_package(
    const string[] packages,
    string package_name)
{
    foreach (candidate; packages)
    {
        if (candidate == package_name)
        {
            return true;
        }
    }
    return false;
}

bool application_visible_to_manager(
    ref ConfigStore config,
    InstalledApplication application)
{
    if (application.package_name == shizuku_manager_package)
    {
        return false;
    }

    if (!application.has_application_info)
    {
        return false;
    }

    int flags;
    auto entry = config.find(application.uid);

    if (entry !is null)
    {
        /*
         * A config entry can be shared by several packages under one UID. When
         * it carries a package list, pinned Shizuku hides sibling packages not
         * present in that list.
         */
        if (entry.packages.length != 0 &&
            !contains_package(
                entry.packages,
                application.package_name))
        {
            return false;
        }

        flags = entry.flags & mask_permission;
    }

    if (flags != 0)
    {
        return true;
    }

    return application.supports_v3 &&
        application.declares_shizuku_permission;
}

InstalledApplication[] visible_applications(
    ref ConfigStore config,
    InstalledApplication[] installed,
    int requested_user_id)
{
    InstalledApplication[] result;

    foreach (application; installed)
    {
        if (requested_user_id != -1 &&
            application.user_id != requested_user_id)
        {
            continue;
        }

        if (application_visible_to_manager(
                config,
                application))
        {
            result ~= application;
        }
    }

    return result;
}

InstalledApplication[] binder_delivery_targets(
    InstalledApplication[] installed,
    int requested_user_id)
{
    InstalledApplication[] result;

    foreach (application; installed)
    {
        if (application.user_id != requested_user_id)
        {
            continue;
        }

        /*
         * sendBinderToClient does not require V3 metadata or current config;
         * declaring the runtime Shizuku permission is enough to receive the
         * broker Binder.
         */
        if (application.declares_shizuku_permission)
        {
            result ~= application;
        }
    }

    return result;
}
