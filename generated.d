// Generate types and variables from DMD cli options.
module gdmd.generated;

import gdmd.ctfeutils;
import gdmd.options;
import dmd.cli : Usage;

@safe pure nothrow:

// Undocumented and backwards-compatible dmd options
private enum UndocumentedOptions = [
    "Dd=<directory>",   // -Dd=
    "Df=<filename>",    // -Df=
    "Hd<directory>",    // -Hd
    "Hf<filename>",     // -Hf
    "I<directory>",     // -I
    "J<directory>",     // -J
    "L<linkerflag>",    // -L
    "Xf<filename>",     // -Xf
    "Xi=<id>",          // -Xi=
    "dip1000",          // -dip1000
    "dip1008",          // -dip1008
    "dip25",            // -dip25
    "fPIE",             // -fPIE
    "h",                // -h
    "o <srcfile>",      // -o
    "od<directory>",    // -od
    "of<filename>",     // -of
    "vcg-ast",          // -vcg-ast

    // Runtime library options
    "-DRT-<option>",    // --DRT-...

    // Internal DMD options that have no effect
    "-b",               // --b
    "-c",               // --c
    "-f",               // --f
    "-r",               // --r
    "-x",               // --x
    "-y",               // --y
    "multiobj",         // -multiobj
    "nofloat",          // -nofloat
    "quiet",            // --quiet
];

// Extract an option flag (`-Dd`) from a usage string (`Dd<directory>`).
private string parseFlag(string flag)
{
    // Any of the characters `[< ` imply the end of an option flag.
    auto idx = flag.indexOfAny("[< ");
    if (idx == -1)
    {
        // Not found, look for common option/argument separator `=`.
        idx = flag.indexOfAny("=");
        if (idx > -1)
            idx++;
    }

    // Prepend the `-` part of the argument flag.
    return "-" ~ flag[0 .. idx > -1 ? idx : $];
}

private // unittest
{
    static assert(parseFlag("debug") == "-debug");
    static assert(parseFlag("debug=<level>") == "-debug=");
    static assert(parseFlag("i[=pattern]") == "-i");
    static assert(parseFlag("run <srcfile>") == "-run");
    static assert(parseFlag("preview=?") == "-preview=");
    static assert(parseFlag("-help") == "--help");
}

// From an option flag (`-Dd`) convert to an enum value (`_Dd`).
private string flagToEnum(string flag)
{
    // Use `_` in place of non-alphanumerics.
    string ret;
    foreach (c; flag)
        ret ~= c.isAlphaNum() ? c : '_';
    return ret;
}

private // unittest
{
    static assert(flagToEnum("-debug") == "_debug");
    static assert(flagToEnum("-debug=") == "_debug_");
    static assert(flagToEnum("--help") == "__help");
}

// Sort all dmd.cli.Usage flags by ASCII collation.
private string[] getSortedFlags()
{
    string[] flags;

    foreach (option; Usage.options)
    {
        bool inserted;
        foreach (idx, flag; flags)
        {
            if (option.flag < flag)
            {
                // Insert option before the current `idx` position.
                flags = flags[0 .. idx] ~ option.flag ~ flags[idx .. $];
                inserted = true;
                break;
            }
        }
        // Append option on the end if not yet added.
        if (!inserted)
            flags ~= option.flag;
    }

    // Repeat the same again for all undocumented flags.
    foreach (option; UndocumentedOptions)
    {
        bool inserted;
        foreach (idx, flag; flags)
        {
            if (option < flag)
            {
                // Insert option before the current `idx` position.
                flags = flags[0 .. idx] ~ option ~ flags[idx .. $];
                inserted = true;
                break;
            }
        }
        // Append option on the end if not yet added.
        if (!inserted)
            flags ~= option;
    }
    return flags;
}

private // unittest
{
    bool isSorted(string[] array)
    {
        if (!array.length)
            return true;

        string[] next = array[1 .. $];
        for (size_t i = 0; i < next.length; i++)
        {
            if (array[i] < next[i])
                continue;
            return false;
        }
        return true;
    }

    static assert(isSorted(getSortedFlags()));
}

// From a Features[] array, generate a spec string.
private string generateFeatureSpec(T)(T features)
{
    string spec = `[all`;
    foreach (feature; features)
        spec ~= `|` ~ feature.name;
    spec ~= `]`;
    return spec;
}

private // unittest
{
    struct Test { string name; }
    static assert(generateFeatureSpec(cast(Test[])[]) == "[all]");
    static assert(generateFeatureSpec([Test("dip25"), Test("dip1000")]) ==
                  "[all|dip25|dip1000]");
}

// Generates:
//  enum string[][] OptionStrings = [
//      ["-allinst"],
//      ["-boundscheck=", "[on|safeonly|off]"],
//      ["-c"],
//      ["-conf=", "<filename>"],
//      ...
//  ];
private string generateOptionStrings()
{
    string ret;

    ret ~= "enum string[][] OptionStrings = [\n";

    string[] optionflags = getSortedFlags();
    for (size_t i = 0; i < optionflags.length; i++)
    {
        string opt = optionflags[i];
        string flag = parseFlag(opt);

        // Some options have `[=<...>]`, we need to generate two enum entries
        // for them to distinguish between the flag with and without argument.
        auto idx = opt.indexOfAny("[");
        if (idx > -1 && opt[idx] == '[' && opt[idx + 1] == '=')
        {
            // Add two entries for `-opt`, and `-opt=`.
            ret ~= "\t" ~ `["` ~ flag ~ `"],` ~ "\n";
            ret ~= "\t" ~ `["` ~ flag ~ `="`;
            // Include spec for the argument, remove the `=` part as that
            // has been moved into the option flag itself.
            if (flag.length < opt.length)
            {
                ret ~= `, "` ~ opt[flag.length - 1 .. flag.length];
                ret ~= opt[flag.length + 1 .. $] ~ `"`;
            }
            ret ~= "],\n";
        }
        else
        {
            // Add single entry for the option.
            ret ~= "\t" ~ `["` ~ flag ~ `"`;
            // Include spec for the argument.
            if (flag.length < opt.length)
            {
                string spec;

                // Some flags have their specs in a Feature array.
                if (flag == "-preview=")
                    spec = generateFeatureSpec(Usage.previews);
                else if (flag == "-revert=")
                    spec = generateFeatureSpec(Usage.reverts);
                else if (flag == "-transition=")
                    spec = generateFeatureSpec(Usage.transitions);
                else
                    spec = opt[flag.length - 1 .. $];

                ret ~= `, "`;

                // The Options array sometimes has multiple entries for the
                // same option, such as `-debug=<level>` and `-debug=<ident>`.
                // Be mindful to join these options together.
                if (i + 1 < optionflags.length)
                {
                    string nextopt = optionflags[i + 1];
                    string nextflag = parseFlag(nextopt);
                    if (flag == nextflag)
                    {
                        spec = `[` ~ spec;
                        while (flag == nextflag)
                        {
                            spec ~= `|`;
                            if (nextopt[nextflag.length - 1] == '[')
                                spec ~= nextopt[nextflag.length .. $ - 1];
                            else
                                spec ~= nextopt[nextflag.length - 1 .. $];
                            i++;
                            nextopt = optionflags[i + 1];
                            nextflag = parseFlag(nextopt);
                        }
                        //i++;
                        spec ~= `]`;
                    }
                }
                ret ~= spec ~ `"`;
            }
            ret ~= "],\n";
        }
    }
    ret ~= "];\n";

    return ret;
}
mixin(generateOptionStrings());

// Generates:
//  enum Option {
//      _allinst,   // -allinst
//      _c,         // -c
//      _debug,     // -debug
//      _debug_,    // -debug=
//      ...
//      max,
//      input_file, // file.d
//  }
private string generateOptionEnum()
{
    string ret;

    ret ~= "enum Option {\n";
    foreach (opt; OptionStrings)
    {
        auto val = flagToEnum(opt[0]);

        ret ~= "\t" ~ val;
        // Add comment for enum member documenting which option it is.
        debug ret ~= "\t/* " ~ opt[0 .. val.length - 1] ~ " */";
        ret ~= ",\n";
    }

    // Add entry to mark end of command-line arguments.
    ret ~= "\tmax,\n";

    // Entry for input sources.
    ret ~= "\tinput_file,\n";

    // Extra commandline options specific for gdmd.
    ret ~= "\tgcc_flag,\n";       // -f...
    ret ~= "\tmachine_flag,\n";   // -m...
    ret ~= "\twarning_flag,\n";   // -W...
    ret ~= "\tgdmd_verbose,\n";   // -vdmd

    ret ~= "}";

    return ret;
}
mixin(generateOptionEnum());

// Generates:
//  enum Flag[Option.max] OptionFlags = [
//      Flag("-allinst", false, false, []),
//      Flag("-c", false, false, []),
//      Flag("-debug", false, false, []),
//      Flag("-debug=", true, false, []),
//      ...
//  ];
private string generateOptionFlags()
{
    string ret;

    ret ~= `enum Flag[` ~ Option.max.intToString() ~ "] OptionFlags = [\n";
    foreach (idx, opt; OptionStrings)
    {
        auto flag = opt[0];
        auto argspec = opt.length == 2 ? opt[1] : null;

        // flag = "--flag"
        ret ~= `Flag("` ~ flag ~ `"`;
        if (argspec)
        {
            // argument = true
            ret ~= `, true, `;

            // separated = true|false
            if (argspec[0] == ' ')
            {
                ret ~= `true, `;
                argspec = argspec[1 .. $];
            }
            else
                ret ~= `false, `;

            // overlapping = idx|-1
            int overlapped = -1;
            foreach_reverse (pidx; 0 .. idx)
            {
                if (OptionStrings[pidx][0][1] != flag[1])
                    break;
                if (OptionStrings[pidx].length != 2)
                    continue;
                auto prevflag = OptionStrings[pidx][0];
                auto prevspec = OptionStrings[pidx][1];
                if (prevflag.length < flag.length && prevspec[0] != ' ' &&
                    flag[0 .. prevflag.length] == prevflag)
                {
                    overlapped = cast(int)pidx;
                    break;
                }
            }
            ret ~= (overlapped >= 0 ? overlapped.intToString() : `-1`);
            ret ~= `, `;

            // values = [ ... ]
            string[] values = extractVariants(argspec);
            ret ~= `[`;
            foreach (value; values)
                ret ~= `"` ~ value ~ `",`;
            ret ~= `]`;
        }
        ret ~= `),` ~ "\n";
    }
    ret ~= "];\n";

    return ret;
}
mixin(generateOptionFlags());
