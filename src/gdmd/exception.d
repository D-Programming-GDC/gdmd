/**
 * Contains functions to exit the gdmd program early.
 */
module gdmd.exception;

import std.exception;

/**
 * Thrown to abort the program with an error.
 */
class AbortException : Exception
{
    public
    {
        @safe pure nothrow this(string message, string file = __FILE__,
            size_t line = __LINE__, Throwable next = null)
        {
            super(message, file, line, next);
        }
    }
}

/**
 * Thrown to exit the program normally.
 */
class ExitException : Exception
{
    public
    {
        @safe pure nothrow this(string message, string file = __FILE__,
            size_t line = __LINE__, Throwable next = null)
        {
            super(message, file, line, next);
        }
    }
}

/**
 * Check condition and abort program if condition is false.
 */
void enforceAbort(bool condition, string message)
{
    enforceEx!AbortException(condition, message);
}

/**
 * Abort the program with message.
 */
void abort(string message)
{
    throw new AbortException(message);
}

/**
 * Exit the program. Optionally print a message.
 */
void exit(string message = "")
{
    throw new ExitException(message);
}
