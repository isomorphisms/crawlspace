module crawlspace.shizuku.user_service_apk;

import crawlspace.shizuku.user_service;

struct PackageInstallation
{
    int user_id;
    bool package_present;
    string source_dir;
}

enum UserServiceApkAction : ubyte
{
    remove_record,
    retarget_observer
}

struct UserServiceApkDecision
{
    UserServiceApkAction action;
    string new_source_dir;
}

UserServiceApkDecision user_service_apk_changed(
    PackageInstallation[] installations)
{
    foreach (installation; installations)
    {
        if (!installation.package_present ||
            installation.source_dir.length == 0)
        {
            continue;
        }

        UserServiceApkDecision result;
        result.action =
            UserServiceApkAction.retarget_observer;
        result.new_source_dir =
            installation.source_dir;
        return result;
    }

    UserServiceApkDecision result;
    result.action =
        UserServiceApkAction.remove_record;
    return result;
}

struct UserServiceApkWatch
{
    UserServiceIdentity service;
    string package_name;
    string source_dir;
}

struct UserServiceApkWatchRegistry
{
private:
    UserServiceApkWatch[] watches;

    size_t find_index(
        UserServiceIdentity service) const
    {
        foreach (i, watch; watches)
        {
            if (watch.service.generation ==
                    service.generation &&
                watch.service.token ==
                    service.token)
            {
                return i;
            }
        }

        return size_t.max;
    }

public:
    size_t length() const nothrow @nogc
    {
        return watches.length;
    }

    UserServiceApkWatch* find(
        UserServiceIdentity service)
    {
        auto i = find_index(service);
        return i == size_t.max
            ? null
            : &watches[i];
    }

    void record_created(
        UserServiceIdentity service,
        string package_name,
        string source_dir)
    {
        UserServiceApkWatch watch;
        watch.service = service;
        watch.package_name = package_name;
        watch.source_dir = source_dir;

        auto i = find_index(service);
        if (i == size_t.max)
        {
            watches ~= watch;
        }
        else
        {
            watches[i] = watch;
        }
    }

    bool record_removed(
        UserServiceIdentity service)
    {
        auto i = find_index(service);
        if (i == size_t.max)
        {
            return false;
        }

        for (size_t j = i; j + 1 < watches.length; ++j)
        {
            watches[j] = watches[j + 1];
        }

        watches.length = watches.length - 1;
        return true;
    }

    UserServiceApkDecision apk_changed(
        UserServiceIdentity service,
        PackageInstallation[] installations)
    {
        auto decision =
            user_service_apk_changed(installations);

        auto watch = find(service);

        if (decision.action ==
            UserServiceApkAction.retarget_observer)
        {
            if (watch !is null)
            {
                /*
                 * Upstream stops the old ApkChangedObserver and starts the
                 * same listener against the newly found sourceDir.
                 */
                watch.source_dir =
                    decision.new_source_dir;
            }
        }
        else
        {
            /*
             * Actual UserServiceRecord removal is performed by the manager.
             * Removing the watch models onUserServiceRecordRemoved.
             */
            record_removed(service);
        }

        return decision;
    }
}
