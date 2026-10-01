module crawlspace.shizuku.framework_forwarding;

import crawlspace.shizuku.android_boundary;
import crawlspace.shizuku.service;
import crawlspace.shizuku.types;

alias JavaObject = void*;

alias JavaParcelObtain =
    JavaObject delegate();
alias NativeParcelFromJava =
    void* delegate(JavaObject parcel);
alias DeleteNativeParcelWrapper =
    void delegate(void* parcel);
alias JavaParcelRecycle =
    void delegate(JavaObject parcel);
alias DeleteLocalReference =
    void delegate(JavaObject object);

alias NativeReadStrongBinder =
    bool delegate(
        void* parcel,
        out void* binder);
alias NativeReadInt32 =
    bool delegate(
        void* parcel,
        out int value);
alias NativeBinderToJava =
    JavaObject delegate(void* binder);
alias NativeBinderDecStrong =
    void delegate(void* binder);

alias NativeParcelPosition =
    int delegate(void* parcel);
alias NativeParcelSize =
    int delegate(void* parcel);
alias NativeParcelAppend =
    bool delegate(
        void* source,
        void* target,
        int start,
        int size);

alias JavaBinderTransact =
    bool delegate(
        JavaObject target,
        TransactionCode code,
        JavaObject data,
        JavaObject reply,
        TransactionFlags flags);

alias FrameworkClearCallingIdentity =
    ulong delegate();
alias FrameworkRestoreCallingIdentity =
    void delegate(ulong identity);
alias FrameworkExceptionPending =
    bool delegate();
alias FrameworkRethrowPendingException =
    void delegate();

class FrameworkPendingJavaException : Exception
{
    this()
    {
        super("Java framework call raised an exception");
    }
}

struct FrameworkForwardingOps
{
    JavaParcelObtain parcel_obtain;
    NativeParcelFromJava parcel_from_java;
    DeleteNativeParcelWrapper delete_native_parcel;
    JavaParcelRecycle parcel_recycle;
    DeleteLocalReference delete_local_reference;

    NativeReadStrongBinder read_strong_binder;
    NativeReadInt32 read_int32;
    NativeBinderToJava binder_to_java;
    NativeBinderDecStrong binder_dec_strong;

    NativeParcelPosition parcel_position;
    NativeParcelSize parcel_size;
    NativeParcelAppend parcel_append;

    JavaBinderTransact binder_transact;

    FrameworkClearCallingIdentity clear_calling_identity;
    FrameworkRestoreCallingIdentity restore_calling_identity;
    FrameworkExceptionPending exception_pending;
    FrameworkRethrowPendingException rethrow_pending_exception;

    bool complete() const nothrow @nogc
    {
        return parcel_obtain !is null &&
            parcel_from_java !is null &&
            delete_native_parcel !is null &&
            parcel_recycle !is null &&
            delete_local_reference !is null &&
            read_strong_binder !is null &&
            read_int32 !is null &&
            binder_to_java !is null &&
            binder_dec_strong !is null &&
            parcel_position !is null &&
            parcel_size !is null &&
            parcel_append !is null &&
            binder_transact !is null &&
            clear_calling_identity !is null &&
            restore_calling_identity !is null &&
            exception_pending !is null &&
            rethrow_pending_exception !is null;
    }
}

ParcelHandle borrow_framework_parcel(
    JavaObject java_parcel,
    FrameworkForwardingOps ops)
{
    ParcelHandle result;

    if (java_parcel is null ||
        ops.parcel_from_java is null)
    {
        return result;
    }

    result.raw =
        ops.parcel_from_java(java_parcel);

    if (result.raw is null)
    {
        return ParcelHandle.init;
    }

    result.framework_raw = java_parcel;
    return result;
}

void release_borrowed_framework_parcel(
    ParcelHandle parcel,
    FrameworkForwardingOps ops)
{
    /*
     * AParcel_fromJavaParcel creates a native wrapper that must be deleted,
     * but it does not own the Java Parcel. The Java caller remains responsible
     * for that object.
     */
    if (parcel.raw !is null &&
        ops.delete_native_parcel !is null)
    {
        ops.delete_native_parcel(parcel.raw);
    }
}

struct FrameworkBorrowedTransaction
{
    ParcelHandle input;
    ParcelHandle reply;

    bool valid() const nothrow @nogc
    {
        return input.valid;
    }
}

FrameworkBorrowedTransaction borrow_framework_transaction(
    JavaObject java_input,
    JavaObject java_reply,
    FrameworkForwardingOps ops)
{
    FrameworkBorrowedTransaction result;

    result.input =
        borrow_framework_parcel(
            java_input,
            ops);

    if (!result.input.valid)
    {
        return result;
    }

    if (java_reply !is null)
    {
        result.reply =
            borrow_framework_parcel(
                java_reply,
                ops);

        if (!result.reply.valid)
        {
            release_borrowed_framework_parcel(
                result.input,
                ops);
            result.input = ParcelHandle.init;
        }
    }

    return result;
}

void release_borrowed_framework_transaction(
    FrameworkBorrowedTransaction transaction,
    FrameworkForwardingOps ops)
{
    release_borrowed_framework_parcel(
        transaction.reply,
        ops);
    release_borrowed_framework_parcel(
        transaction.input,
        ops);
}

TransparentBinderBridge build_framework_transparent_bridge(
    FrameworkForwardingOps ops)
{
    TransparentBinderBridge bridge;

    if (!ops.complete)
    {
        return bridge;
    }

    bool read_strong_binder(
        ParcelHandle parcel,
        out BinderHandle binder)
    {
        binder = BinderHandle.init;

        void* native_binder;
        if (!ops.read_strong_binder(
                parcel.raw,
                native_binder) ||
            native_binder is null)
        {
            return false;
        }

        auto java_binder =
            ops.binder_to_java(native_binder);

        if (java_binder is null)
        {
            ops.binder_dec_strong(native_binder);
            return false;
        }

        binder.raw = native_binder;
        binder.framework_raw = java_binder;
        return true;
    }

    bool read_int32(
        ParcelHandle parcel,
        out int value)
    {
        return ops.read_int32(
            parcel.raw,
            value);
    }

    void release_binder(BinderHandle binder)
    {
        /*
         * AParcel_readStrongBinder passes one strong native reference to the
         * caller. AIBinder_toJavaBinder also returns a JNI local reference.
         * Release both.
         */
        if (binder.framework_raw !is null)
        {
            ops.delete_local_reference(
                binder.framework_raw);
        }

        if (binder.raw !is null)
        {
            ops.binder_dec_strong(
                binder.raw);
        }
    }

    ParcelHandle create_parcel()
    {
        ParcelHandle result;

        auto java_parcel =
            ops.parcel_obtain();

        if (java_parcel is null)
        {
            return result;
        }

        auto native_parcel =
            ops.parcel_from_java(
                java_parcel);

        if (native_parcel is null)
        {
            ops.parcel_recycle(java_parcel);
            ops.delete_local_reference(java_parcel);
            return result;
        }

        result.raw = native_parcel;
        result.framework_raw = java_parcel;
        return result;
    }

    void delete_parcel(ParcelHandle parcel)
    {
        /*
         * This is the owned temporary forwarded Parcel, unlike borrowed
         * incoming/reply wrappers.
         */
        if (parcel.raw !is null)
        {
            ops.delete_native_parcel(
                parcel.raw);
        }

        if (parcel.framework_raw !is null)
        {
            ops.parcel_recycle(
                parcel.framework_raw);
            ops.delete_local_reference(
                parcel.framework_raw);
        }
    }

    int parcel_position(ParcelHandle parcel)
    {
        return ops.parcel_position(
            parcel.raw);
    }

    int parcel_size(ParcelHandle parcel)
    {
        return ops.parcel_size(
            parcel.raw);
    }

    bool append_parcel(
        ParcelHandle source,
        ParcelHandle target,
        int start,
        int size)
    {
        return ops.parcel_append(
            source.raw,
            target.raw,
            start,
            size);
    }

    bool transact(
        BinderHandle target,
        TransactionCode code,
        ParcelHandle data,
        ParcelHandle reply,
        TransactionFlags flags)
    {
        if (target.framework_raw is null ||
            data.framework_raw is null)
        {
            return false;
        }

        auto accepted = ops.binder_transact(
            target.framework_raw,
            code,
            data.framework_raw,
            reply.framework_raw,
            flags);

        /*
         * The JNI shim captures and clears a Java exception rather than
         * leaving it pending. Throw a D marker now so transact_remote's
         * scope-exit cleanup runs before the JNI entrypoint rethrows it.
         */
        if (ops.exception_pending())
        {
            throw new FrameworkPendingJavaException;
        }

        return accepted;
    }

    bridge.read_strong_binder = &read_strong_binder;
    bridge.read_int32 = &read_int32;
    bridge.release_binder = &release_binder;
    bridge.create_parcel = &create_parcel;
    bridge.delete_parcel = &delete_parcel;
    bridge.parcel_position = &parcel_position;
    bridge.parcel_size = &parcel_size;
    bridge.append_parcel = &append_parcel;
    bridge.transact = &transact;

    return bridge;
}

BinderIdentityBridge build_framework_identity_bridge(
    FrameworkForwardingOps ops)
{
    BinderIdentityBridge bridge;

    if (ops.clear_calling_identity is null ||
        ops.restore_calling_identity is null ||
        ops.exception_pending is null)
    {
        return bridge;
    }

    ulong clear_identity()
    {
        auto identity =
            ops.clear_calling_identity();

        if (ops.exception_pending())
        {
            throw new FrameworkPendingJavaException;
        }

        return identity;
    }

    void restore_identity(ulong identity)
    {
        ops.restore_calling_identity(identity);

        if (ops.exception_pending())
        {
            throw new FrameworkPendingJavaException;
        }
    }

    bridge.clear_calling_identity =
        &clear_identity;
    bridge.restore_calling_identity =
        &restore_identity;
    return bridge;
}

bool rethrow_pending_framework_exception(
    FrameworkForwardingOps ops)
{
    if (ops.exception_pending is null ||
        ops.rethrow_pending_exception is null ||
        !ops.exception_pending())
    {
        return false;
    }

    ops.rethrow_pending_exception();
    return true;
}
