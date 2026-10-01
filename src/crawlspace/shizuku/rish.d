module crawlspace.shizuku.rish;

import crawlspace.shizuku.types;

enum ubyte atty_in = 1;
enum ubyte atty_out = 1 << 1;
enum ubyte atty_err = 1 << 2;

enum int rish_transaction_create_host = 0;
enum int rish_transaction_set_window_size = 1;
enum int rish_transaction_get_exit_code = 2;
enum int binder_flag_oneway = 0x01;

struct FileDescriptorHandle
{
    int fd = -1;

    bool valid() const nothrow @nogc
    {
        return fd >= 0;
    }
}

struct RishConfig
{
    string interface_token;
    int transaction_code_start;

    int transaction_code(int local_code) const nothrow @nogc
    {
        return transaction_code_start + local_code;
    }
}

struct RishHostSpec
{
    string[] arguments;
    string[] environment;
    bool environment_preserved;
    string directory;
    ubyte tty;
    FileDescriptorHandle stdin_fd;
    FileDescriptorHandle stdout_fd;
    FileDescriptorHandle stderr_fd;
}

struct RishHostHandle
{
    ulong generation;
    AndroidPid owner_pid;
    AndroidPid child_pid;
    int ptmx = -1;

    bool valid() const nothrow @nogc
    {
        return generation != 0;
    }
}

struct RishHostRecord
{
    RishHostHandle handle;
    RishHostSpec spec;
}

alias StartRishHost = RishHostHandle delegate(
    AndroidPid owner_pid,
    RishHostSpec spec,
    ulong generation);
alias SetRishWindowSize = void delegate(
    RishHostHandle host,
    ulong packed_size);
alias GetRishExitCode = int delegate(RishHostHandle host);
alias DestroyRishHost = void delegate(RishHostHandle host);

struct RishHostOps
{
    StartRishHost start_host;
    SetRishWindowSize set_window_size;
    GetRishExitCode get_exit_code;
    DestroyRishHost destroy_host;
}

bool rish_preserve_environment(
    bool server_is_root,
    string[] environment)
{
    bool preserve = server_is_root;

    foreach (entry; environment)
    {
        if (entry == "RISH_PRESERVE_ENV=1")
        {
            preserve = true;
            break;
        }

        if (entry == "RISH_PRESERVE_ENV=0")
        {
            preserve = false;
            break;
        }
    }

    return preserve;
}

struct RishHostRegistry
{
private:
    RishHostRecord[] records;
    ulong next_generation = 1;

    size_t find_index(AndroidPid owner_pid) const nothrow @nogc
    {
        foreach (i, record; records)
        {
            if (record.handle.owner_pid == owner_pid)
            {
                return i;
            }
        }
        return size_t.max;
    }

public:
    size_t length() const nothrow @nogc
    {
        return records.length;
    }

    RishHostRecord* find(AndroidPid owner_pid) nothrow @nogc
    {
        auto i = find_index(owner_pid);
        return i == size_t.max ? null : &records[i];
    }

    RishHostHandle create_host(
        AndroidPid owner_pid,
        RishHostSpec spec,
        RishHostOps ops)
    {
        auto generation = next_generation++;
        auto handle = ops.start_host(
            owner_pid,
            spec,
            generation);

        if (!handle.valid)
        {
            return RishHostHandle.init;
        }

        /*
         * Upstream HOSTS.put(callingPid, host) replaces any older map entry
         * without explicitly killing that old host. Preserve that behavior:
         * ownership is by the latest host registered for this Binder PID.
         */
        auto i = find_index(owner_pid);
        RishHostRecord record;
        record.handle = handle;
        record.spec = spec;

        if (i == size_t.max)
        {
            records ~= record;
        }
        else
        {
            records[i] = record;
        }

        return handle;
    }

    bool set_window_size(
        AndroidPid owner_pid,
        ulong packed_size,
        RishHostOps ops)
    {
        auto record = find(owner_pid);
        if (record is null)
        {
            return false;
        }

        ops.set_window_size(
            record.handle,
            packed_size);
        return true;
    }

    int exit_code(
        AndroidPid owner_pid,
        RishHostOps ops)
    {
        auto record = find(owner_pid);
        if (record is null)
        {
            return -1;
        }

        return ops.get_exit_code(record.handle);
    }
}

RishHostSpec prepare_rish_host(
    bool server_is_root,
    string[] arguments,
    string[] environment,
    string directory,
    ubyte tty,
    FileDescriptorHandle stdin_fd,
    FileDescriptorHandle stdout_fd,
    FileDescriptorHandle stderr_fd)
{
    RishHostSpec spec;
    spec.arguments = arguments;
    spec.directory = directory;
    spec.tty = tty;
    spec.stdin_fd = stdin_fd;
    spec.stdout_fd = stdout_fd;

    /*
     * When stderr is a TTY, upstream does not receive a separate stderr
     * descriptor; the native host directs stderr to the same PTY.
     */
    if ((tty & atty_err) == 0)
    {
        spec.stderr_fd = stderr_fd;
    }

    spec.environment_preserved =
        rish_preserve_environment(
            server_is_root,
            environment);

    if (spec.environment_preserved)
    {
        spec.environment = environment;
    }

    return spec;
}

enum RishDispatchKind : ubyte
{
    not_rish,
    create_host,
    set_window_size,
    get_exit_code
}

struct RishDispatchResult
{
    RishDispatchKind kind;
    bool handled;
    bool host_created;
    bool host_found;
    int exit_code;
}

alias EnforceRishPermission = bool delegate(string operation);

RishDispatchResult dispatch_rish_create_host(
    ref RishHostRegistry hosts,
    AndroidPid caller_pid,
    bool server_is_root,
    bool reply_present,
    int binder_flags,
    RishHostSpec requested,
    EnforceRishPermission enforce_permission,
    RishHostOps ops)
{
    RishDispatchResult result;
    result.kind = RishDispatchKind.create_host;
    result.handled = true;

    if (enforce_permission is null ||
        !enforce_permission("createHost"))
    {
        return result;
    }

    /*
     * This ordering is deliberate. RishService enforces permission first, then
     * treats a missing reply or FLAG_ONEWAY createHost as handled but does not
     * read the Parcel and does not fork.
     */
    if (!reply_present ||
        (binder_flags & binder_flag_oneway) != 0)
    {
        return result;
    }

    auto spec = prepare_rish_host(
        server_is_root,
        requested.arguments,
        requested.environment,
        requested.directory,
        requested.tty,
        requested.stdin_fd,
        requested.stdout_fd,
        requested.stderr_fd);

    auto host = hosts.create_host(
        caller_pid,
        spec,
        ops);

    result.host_created = host.valid;
    result.host_found = host.valid;
    return result;
}

RishDispatchResult dispatch_rish_set_window_size(
    ref RishHostRegistry hosts,
    AndroidPid caller_pid,
    ulong packed_size,
    EnforceRishPermission enforce_permission,
    RishHostOps ops)
{
    RishDispatchResult result;
    result.kind = RishDispatchKind.set_window_size;
    result.handled = true;

    if (enforce_permission is null ||
        !enforce_permission("setWindowSize"))
    {
        return result;
    }

    result.host_found =
        hosts.set_window_size(
            caller_pid,
            packed_size,
            ops);

    return result;
}

RishDispatchResult dispatch_rish_get_exit_code(
    ref RishHostRegistry hosts,
    AndroidPid caller_pid,
    EnforceRishPermission enforce_permission,
    RishHostOps ops)
{
    RishDispatchResult result;
    result.kind = RishDispatchKind.get_exit_code;
    result.handled = true;

    if (enforce_permission is null ||
        !enforce_permission("getExitCode"))
    {
        result.exit_code = -1;
        return result;
    }

    auto record = hosts.find(caller_pid);
    result.host_found = record !is null;
    result.exit_code = result.host_found
        ? hosts.exit_code(caller_pid, ops)
        : -1;

    return result;
}

RishDispatchKind classify_rish_transaction(
    RishConfig config,
    int binder_code)
    nothrow @nogc
{
    if (binder_code ==
        config.transaction_code(
            rish_transaction_create_host))
    {
        return RishDispatchKind.create_host;
    }

    if (binder_code ==
        config.transaction_code(
            rish_transaction_set_window_size))
    {
        return RishDispatchKind.set_window_size;
    }

    if (binder_code ==
        config.transaction_code(
            rish_transaction_get_exit_code))
    {
        return RishDispatchKind.get_exit_code;
    }

    return RishDispatchKind.not_rish;
}
