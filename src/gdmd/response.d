/**
 * Handles response file parsing.
 */
module gdmd.response;

import std.array, std.file, std.process, std.string;
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

/**
 * Expand a single response file. The leading @ must be removed
 * before calling this function.
 */
string[] parseResponse(string name)
{
    string[] result;

    // First look in evironment
    string content = environment.get(name);
    // Then try to read a file
    if (content is null)
        content = readText(name);

    foreach (entry; ArgumentSplitter(content))
    {
        if (entry.startsWith("@"))
            result ~= parseResponse(entry[1 .. $]);
        else
            result ~= entry;
    }

    return result;
}

/**
 * Return true if char is used to split arguments.
 */
@property bool isSplitChar(char c)
{
    switch (c)
    {
    case '\r':
    case '\n':
    case '\0':
    case ' ':
    case '\t':
        return true;
    default:
        return false;
    }
}

/**
 * Step 1: Split text string into separate arguments
 */
private struct ArgumentSplitter
{
private:
    string _content;
    size_t _index = 0;

public:
    string front;

    this(string content)
    {
        _content = content;
        popFront();
    }

    @property bool empty()
    {
        return front.empty;
    }

    void popFront()
    {
        front = "";

        bool inString = false; // in "..."
        size_t start = size_t.max;
        for (; _index < _content.length; _index++)
        {
            switch (_content[_index])
            {
            case 0x1a:
                //EOF
                _index = _content.length;
                return;
            case '#':
                // Allow # in arguments
                if (!front.empty)
                {
                    front ~= _content[_index];
                }
                else
                {
                    for (; _index < _content.length; _index++)
                    {
                        if (_content[_index] == '\r' || _content[_index] == '\n')
                            break;
                    }
                }
                break;
            case '\\':
                bool needSplit;
                front ~= _content.parseEscapeSequence(_index, needSplit);
                if (needSplit)
                {
                    _index++;
                    return;
                }
                break;
            case '"':
                inString = !inString;
                break;
            default:
                if (_content[_index].isSplitChar())
                {
                    if (!front.empty && (!inString || _content[_index] == '\0'
                            || _content[_index] == '\n'))
                        return;
                    else if (inString)
                        front ~= _content[_index];
                }
                else
                    front ~= _content[_index];
            }
        }
    }
}

unittest
{
    // Whitespace handling
    assert(ArgumentSplitter("").array() == []);
    assert(ArgumentSplitter(" \t \r\n \r \0").array() == []);
    assert(ArgumentSplitter("foo").array() == ["foo"]);
    assert(ArgumentSplitter("foo \t \0\0 bar\r\n\nbaz\nboo\r\rab\r")
        .array() == ["foo", "bar", "baz", "boo", "ab"]);
    assert(ArgumentSplitter(`"foo bar"`).array() == ["foo bar"]);

    char endChar = 0x1a;
    assert(ArgumentSplitter(`"foo ` ~ endChar ~ `bar"`).array() == ["foo "]);
    assert(ArgumentSplitter("foo " ~ endChar ~ "bar").array() == ["foo"]);
    assert(ArgumentSplitter(" \t" ~ endChar).array() == []);

    // Comment handling
    assert(ArgumentSplitter(" \t#abc abc # \" \\ \\\" \0 \t foo1\r\nfoo").array() == ["foo"]);
    assert(ArgumentSplitter(" \t#comment\rabc def\r\nfoo").array() == ["abc", "def",
        "foo"]);
    assert(ArgumentSplitter("#comment\nabc").array() == ["abc"]);
    assert(ArgumentSplitter("#comment\r\nabc").array() == ["abc"]);
    assert(ArgumentSplitter("foo#nocomment").array() == ["foo#nocomment"]);
    assert(ArgumentSplitter("\"foo\"#nocomment").array() == ["foo#nocomment"]);
    assert(ArgumentSplitter("foo #comment").array() == ["foo"]);
    assert(ArgumentSplitter("\"foo\" #comment").array() == ["foo"]);

    // String handling
    assert(ArgumentSplitter(`\"abc\ def foo`).array() == [`"abc\`, "def", "foo"]);
    assert(ArgumentSplitter(`"abc\ def" foo`).array() == [`abc\ def`, "foo"]);
    assert(ArgumentSplitter(`"abc\" def" foo`).array() == [`abc" def`, "foo"]);
    assert(ArgumentSplitter(`"abc\\\" def" foo`).array() == [`abc\" def`, "foo"]);
    assert(ArgumentSplitter(`"abc def\\" foo`).array() == [`abc def\`, `foo`]);
    assert(ArgumentSplitter(`"abc def\\"" foo`).array() == [`abc def\"`, "foo"]);
    assert(ArgumentSplitter("\" def\n \"foo").array() == [" def", "foo"]);
    assert(ArgumentSplitter("\" def\0 \"foo").array() == [" def", "foo"]);

    assert(ArgumentSplitter(`"C:\abc\" def" foo`).array() == [`C:\abc" def`, `foo`]);
    assert(ArgumentSplitter(`"C:\abc\\" def" foo`).array() == [`C:\abc\`, `def foo`]);
    assert(ArgumentSplitter(`"C:\abc\\\" def" foo`).array() == [`C:\abc\" def`, `foo`]);
    assert(ArgumentSplitter(`"C:\abc\\\\" def" foo`).array() == [`C:\abc\\`, `def foo`]);
    assert(ArgumentSplitter(`"C:\abc\\\\\" def" foo`).array() == [`C:\abc\\" def`,
        `foo`]);
}

// Adapted from phobos, std.process
unittest
{
    string[] parseCommandLine(string line)
    {
        return ArgumentSplitter(line).array();
    }

    string[] testStrings = [`Hello`, `Hello, world`, `Hello, "world"`, `C:\`, `C:\dmd`,
        // `C:\Program Files\`,
        ];

    enum CHARS = `_x\" *&^` ~ "\t"; // _ is placeholder for nothing
    foreach (c1; CHARS)
        foreach (c2; CHARS)
            foreach (c3; CHARS)
                foreach (c4; CHARS)
                    testStrings ~= [c1, c2, c3, c4].replace("_", "");

    foreach (s; testStrings)
    {
        // FIXME: We do not support parsing empty strings, but we don't need it either
        if (s.empty)
            continue;
        import std.process, std.conv;

        auto q = escapeWindowsArgument(s);
        auto args = parseCommandLine("Dummy.exe " ~ q);
        assert(args.length == 2, s ~ " => " ~ q ~ " #" ~ text(args.length - 1));
        assert(args[1] == s, s ~ " => " ~ q ~ " => " ~ args[1]);
    }

    import std.stdio;

    writeln(ArgumentSplitter(`"C:\abc\\"def" foo`));
}

/**
 * Parse a backslash / quotation mark sequence as described on
 * https://msdn.microsoft.com/en-us/library/windows/desktop/bb776391%28v=vs.85%29.aspx
 *
 * 2n backslashes followed by a quotation mark produce n backslashes followed by a quotation mark.
 * (2n) + 1 backslashes followed by a quotation mark again produce n backslashes followed by a quotation mark.
 * n backslashes not followed by a quotation mark simply produce n backslashes.
 */
private string parseEscapeSequence(string content, ref size_t position, out bool needSplit)
{
    import std.range : repeat;

    size_t num = 0;
    needSplit = false;
    while (position < content.length)
    {
        if (content[position] == '"')
        {
            // If " is followed by a splitting char, the " is not kept except if num is odd...
            if ((num % 2 == 0) && (position + 1 >= content.length
                    || content[position + 1].isSplitChar()))
            {
                needSplit = true;
                return '\\'.repeat(num / 2).array().idup;
            }
            else
            {
                return '\\'.repeat(num / 2).array().idup ~ "\"";
            }
        }
        else if (content[position] != '\\')
        {
            position--;
            return '\\'.repeat(num).array().idup;
        }

        num++;
        position++;
    }

    position--;
    return '\\'.repeat(num).array().idup;
}

unittest
{
    size_t idx = 0;
    bool needSplit;
    assert(r"\".parseEscapeSequence(idx, needSplit) == r"\" && idx == 0);
    idx = 0;
    assert(r"\ ".parseEscapeSequence(idx, needSplit) == r"\" && idx == 0);
    idx = 0;
    assert(r"\\ ".parseEscapeSequence(idx, needSplit) == r"\\" && idx == 1);
    idx = 0;
    assert(r"\\\ ".parseEscapeSequence(idx, needSplit) == r"\\\" && idx == 2);
    idx = 0;
    assert(r"\\\".parseEscapeSequence(idx, needSplit) == r"\\\" && idx == 2);

    idx = 0;
    assert(`\"`.parseEscapeSequence(idx, needSplit) == `"` && idx == 1);
    idx = 0;
    assert(`\" `.parseEscapeSequence(idx, needSplit) == `"` && idx == 1);
    idx = 0;
    assert(`\\" `.parseEscapeSequence(idx, needSplit) == `\` && idx == 2);
    idx = 0;
    assert(`\\\" `.parseEscapeSequence(idx, needSplit) == `\"` && idx == 3);
    idx = 0;
    assert(`\\\" `.parseEscapeSequence(idx, needSplit) == `\"` && idx == 3);
    idx = 0;
    assert(`\\\\" `.parseEscapeSequence(idx, needSplit) == `\\` && idx == 4);
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
