// Helper functions for driver run-time.
module gdmd.rtutils;

import gdmd.options;

@safe nothrow @nogc:
package:

// Returns true iff the string `str` ends with `endstr`.
bool endsWith(string str, string endstr)
{
    if (!str.length || endstr.length > str.length)
        return false;

    return str[$ - endstr.length .. $] == endstr;
}

private // unittest
{
    static assert( "test.d".endsWith(".d"));
    static assert(!"test.d".endsWith(".c"));
    static assert(!"test".endsWith(".json"));
    static assert("empty".endsWith(""));
    static assert(!"".endsWith(""));
}

// Open browser to the DMD man-page.
void openManPage() @trusted
{
    import dmd.root.man;
    browse("https://dlang.org/dmd.html");
}

// Returns true iff option argument `value` is a help string `[help|h|?]`.
bool checkHelpUsage(string value)
{
    switch (value)
    {
        case "help":
        case "h":
        case "?":
            return true;

        default:
            return false;
    }
}

private // unittest
{
    static assert(checkHelpUsage("help") == true);
    static assert(checkHelpUsage("h") == true);
    static assert(checkHelpUsage("?") == true);
    static assert(checkHelpUsage("H") == false);
}

// Returns true iff option argument `value` is found in the list of allowed
// values for the switch `code`.
bool checkValue(Option code, string value)
{
    auto option = OptionFlags[code];
    foreach (arg; option.arguments)
    {
        // If one of the permitted values is `*`, then any value is accepted.
        if (arg.length == 1 && arg[0] == '*')
           return true;

        if (value == arg)
            return true;
    }
    return false;
}

private // unittest
{
    // Tests may fail if generated options ever change.
    static assert(checkValue(Option._J, "hello") == true);
    static assert(checkValue(Option._profile_, "gc") == true);
    static assert(checkValue(Option._profile_, "off") == false);
}

// Search OptionFlags for a match for the argument `arg`.
// Uses binary search to traverse the OptionFlags array.
Option matchOption(string arg, out string value)
{
    int low = Option.min;
    int high = Option.max - 1;

    // Treat arguments that don't start with `-` as source files.
    // Just `-` on its own means use stdin for input.
    if (!arg.length || arg[0] != '-' || arg.length == 1)
        return Option.input_file;

    while (low <= high)
    {
        int mid = (low + high) >> 1;
        auto option = &OptionFlags[mid];
        int cond;

        // There will be no match if the argument is shorter than the
        // current flag, so only use comparison check.
        if (arg.length < option.flag.length)
            cond = (option.flag < arg) ? -1 : 1;
        else if (!option.argument || option.separated)
            cond = (option.flag == arg) ? 0 : (option.flag < arg) ? -1 : 1;
        else
        {
            // Joined options only need to check whether a slice of the
            // argument matches.  The rest of the argument is the value.
            if (option.flag == arg[0 .. option.flag.length])
            {
                cond = (arg.length == option.flag.length ||
                        arg[option.flag.length] != '=') ? 0 : -1;
            }
            else
                cond = (option.flag < arg) ? -1 : 1;

            if (cond != 0 && option.overlapping >= 0)
            {
                // Option is overlapping another, check each option flag,
                // preferring the strongest match.
                int nextmid = option.overlapping;

                while (nextmid != -1)
                {
                    auto nextoption = &OptionFlags[nextmid];
                    if (cond == 0)
                        break;
                    if (nextoption.flag == arg[0 .. nextoption.flag.length] &&
                        (arg.length == nextoption.flag.length ||
                         arg[nextoption.flag.length] != '='))
                    {
                        cond = 0;
                        mid = nextmid;
                        option = nextoption;
                    }
                    nextmid = nextoption.overlapping;
                }
            }
        }

        if (cond > 0)
            high = mid - 1;
        else if (cond < 0)
            low = mid + 1;
        else
        {
            // Matched the option.
            assert(mid >= Option.min && mid <= Option.max);
            if (option.argument)
                value = arg[option.flag.length .. $];
            return cast(Option)mid;
        }
    }
    // No match, test for gdmd-specific options.
    if (arg.length > 2)
    {
        // arg[0] has already been tested for `-`.
        if (arg[1] == 'f')
        {
            // Match any front-end option starting with `-f`.
            return Option.gcc_flag;
        }
        else if (arg[1] == 'm')
        {
            // Match any back-end option starting with `-m`.
            return Option.machine_flag;
        }
        else if (arg[1] == 'W')
        {
            // Match any warning option starting with `-W`.
            return Option.warning_flag;
        }
        else if (arg == "-vdmd")
        {
            // Print commands executed by this program.
            return Option.gdmd_verbose;
        }
    }
    return Option.max;
}

private // unittest
{
    Option matchOptionCTFE(string arg)
    {
        string value;
        assert(__ctfe);
        return matchOption(arg, value);
    }

    static assert(()
    {
        foreach (flag, option; OptionFlags)
            assert(matchOptionCTFE(option.flag) == flag);
        return true;
    }());
    static assert(matchOptionCTFE("-flto") == Option.gcc_flag);
    static assert(matchOptionCTFE("-msoft-float") == Option.machine_flag);
    static assert(matchOptionCTFE("-Wextra") == Option.warning_flag);
    static assert(matchOptionCTFE("-vdmd") == Option.gdmd_verbose);
}
