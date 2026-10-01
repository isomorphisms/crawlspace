module crawlspace.shizuku.user_service_entry;

import crawlspace.shizuku.types;

enum UserServiceEntryError : ubyte
{
    none,
    invalid_uid,
    platform_creation_failed
}

struct UserServiceArguments
{
    string debug_name;
    bool has_debug_name;

    string token;
    string package_name;
    string class_name;

    AndroidUid calling_uid = -1;
}

struct UserServiceArgumentResult
{
    UserServiceEntryError error;
    UserServiceArguments arguments;

    bool ok() const nothrow @nogc
    {
        return error == UserServiceEntryError.none;
    }
}

private bool parse_decimal_int(
    string text,
    out int value)
{
    if (text.length == 0)
    {
        return false;
    }

    bool negative;
    size_t i;

    if (text[0] == '-')
    {
        negative = true;
        i = 1;

        if (i == text.length)
        {
            return false;
        }
    }

    long result;

    for (; i < text.length; ++i)
    {
        auto c = text[i];
        if (c < '0' || c > '9')
        {
            return false;
        }

        result =
            result * 10 +
            cast(int) (c - '0');

        auto signed_result =
            negative ? -result : result;

        if (signed_result < int.min ||
            signed_result > int.max)
        {
            return false;
        }
    }

    value = cast(int) (
        negative ? -result : result);
    return true;
}

UserServiceArgumentResult parse_user_service_arguments(
    string[] args)
{
    UserServiceArgumentResult result;

    /*
     * The Java loop overwrites fields when an option appears more than once,
     * so the last occurrence wins.
     */
    foreach (arg; args)
    {
        if (arg.length >= 13 &&
            arg[0 .. 13] == "--debug-name=")
        {
            result.arguments.debug_name =
                arg[13 .. $];
            result.arguments.has_debug_name = true;
        }
        else if (arg.length >= 8 &&
                 arg[0 .. 8] == "--token=")
        {
            result.arguments.token =
                arg[8 .. $];
        }
        else if (arg.length >= 10 &&
                 arg[0 .. 10] == "--package=")
        {
            result.arguments.package_name =
                arg[10 .. $];
        }
        else if (arg.length >= 8 &&
                 arg[0 .. 8] == "--class=")
        {
            result.arguments.class_name =
                arg[8 .. $];
        }
        else if (arg.length >= 6 &&
                 arg[0 .. 6] == "--uid=")
        {
            int uid;
            if (!parse_decimal_int(
                    arg[6 .. $],
                    uid))
            {
                result.error =
                    UserServiceEntryError.invalid_uid;
                return result;
            }

            result.arguments.calling_uid = uid;
        }
    }

    result.error = UserServiceEntryError.none;
    return result;
}

int user_service_android_user(
    AndroidUid uid)
    nothrow @nogc
{
    /*
     * Java integer division truncates toward zero. D integral division has the
     * same behavior, including the default uid=-1 producing user 0.
     */
    return uid / android_uid_per_user_range;
}

string user_service_process_name(
    UserServiceArguments arguments)
{
    if (arguments.has_debug_name)
    {
        return arguments.debug_name;
    }

    return arguments.package_name ~
        ":user_service";
}

enum UserServiceConstructor : ubyte
{
    context_constructor,
    no_arg_constructor
}

UserServiceConstructor select_user_service_constructor(
    bool public_context_constructor_exists)
    nothrow @nogc
{
    /*
     * UserService.create first asks getConstructor(Context.class), which means
     * a public Context constructor. Only NoSuchMethod/SecurityException cause
     * fallback to Class.newInstance().
     */
    return public_context_constructor_exists
        ? UserServiceConstructor.context_constructor
        : UserServiceConstructor.no_arg_constructor;
}

struct UserServicePlatformRequest
{
    string process_name;
    int user_id;
    string package_name;
    string class_name;
    UserServiceConstructor constructor;
}

alias CreateUserServiceBinder =
    BinderHandle delegate(
        UserServicePlatformRequest request);

struct UserServiceEntryOps
{
    bool public_context_constructor_exists;
    CreateUserServiceBinder create_binder;
}

struct UserServiceEntryResult
{
    UserServiceEntryError error;
    BinderHandle binder;
    string token;
    UserServicePlatformRequest request;

    bool ok() const nothrow @nogc
    {
        return error == UserServiceEntryError.none &&
            binder.valid;
    }
}

UserServiceEntryResult create_user_service(
    string[] args,
    UserServiceEntryOps ops)
{
    auto parsed =
        parse_user_service_arguments(args);

    UserServiceEntryResult result;

    if (!parsed.ok)
    {
        result.error = parsed.error;
        return result;
    }

    auto arguments = parsed.arguments;

    result.token = arguments.token;
    result.request.process_name =
        user_service_process_name(arguments);
    result.request.user_id =
        user_service_android_user(
            arguments.calling_uid);
    result.request.package_name =
        arguments.package_name;
    result.request.class_name =
        arguments.class_name;
    result.request.constructor =
        select_user_service_constructor(
            ops.public_context_constructor_exists);

    if (ops.create_binder is null)
    {
        result.error =
            UserServiceEntryError.platform_creation_failed;
        return result;
    }

    result.binder =
        ops.create_binder(result.request);

    if (!result.binder.valid)
    {
        result.error =
            UserServiceEntryError.platform_creation_failed;
        return result;
    }

    result.error = UserServiceEntryError.none;
    return result;
}
