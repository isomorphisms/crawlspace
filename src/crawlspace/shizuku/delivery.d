module crawlspace.shizuku.delivery;

import crawlspace.shizuku.types;

struct ProviderHandle
{
    void* raw;

    bool valid() const nothrow @nogc
    {
        return raw !is null;
    }
}

enum DeliveryAttempt : ubyte
{
    first_attempt,
    retry_after_force_stop
}

enum DeliveryResult : ubyte
{
    delivered,
    provider_missing,
    provider_dead,
    provider_rejected_binder
}

alias TempWhitelist = bool delegate(
    string package_name,
    int user_id,
    uint milliseconds);
alias OpenExternalProvider = ProviderHandle delegate(
    string provider_name,
    int user_id);
alias ProviderAlive = bool delegate(ProviderHandle provider);
alias SendBrokerBinder = bool delegate(
    ProviderHandle provider,
    BinderHandle broker,
    string provider_name);
alias CloseExternalProvider = void delegate(string provider_name);
alias ForceStopPackage = void delegate(string package_name, int user_id);
alias SleepMilliseconds = void delegate(uint milliseconds);

struct DeliveryOps
{
    TempWhitelist temp_whitelist;
    OpenExternalProvider open_external_provider;
    ProviderAlive provider_alive;
    SendBrokerBinder send_broker_binder;
    CloseExternalProvider close_external_provider;
    ForceStopPackage force_stop_package;
    SleepMilliseconds sleep_milliseconds;
}

DeliveryResult deliver_broker_binder(
    BinderHandle broker,
    string package_name,
    int user_id,
    DeliveryOps ops,
    DeliveryAttempt attempt = DeliveryAttempt.first_attempt)
{
    /*
     * Shizuku treats failure to obtain the temporary idle exemption as
     * non-fatal and still attempts delivery.
     */
    if (ops.temp_whitelist !is null)
    {
        ops.temp_whitelist(package_name, user_id, 30_000);
    }

    const provider_name = package_name ~ ".shizuku";
    const provider = ops.open_external_provider(provider_name, user_id);

    if (!provider.valid)
    {
        return DeliveryResult.provider_missing;
    }

    /*
     * Upstream removes the external provider in a finally block and passes a
     * null token. Keep release unconditional here; token/count mechanics stay
     * inside the Android implementation of this operation.
     */
    scope (exit)
    {
        ops.close_external_provider(provider_name);
    }

    if (!ops.provider_alive(provider))
    {
        if (attempt == DeliveryAttempt.first_attempt)
        {
            ops.force_stop_package(package_name, user_id);
            ops.sleep_milliseconds(1_000);

            return deliver_broker_binder(
                broker,
                package_name,
                user_id,
                ops,
                DeliveryAttempt.retry_after_force_stop);
        }

        return DeliveryResult.provider_dead;
    }

    if (ops.send_broker_binder(provider, broker, provider_name))
    {
        return DeliveryResult.delivered;
    }

    return DeliveryResult.provider_rejected_binder;
}
