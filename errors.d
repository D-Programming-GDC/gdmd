module gdmd.errors;

import core.stdc.stdio;
import core.stdc.stdarg;

@safe nothrow @nogc:
package:

// Print error for unrecognized switch `arg`.
void unrecognizedSwitch(string arg)
{
    errorPrint("Error: unrecognized switch `%.*s`",
               cast(int)arg.length, arg.ptr);
}

// Print error for unsupported switch `arg`.
void unsupportedSwitch(string arg, string msg)
{
    errorPrint("Error: `%.*s` no longer supported, %.*s",
               cast(int)arg.length, arg.ptr, cast(int)msg.length, msg.ptr);
}

// Print error for unimplemented switch `arg`.
void unimplementedSwitch(string arg)
{
    errorPrint("Warning: `%.*s` is unimplemented and ignored",
               cast(int)arg.length, arg.ptr);
}

// Print error for invalid argument `arg` with optional supplemental help
// message `msg`.
void invalidArgument(string arg, string msg = null)
{
    errorPrint("Error: switch `%.*s` is invalid",
               cast(int)arg.length, arg.ptr);
    if (msg)
        errorPrint("%.*s", cast(int)msg.length, msg.ptr);
}

// Print error for empty argument `arg` with optional supplemental help
// message `msg.
void missingArgument(string arg, string msg = null)
{
    errorPrint("Error: argument expected for switch `%.*s`",
               cast(int)arg.length, arg.ptr);
    if (msg)
        errorPrint("%.*s", cast(int)msg.length, msg.ptr);
}

// Print error if any command line arguments are malformed.
void malformedArguments()
{
    errorPrint("Error: missing or null command line arguments");
}

// Printed if driver couldn't open a @response file.
void missingResponseFile()
{
    errorPrint("Error: can't open response file");
}

private:

// Send an error `msg` to console.
void errorPrint(const(char)* msg, ...) @trusted
{
    vfprintf(stderr, msg, _argptr);
    fputc('\n', stderr);
    fflush(stderr);
}
