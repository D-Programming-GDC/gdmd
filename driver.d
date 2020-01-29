module gdmd.driver;

import dmd.cli;
import dmd.root.filename;
import dmd.root.string;
import dmd.root.response;

import gdmd.options;
import gdmd.errors;
import gdmd.rtutils;
import core.stdc.stdio;

package:

// Print command usage to console.
private void printUsage()
{
    auto help = CLIUsage.usage;
    printf("
Documentation: https://dlang.org/
               https://gdcproject.org/
Usage:
  gdmd [<option>...] <file>...
  gdmd [<option>...] -run <file> [<arg>...]

Where:
  <file>            D source file
  <arg>             Argument to pass when running the resulting program

<option>:
  -f...             pass a -f... option to gdc
  -m...             pass a -m... option to gdc
  -W...             pass a -W... option to gdc
  -vdmd             print commands ran by this program

  @<cmdfile>        read arguments from cmdfile
%.*s", cast(int)help.length, help.ptr);
}

// Print supplied usage text `help` to console.
private void printHelpUsage(string help) nothrow @nogc
{
    printf("%.*s", cast(int)help.length, help.ptr);
}

// Handles DMD specific option identified by `code`.  The original argument
// is stored in `arg`, and extracted argument value in `value`.  Program
// option data is referenced by `params`.  Returns true if errors found.
private bool handleOption(Option code, string arg, string value,
                          ref OptionData params)
{
    // Append gdc-style option `replace` if the dmd-style option `arg` matches
    // `match`.  If `toggle`, also check for `=off`/`=on`.
    bool translate(in string arg, in string match, in string replace,
                   bool toggle = false) nothrow
    {
        if (arg.length >= match.length && arg[0 .. match.length] == match &&
            (toggle || arg.length == match.length))
        {
            if (!toggle)
                params.args.push(("-f" ~ replace).ptr);
            else
            {
                params.args.push((arg[match.length .. $] == "=off")
                                 ? ("-fno-" ~ replace).ptr : ("-f" ~ replace).ptr);
            }
            return true;
        }
        return false;
    }

    // Common code for options with CLIUsage help strings.
    static string generateUsageChecks(string check) nothrow
    {
        return `
            if (!code.checkValue(value))
            {
                if (!value.length)
                    missingArgument(arg);
                else
                    invalidArgument(arg);
                printHelpUsage(CLIUsage.` ~ check ~ `);
                return true;
            }
            else if (checkHelpUsage(value))
            {
                printHelpUsage(CLIUsage.` ~ check ~ `);
                return false;
            }
        `;
    }

    // Common code for checking non-zero length argument value.
    static string enforceValue() nothrow @nogc
    {
        return q{
            if (!value.length)
                goto Lmissing;
        };
    }

    switch (code)
    {
        // Internal dmd options.
        case Option.__DRT_:
        case Option.__b:
        case Option.__c:
        case Option.__f:
        case Option.__r:
        case Option.__x:
        case Option.__y:
        case Option._lowmem:    // GC is enabled by default in gdc.
        case Option._mscrtlib_: // MinGW always links against msvcrt.
        case Option._multiobj:
        case Option._nofloat:
        case Option._quiet:
            // Silently ignored.
            break;

        // Options that have equivalence in gdc.
        case Option.__version:
        case Option._c:
        case Option._debuglib_:
        case Option._defaultlib_:
        case Option._fPIC:
        case Option._fPIE:
        case Option._shared:
        case Option._v:
            params.args.push(arg.ptr);
            break;

        case Option._mcpu_:
            mixin(enforceValue());
            params.args.push(arg.ptr);
            break;

        case Option._Xcc_:
            mixin(enforceValue());
            params.args.push(value.ptr);
            break;

        // Options for generating Ddoc.
        case Option._D:
            params.args.push("-fdoc");
            break;

        case Option._Dd:
        case Option._Dd_:
            mixin(enforceValue());
            params.args.push(("-fdoc-dir=" ~ value).ptr);
            break;

        case Option._Df:
        case Option._Df_:
            mixin(enforceValue());
            params.args.push(("-fdoc-file=" ~ value).ptr);
            break;

        // Options for generating D headers.
        case Option._H:
            params.args.push(arg.ptr);
            break;

        case Option._Hd:
        case Option._Hd_:
            mixin(enforceValue());
            params.args.push("-Hd");
            params.args.push(value.ptr);
            break;

        case Option._Hf:
        case Option._Hf_:
            mixin(enforceValue());
            params.args.push("-Hf");
            params.args.push(value.ptr);
            break;

        // Options for generating JSON files.
        case Option._X:
            params.args.push(arg.ptr);
            break;

        case Option._Xf:
        case Option._Xf_:
            mixin(enforceValue());
            params.args.push("-Xf");
            params.args.push(value.ptr);
            break;

        // Module and import search paths.
        case Option._I:
        case Option._I_:
            mixin(enforceValue());
            params.args.push("-I");
            params.args.push(value.ptr);
            break;

        case Option._J:
        case Option._J_:
            mixin(enforceValue());
            params.args.push("-J");
            params.args.push(value.ptr);
            break;

        // Pass flags to the linker.
        case Option._L:
        case Option._L_:
            mixin(enforceValue());
            params.args.push(("-Wl," ~ value).ptr);
            break;

        // Code generation options.
        case Option._O:
            params.args.push("-O2");
            break;

        case Option._allinst:
            params.args.push("-fall-instantiations");
            break;

        case Option._betterC:
            params.args.push("-fno-druntime");
            break;

        case Option._boundscheck_:
            if (!code.checkValue(value))
            {
                mixin(enforceValue());
                invalidArgument(arg,
                    "Only `on`, `safeonly` or `off` are allowed " ~
                    "for `-boundscheck`");
                return true;
            }
            else
                params.args.push(("-fbounds-check=" ~ value).ptr);
            break;

        case Option._check_:
            mixin(generateUsageChecks("checkUsage"));
            if (!translate(value, "invariant", "invariants", true) &&
                !translate(value, "assert", "assert", true) &&
                !translate(value, "bounds", "bounds-check", true) &&
                !translate(value, "switch", "switch-errors", true) &&
                !translate(value, "out", "postconditions", true) &&
                !translate(value, "in", "preconditions", true))
            {
                unimplementedSwitch(arg);
            }
            break;

        case Option._checkaction_:
            mixin(generateUsageChecks("checkActionUsage"));
            if (!translate(value, "D", "checkaction=throw") &&
                !translate(value, "C", "checkaction=halt") &&
                !translate(value, "halt", "checkaction=halt") &&
                !translate(value, "context", "checkaction=context"))
            {
                unimplementedSwitch(arg);
            }
            break;

        case Option._color:
            params.args.push("-fdiagnostics-color");
            break;

        case Option._color_:
            if (!code.checkValue(value))
            {
                mixin(enforceValue());
                invalidArgument(arg,
                    "Available options for `-color` are `on`, " ~
                    "`off` and `auto`");
                return true;
            }
            else if (!translate(value, "on", "diagnostics-color=always") &&
                     !translate(value, "off", "diagnostics-color=never") &&
                     !translate(value, "auto", "diagnostics-color=auto"))
            {
                unimplementedSwitch(arg);
            }
            break;

        case Option._cov:
        case Option._cov_:
            params.args.push("-fprofile-arcs");
            params.args.push("-ftest-coverage");
            break;

        case Option._d:
            params.args.push("-Wno-deprecated");
            break;

        case Option._de:
            params.args.push("-Wdeprecated");
            params.args.push("-Werror");
            break;

        case Option._dw:
            params.args.push("-Wdeprecated");
            break;

        case Option._debug:
            params.args.push("-fdebug");
            break;

        case Option._debug_:
            mixin(enforceValue());
            params.args.push(("-fdebug=" ~ value).ptr);
            break;

        case Option._dip1000:
            params.args.push("-fpreview=dip25");
            params.args.push("-fpreview=dip1000");
            break;

        case Option._dip1008:
            params.args.push("-fpreview=dip1008");
            break;

        case Option._dip25:
            params.args.push("-fpreview=dip25");
            break;

        case Option._extern_std_:
            mixin(generateUsageChecks("externStdUsage"));
            if (checkHelpUsage(value))
            {
                printHelpUsage(CLIUsage.externStdUsage);
                return false;
            }
            else if (!translate(value, "c++98", "extern-std=c++98") &&
                     !translate(value, "c++11", "extern-std=c++11") &&
                     !translate(value, "c++14", "extern-std=c++14") &&
                     !translate(value, "c++17", "extern-std=c++17"))
            {
                if (!value.length)
                    missingArgument(arg);
                else
                    invalidArgument(arg);
                printHelpUsage(CLIUsage.externStdUsage);
                return true;
            }
            break;

        case Option._g:
        case Option._gf:
            params.args.push("-g");
            break;

        case Option._gs:
            params.args.push("-fno-omit-frame-pointer");
            break;

        case Option._gx:
            params.args.push("-fstack-protector");
            break;

        case Option._ignore:
            params.args.push("-fignore-unknown-pragmas");
            break;

        case Option._inline:
            params.args.push("-finline-functions");
            break;

        case Option._lib:
            params.lib = true;
            break;

        case Option._m32:
        case Option._m32mscoff:
            params.args.push("-m32");
            break;

        case Option._m64:
            params.args.push("-m64");
            break;

        case Option._main:
            params.args.push("-fmain");
            break;

        case Option._map:
            params.map = true;
            break;

        case Option._mixin_:
            mixin(enforceValue());
            params.args.push(("-fsave-mixins=" ~ value).ptr);
            break;

        case Option._mv_:
            mixin(enforceValue());
            params.args.push(("-fmodule-file=" ~ value).ptr);
            break;

        case Option._noboundscheck:
            params.args.push("-fno-bounds-check");
            break;

        case Option._o:
            unsupportedSwitch(arg, "use `-of` or `-od`");
            break;

        case Option._o_:
            params.args.push("-fsyntax-only");
            break;

        case Option._od:
        case Option._od_:
            mixin(enforceValue());
            params.objdir = value;
            break;

        case Option._of:
        case Option._of_:
            mixin(enforceValue());
            params.objname = value;
            break;

        case Option._op:
            params.preservePaths = true;
            break;

        case Option._preview_:
            mixin(generateUsageChecks("previewUsage"));
            if (!translate(value, "all", "preview=all") &&
                !translate(value, "dip25", "preview=dip25") &&
                !translate(value, "dip1000", "preview=dip1000") &&
                !translate(value, "dip1008", "preview=dip1008") &&
                !translate(value, "dip1021", "preview=dip1021") &&
                !translate(value, "fieldwise", "preview=fieldwise") &&
                !translate(value, "markdown", "preview=markdown") &&
                !translate(value, "fixAliasThis", "preview=fixaliasthis") &&
                !translate(value, "intpromote", "preview=intpromote") &&
                !translate(value, "dtorfields", "preview=dtorfields") &&
                !translate(value, "rvaluerefparam", "preview=rvaluerefparam") &&
                !translate(value, "nosharedaccess", "nosharedaccess"))
            {
                unimplementedSwitch(arg);
            }
            break;

        case Option._profile:
            params.args.push("-pg");
            break;

        case Option._release:
            params.args.push("-frelease");
            break;

        case Option._revert_:
            mixin(generateUsageChecks("revertUsage"));
            if (!translate(value, "all", "revert=all") &&
                !translate(value, "dip25", "revert=dip25"))
            {
                unimplementedSwitch(arg);
            }
            break;

        case Option._transition_:
            mixin(generateUsageChecks("transitionUsage"));
            if (!translate(value, "all", "transition=all") &&
                !translate(value, "field", "transition=field") &&
                !translate(value, "complex", "transition=complex") &&
                !translate(value, "tls", "transition=tls") &&
                !translate(value, "vmarkdown", "transition=vmarkdown"))
            {
                unimplementedSwitch(arg);
            }
            break;

        case Option._unittest:
            params.args.push("-funittest");
            break;

        case Option._vcg_ast:
            params.args.push("-fdump-d-original");
            break;

        case Option._vcolumns:
            params.args.push("-fshow-column");
            break;

        case Option._verrors_:
            mixin(enforceValue());
            switch (value)
            {
                case "context":
                    params.args.push("-fdiagnostics-show-caret");
                    break;

                case "spec":
                    params.args.push("-Wspeculative");
                    break;

                default:
                    params.args.push(("-fmax-errors=" ~ value).ptr);
                    break;
            }
            break;

        case Option._version_:
            mixin(enforceValue());
            params.args.push(("-fversion=" ~ value).ptr);
            break;

        case Option._vgc:
            params.args.push("-ftransition=nogc");
            break;

        case Option._vtls:
            params.args.push("-ftransition=tls");
            break;

        case Option._w:
            params.args.push("-Werror");
            break;

        case Option._wi:
            params.args.push("-Wall");
            break;

        case Option._conf_:
            mixin(enforceValue());
            params.inifilename = value;
            break;

        // No longer supported switches.
        case Option._deps:
        case Option._deps_:
        // Options not supported by gdc.
        case Option._Xi_:
        case Option._i:
        case Option._i_:
        case Option._profile_:
            unimplementedSwitch(arg);
            break;

        default:
            unrecognizedSwitch(arg);
            return true;

        Lmissing:
            missingArgument(arg);
            return true;
    }
    return false;
}

// Deal with any options after reading all arguments on the command line.
// All files seen on the command line are in `sources` are all files seen 
// Returns true if an error occurred.
bool postOptions(in Strings* sources, ref OptionData params)
{
    // First input file with a `.d` extension.
    string first_input_file;
    // What name argument to use for mapfile.
    string mapfile;

    // Inspect all digested sources.
    foreach (source; *sources)
    {
        string dsource = cast(string)source.toDString();
        // -x is required when input is from standard input.
        if (dsource == "-")
            params.args.push("-xd");

        if (dsource.endsWith(FileType.ddoc))
        {
            params.args.push(("-fdoc-inc=" ~ dsource).ptr);
            continue;
        }
        if (dsource.endsWith(FileType.json))
        {
            params.args.push("-Xf");
            params.args.push(source);
            continue;
        }
        if (dsource.endsWith(FileType.map))
        {
            mapfile = dsource;
            continue;
        }
        if (dsource.endsWith(FileType.exe))
        {
            params.objname = dsource;
            continue;
        }
        if (!first_input_file.length && dsource.endsWith(FileType.mars))
            first_input_file = dsource;
            
        params.args.push(source);
    }

    if (!first_input_file.length)
    {
        printUsage();
        return true;
    }

    // 
    if (params.objname && params.objdir)
    {
        auto name = FileName.name(params.objname);
        params.args.push("-o");
        params.args.push(FileName.combine(params.objdir, name).ptr);
    }

    // Handle `-map` linker option.
    if (params.map || mapfile.length)
    {
        if (!mapfile.length)
            mapfile = first_input_file[0 .. $ - FileType.mars.length];

        version (OSX)
            params.args.push(("-Wl,-map," ~ mapfile).ptr);
        else
            params.args.push(("-Wl,-Map," ~ mapfile).ptr);
    }

    return false;
}

// Parse all dmd-style command line arguments, converting them to gdc-style
// where necessary.  Returns true if errors in command line.
bool parseArgs(size_t argc, const(char)** argv, out OptionData params) //nothrow
{
    Strings sources;

    // Check for malformed input
    if (argc < 1 || !argv)
    {
    Largs:
        malformedArguments();
        return true;
    }

    // Convert argv into arguments[] for easier handling
    Strings arguments = Strings(argc);
    for (size_t i = 0; i < argc; i++)
    {
        if (!argv[i])
            goto Largs;
        arguments[i] = argv[i];
    }

    // Expand response files
    if (!responseExpand(arguments))
    {
        missingResponseFile();
        return true;
    }

    // Parse and translate all arguments.
Lforeach:
    foreach (idx, arg; arguments[1 .. $])
    {
        string in_arg = cast(string)arg.toDString();
        string value;
        auto code = matchOption(in_arg, value);

        switch (code)
        {
            // DMD command line arguments that require early exit.
            case Option.__help:
            case Option._h:
                printUsage();
                return false;

            case Option._man:
                openManPage();
                return false;

            case Option._run:
                params.run = true;
                if (idx + 1 >= arguments.length)
                {
                    missingArgument(in_arg);
                    return true;
                }
                // Get the source file argument for `-run`.
                auto source = arguments[idx + 1];
                string dsource = cast(string)source.toDString();
                if (!dsource.endsWith(FileType.mars) &&
                    !dsource.endsWith(FileType.hdr) &&
                    dsource != "-")
                {
                    missingArgument(in_arg,
                        "`-run` must be followed by a source file, not " ~
                        "`" ~ dsource ~ "`");
                    return true;
                }
                // Consume all other arguments on the command line that
                // follow and break out of the loop.
                sources.push(source);
                foreach (runarg; arguments[idx + 2 .. $])
                    params.runargs.push(runarg);
                break Lforeach;

            // Other kinds of command line arguments.
            case Option.input_file:
                sources.push(arg);
                break;

            case Option.gcc_flag:
            case Option.machine_flag:
            case Option.warning_flag:
                params.args.push(arg);
                break;

            case Option.gdmd_verbose:
                params.verbose = true;
                break;

            // All other DMD command line arguments.
            default:
                if (handleOption(code, in_arg, value, params))
                    return true;
                break;
        }
    }
    if (postOptions(&sources, params))
        return true;

    return false;
}
