/**
 * Handles response file parsing and response file generation.
 *
 * Note that GCC uses a simpler response file format (no windows
 * escaping), arguments always separated by newlines.
 *
 * The response file parsing is not 100% compatible with
 * DMD as it only implements 'sane' use cases. For example the parser
 * does not handle embedded \0 characters, comments, newlines in quoted
 * strings and some more corner cases.
 */
module gdmd.response;

import std.array, std.file, std.process, std.string, std.uni;
import gdmd.util;

/**
 * Expand all response files in args recursively.
 * Response files are parameters name @name and specify either an
 * environment variable or a file name. The variable or file will
 * contain further arguments in a windows specific escaping format.
 */
string[] parseResponse(string[] args)
{
    string[] result;
    foreach (arg; args)
    {
        if (arg.startsWith("@"))
            result ~= parseResponse(arg[1 .. $]);
        else
            result ~= arg;
    }
    return result;
}

unittest
{
    import std.process;

    environment["RESP1"] = `@RESP2 foo "@bar" @RESP3` ~ "\n" ~ `@RESP2 foo "@bar" @`;
    environment["RESP2"] = `resp2 resp2`;
    environment["RESP3"] = `"res\"p3" resp3`;

    auto result = parseResponse([`@RESP1`]);
    assert(result[0] == `resp2`);
    assert(result[1] == `resp2`);
    assert(result[2] == `foo`);
    assert(result[3] == `@bar`);
    assert(result[4] == `res"p3`);
    assert(result[5] == `resp3`);
    assert(result[6] == `resp2`);
    assert(result[7] == `resp2`);
    assert(result[8] == `foo`);
    assert(result[9] == `@bar`);
}

/**
 * Expand a single response file. The leading @ must be removed
 * before calling this function.
 */
string[] parseResponse(string name)
{
    string[] result;

    if (name.empty)
        return result;
    // First look in evironment
    string content = environment.get(name);
    // Then try to read a file
    if (content is null)
        content = readText(name);

    foreach (line; content.lineSplitter())
    {
        result ~= unescapeLine(line);
    }

    return result;
}

/**
 * Reverse the windows argument escaping
 */
string[] unescapeLine(string line)
{
    static bool isEscapedQuote(const(char)[] str)
    {
        foreach (c; str)
        {
            if (c == '"')
                return true;
            else if (c != '\\')
                return false;
        }
        return false;
    }

    bool inQuoteString = false;
    string buffer;
    string[] result;
    for (size_t i = 0; i < line.length; i++)
    {
        char c = line[i];

        // Recursive response file expansion
        if (c == '@' && !inQuoteString)
        {
            // Need at least one more character
            if (i + 1 < line.length)
            {
                size_t j = i;
                for (; j < line.length && !line[j].isWhite; j++)
                {
                }
                result ~= parseResponse(line[i + 1 .. j]);
                i = j;
            }
        }
        else if (c == '"')
        {
            if (inQuoteString)
            {
                result ~= buffer;
                buffer = "";
            }
            inQuoteString = !inQuoteString;

        }
        else if (c == '\\' && isEscapedQuote(line[i .. $]))
        {
            size_t numSlash = 0;
            while (line[i] != '"')
            {
                if (++numSlash == 2)
                {
                    numSlash = 0;
                    buffer ~= '\\';
                }
                i++;
            }
            // line[i] is now '"'
            // For \\" only produce one backslash, quote is not escaped
            if (numSlash == 0)
                i--;
            else
                buffer ~= '"';
        }
        else if (c.isWhite() && !inQuoteString)
        {
            if (!buffer.empty)
                result ~= buffer;
            buffer = "";
        }
        else
        {
            buffer ~= c;
        }
    }

    if (!buffer.empty && !inQuoteString)
        result ~= buffer;

    return result;
}

// Adapted from phobos, std.process
unittest
{
    string[] testStrings = [
        `Hello`, `Hello, world`, `Hello, "world"`, `C:\`, `C:\dmd`, `C:\Program Files\`,
    ];

    enum CHARS = `_x\" *&^` ~ "\t"; // _ is placeholder for nothing
    foreach (c1; CHARS)
        foreach (c2; CHARS)
            foreach (c3; CHARS)
                foreach (c4; CHARS)
                    testStrings ~= [c1, c2, c3, c4].replace("_", "");

    import std.process;

    foreach (s; testStrings)
    {
        auto q = escapeWindowsArgument(s);
        foreach (s2; testStrings[0 .. 10])
        {
            auto q2 = escapeWindowsArgument(s2);
            auto u = unescapeLine(q ~ " " ~ q2);

            assert(u[0] == s);
            assert(u[1] == s2);
        }
    }
}

/**
 * Maximum length of cmd string (excluding os specific escaping)
 */
enum maxCMDLength = 1024;

/**
 * Exexute a process, use response files if necessary
 */
auto executeResponse(string[] args, bool debugCommands, bool printResult = false)
{
    return doResponse(args, debugCommands, printResult, cmd => execute(cmd));
}

/**
 * Spawn a process and directly wait for it to finish, use response files if necessary
 */
auto spawnWaitResponse(string[] args, bool debugCommands, bool printResult = false)
{
    return doResponse(args, debugCommands, printResult, (string[] cmd) {
        auto pid = spawnProcess(cmd);
        return wait(pid);
    });
}

/**
 * Helper function. Prepare response file and do logging, then
 * call cb and return its return value.
 */
private T doResponse(T)(string[] args, bool debugCommands, bool printResult,
    T delegate(string[] args) cb)
{
    import std.algorithm, std.file, std.path, std.range, std.stdio, std.utf;

    string respFile;
    scope (exit)
    {
        if (!respFile.empty && respFile.exists())
            respFile.remove();
    }

    if (args.joiner(" ").byCodeUnit.walkLength > maxCMDLength)
    {
        respFile = tempDir().buildPath("gdc_%s.response".format(randomLetters(10)));
        if (debugCommands)
            writefln("[exec] Writing response file to %s", respFile);

        auto rfile = File(respFile, "w");
        foreach (i, arg; args[1 .. $])
        {
            if (i != 0)
                rfile.write("\n");
            // GCC format
            rfile.writef(`"%s"`, arg.replace(`\`, `\\`).replace(`"`, `\"`).replace(`'`,
                `\'"`));
        }
        rfile.close();

        args = [args[0], "@" ~ respFile];
    }

    if (debugCommands)
        writefln("[exec]  %s", args.joiner(" "));
    auto result = cb(args);
    if (debugCommands && printResult)
        writefln("[exec] Result: %s", result);
    return result;
}
