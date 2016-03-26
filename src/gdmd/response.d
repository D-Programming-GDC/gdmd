/**
 * Handles response file parsing.
 */
module gdmd.response;

import std.array, std.file, std.process, std.string;

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
        entry = unescape(entry);
        if (entry.startsWith("@"))
            result ~= parseResponse(entry[1 .. $]);
        else
            result ~= entry;
    }

    return result;
}

/**
 * Step 1: Split text string into separate arguments
 */
private struct ArgumentSplitter
{
private:
    string _content;
    size_t _index = 0;

    void markDone()
    {
        _index = _content.length;
    }

    void setFront(size_t start)
    {
        if (start == size_t.max)
            front = "";
        else
            front = _content[start .. _index];
    }

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
        if (_index == _content.length)
            front = "";

        bool inString = false; // in "..."
        size_t start = size_t.max;
        for (; _index < _content.length; _index++)
        {
            switch (_content[_index])
            {
            case 0x1a:
                //EOF
                setFront(start);
                markDone();
                return;
            case '#':
                // Allow # in arguments
                if (start == size_t.max)
                {
                    for (; _index < _content.length; _index++)
                    {
                        if (_content[_index] == '\r' || _content[_index] == '\n')
                            break;
                    }
                }
                break;
            case '\r':
            case '\n':
            case '\0':
            case ' ':
            case '\t':
                if (start != size_t.max && (!inString
                        || _content[_index] == '\0' || _content[_index] == '\n'))
                {
                    setFront(start);
                    return;
                }
                break;
            case '\\':
                if (start == size_t.max)
                    start = _index;
                _content.parseEscapeSequence(_index);
                break;
            case '"':
                inString = !inString;
                goto default;
            default:
                if (start == size_t.max)
                    start = _index;
            }
        }

        setFront(start);
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
    assert(ArgumentSplitter("\"foo bar\"").array() == ["\"foo bar\""]);

    char endChar = 0x1a;
    assert(ArgumentSplitter("\"foo " ~ endChar ~ "bar\"").array() == ["\"foo "]);
    assert(ArgumentSplitter("foo " ~ endChar ~ "bar").array() == ["foo"]);
    assert(ArgumentSplitter(" \t" ~ endChar).array() == []);

    // Comment handling
    assert(ArgumentSplitter(" \t#abc abc # \" \\ \\\" \0 \t foo1\r\nfoo").array() == ["foo"]);
    assert(ArgumentSplitter(" \t#comment\rabc def\r\nfoo").array() == ["abc", "def",
        "foo"]);
    assert(ArgumentSplitter("#comment\nabc").array() == ["abc"]);
    assert(ArgumentSplitter("#comment\r\nabc").array() == ["abc"]);
    assert(ArgumentSplitter("foo#nocomment").array() == ["foo#nocomment"]);
    assert(ArgumentSplitter("\"foo\"#nocomment").array() == ["\"foo\"#nocomment"]);
    assert(ArgumentSplitter("foo #comment").array() == ["foo"]);
    assert(ArgumentSplitter("\"foo\" #comment").array() == ["\"foo\""]);

    // String handling
    assert(ArgumentSplitter("\\\"abc\\ def foo").array() == ["\\\"abc\\", "def", "foo"]);
    assert(ArgumentSplitter("\"abc\\ def\" foo").array() == ["\"abc\\ def\"", "foo"]);
    assert(ArgumentSplitter("\"abc\\\" def\" foo").array() == ["\"abc\\\" def\"", "foo"]);
    assert(ArgumentSplitter("\"abc\\\\\\\" def\" foo").array() == ["\"abc\\\\\\\" def\"",
        "foo"]);
    assert(ArgumentSplitter("\"abc def\\\\\" foo").array() == ["\"abc def\\\\\" foo"]);
    assert(ArgumentSplitter("\"abc def\\\\\"\" foo").array() == ["\"abc def\\\\\"\"",
        "foo"]);
    assert(ArgumentSplitter("\" def\n \"foo").array() == ["\" def", "\"foo"]);
    assert(ArgumentSplitter("\" def\0 \"foo").array() == ["\" def", "\"foo"]);
}

/**
 * Step 2: unescape single argument
 */
private string unescape(string arg)
{
    string result;
    result.reserve(arg.length);

    if (arg.startsWith(`"`))
        arg = arg[1 .. $];
    if (arg.endsWith(`"`) && (arg.length == 1 || arg[$ - 2] != '\\'))
        arg = arg[0 .. $ - 1];

    for (size_t i = 0; i < arg.length; i++)
    {
        if (arg[i] == '\\')
        {
            result ~= parseEscapeSequence(arg, i);
        }
        else
        {
            result ~= arg[i];
        }
    }
    return result;
}

unittest
{
    assert(unescape(`\`) == `\`);
    assert(unescape(`\\`) == `\\`);
    assert(unescape(`\\\`) == `\\\`);
    assert(unescape(`\\\\`) == `\\\\`);

    assert(unescape(` \ `) == ` \ `);
    assert(unescape(` \\ `) == ` \\ `);
    assert(unescape(` \\\ `) == ` \\\ `);
    assert(unescape(` \\\\ `) == ` \\\\ `);

    assert(unescape(`\"`) == `"`);
    assert(unescape(`\\"`) == `\"`);
    assert(unescape(`\\\"`) == `\"`);
    assert(unescape(`\\\\"`) == `\\"`);

    assert(unescape(` \" `) == ` " `);
    assert(unescape(` \\" `) == ` \" `);
    assert(unescape(` \\\" `) == ` \" `);
    assert(unescape(` \\\\" `) == ` \\" `);

    assert(unescape(`"`) == ``);
    assert(unescape(`""`) == ``);
    assert(unescape(`"abc"`) == `abc`);
    assert(unescape(`\"abc\"`) == `"abc"`);
    assert(unescape(`"a\b"`) == `a\b`);
    assert(unescape(`"a\\b"`) == `a\\b`);
    assert(unescape(`"a\\\b"`) == `a\\\b`);
    assert(unescape(`"a\"b"`) == `a"b`);
    assert(unescape(`"a\\"b"`) == `a\"b`);
    assert(unescape(`"a\\\"b"`) == `a\"b`);
}

/**
 * Parse a backslash / quotation mark sequence as described on
 * https://msdn.microsoft.com/en-us/library/windows/desktop/bb776391%28v=vs.85%29.aspx
 *
 * 2n backslashes followed by a quotation mark produce n backslashes followed by a quotation mark.
 * (2n) + 1 backslashes followed by a quotation mark again produce n backslashes followed by a quotation mark.
 * n backslashes not followed by a quotation mark simply produce n backslashes.
 */
private string parseEscapeSequence(string content, ref size_t position)
{
    import std.range : repeat;

    size_t num = 0;
    while (position < content.length)
    {
        if (content[position] == '"')
            return '\\'.repeat(num / 2).array().idup ~ "\"";
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
    assert(r"\".parseEscapeSequence(idx) == r"\" && idx == 0);
    idx = 0;
    assert(r"\ ".parseEscapeSequence(idx) == r"\" && idx == 0);
    idx = 0;
    assert(r"\\ ".parseEscapeSequence(idx) == r"\\" && idx == 1);
    idx = 0;
    assert(r"\\\ ".parseEscapeSequence(idx) == r"\\\" && idx == 2);
    idx = 0;
    assert(r"\\\".parseEscapeSequence(idx) == r"\\\" && idx == 2);

    idx = 0;
    assert(`\"`.parseEscapeSequence(idx) == `"` && idx == 1);
    idx = 0;
    assert(`\" `.parseEscapeSequence(idx) == `"` && idx == 1);
    idx = 0;
    assert(`\\" `.parseEscapeSequence(idx) == `\"` && idx == 2);
    idx = 0;
    assert(`\\\" `.parseEscapeSequence(idx) == `\"` && idx == 3);
    idx = 0;
    assert(`\\\" `.parseEscapeSequence(idx) == `\"` && idx == 3);
    idx = 0;
    assert(`\\\\" `.parseEscapeSequence(idx) == `\\"` && idx == 4);
}
