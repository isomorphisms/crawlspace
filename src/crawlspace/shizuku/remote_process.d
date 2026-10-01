module crawlspace.shizuku.remote_process;

import crawlspace.shizuku.types;

struct ProcessHandle
{
    void* raw;

    bool valid() const nothrow @nogc
    {
        return raw !is null;
    }
}

struct StreamHandle
{
    void* raw;

    bool valid() const nothrow @nogc
    {
        return raw !is null;
    }
}

struct PipeHandle
{
    int fd = -1;

    bool valid() const nothrow @nogc
    {
        return fd >= 0;
    }
}

struct RemoteProcessSpec
{
    string[] command;
    string[] environment;
    string directory;
}

struct RemoteProcessRecord
{
    ulong generation;
    ProcessHandle process;
    BinderHandle owner_token;

    PipeHandle cached_output_stream;
    PipeHandle cached_input_stream;
}

alias SpawnProcess =
    ProcessHandle delegate(RemoteProcessSpec spec);
alias LinkOwnerDeath =
    bool delegate(
        BinderHandle token,
        ulong generation);
alias ProcessAlive =
    bool delegate(ProcessHandle process);
alias DestroyProcess =
    void delegate(ProcessHandle process);
alias ProcessWait =
    int delegate(ProcessHandle process);
alias ProcessExitValue =
    int delegate(ProcessHandle process);
alias ProcessInputStream =
    StreamHandle delegate(ProcessHandle process);
alias ProcessOutputStream =
    StreamHandle delegate(ProcessHandle process);
alias ProcessErrorStream =
    StreamHandle delegate(ProcessHandle process);
alias PipeFromStream =
    PipeHandle delegate(StreamHandle stream);
alias PipeToStream =
    PipeHandle delegate(StreamHandle stream);
alias MonotonicNanoseconds = ulong delegate();
alias SleepMilliseconds = void delegate(uint milliseconds);

struct RemoteProcessOps
{
    SpawnProcess spawn_process;
    LinkOwnerDeath link_owner_death;
    ProcessAlive process_alive;
    DestroyProcess destroy_process;
    ProcessWait wait_for;
    ProcessExitValue exit_value;

    ProcessInputStream input_stream;
    ProcessOutputStream output_stream;
    ProcessErrorStream error_stream;

    PipeFromStream pipe_from_stream;
    PipeToStream pipe_to_stream;

    MonotonicNanoseconds monotonic_nanoseconds;
    SleepMilliseconds sleep_milliseconds;
}

struct RemoteProcessCreateResult
{
    bool created;
    ulong generation;
}

struct RemoteProcessRegistry
{
private:
    RemoteProcessRecord[] records;
    ulong next_generation = 1;

    size_t find_index(ulong generation) const nothrow @nogc
    {
        foreach (i, record; records)
        {
            if (record.generation == generation)
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

    RemoteProcessRecord* find(ulong generation)
    {
        auto i = find_index(generation);
        return i == size_t.max ? null : &records[i];
    }

    RemoteProcessCreateResult create(
        RemoteProcessSpec spec,
        BinderHandle owner_token,
        RemoteProcessOps ops)
    {
        RemoteProcessCreateResult result;

        if (ops.spawn_process is null)
        {
            return result;
        }

        auto process = ops.spawn_process(spec);
        if (!process.valid)
        {
            return result;
        }

        RemoteProcessRecord record;
        record.generation = next_generation++;
        record.process = process;
        record.owner_token = owner_token;

        /*
         * RemoteProcessHolder logs linkToDeath failure but keeps the process
         * alive and still returns the holder.
         */
        if (owner_token.valid &&
            ops.link_owner_death !is null)
        {
            ops.link_owner_death(
                owner_token,
                record.generation);
        }

        records ~= record;

        result.created = true;
        result.generation = record.generation;
        return result;
    }

    bool owner_died(
        ulong generation,
        RemoteProcessOps ops)
    {
        auto record = find(generation);
        if (record is null)
        {
            return false;
        }

        if (ops.process_alive !is null &&
            ops.process_alive(record.process) &&
            ops.destroy_process !is null)
        {
            ops.destroy_process(record.process);
        }

        return true;
    }

    PipeHandle get_output_stream(
        ulong generation,
        RemoteProcessOps ops)
    {
        auto record = find(generation);
        if (record is null)
        {
            return PipeHandle.init;
        }

        /*
         * Java Process#getOutputStream writes to the child's stdin. Shizuku
         * creates this pipe lazily and caches it.
         */
        if (!record.cached_output_stream.valid)
        {
            auto stream =
                ops.output_stream(record.process);
            record.cached_output_stream =
                ops.pipe_to_stream(stream);
        }

        return record.cached_output_stream;
    }

    PipeHandle get_input_stream(
        ulong generation,
        RemoteProcessOps ops)
    {
        auto record = find(generation);
        if (record is null)
        {
            return PipeHandle.init;
        }

        /*
         * Java Process#getInputStream reads the child's stdout. This one is
         * also lazily created and cached.
         */
        if (!record.cached_input_stream.valid)
        {
            auto stream =
                ops.input_stream(record.process);
            record.cached_input_stream =
                ops.pipe_from_stream(stream);
        }

        return record.cached_input_stream;
    }

    PipeHandle get_error_stream(
        ulong generation,
        RemoteProcessOps ops)
    {
        auto record = find(generation);
        if (record is null)
        {
            return PipeHandle.init;
        }

        /*
         * Upstream does not cache the stderr bridge: each request calls
         * pipeFrom(process.getErrorStream()) again.
         */
        auto stream = ops.error_stream(record.process);
        return ops.pipe_from_stream(stream);
    }
}

bool wait_for_timeout(
    ProcessHandle process,
    ulong timeout_nanoseconds,
    RemoteProcessOps ops)
{
    auto start = ops.monotonic_nanoseconds();
    auto remaining = timeout_nanoseconds;

    do
    {
        if (!ops.process_alive(process))
        {
            return true;
        }

        if (remaining > 0)
        {
            /*
             * Upstream sleeps min(nanosToMillis(rem) + 1, 100).
             */
            auto milliseconds =
                remaining / 1_000_000UL + 1;

            if (milliseconds > 100)
            {
                milliseconds = 100;
            }

            ops.sleep_milliseconds(
                cast(uint) milliseconds);
        }

        auto now = ops.monotonic_nanoseconds();
        auto elapsed =
            now >= start
                ? now - start
                : ulong.max;

        remaining =
            elapsed >= timeout_nanoseconds
                ? 0
                : timeout_nanoseconds - elapsed;
    }
    while (remaining > 0);

    return false;
}
