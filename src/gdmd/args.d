/**
 * Handles command line argument parsing.
 */
module gdmd.args;

import std.array, std.algorithm, std.stdio, std.string, std.path, std.typecons;
import gdmd.exception, gdmd.response;

/**
 * Prints command-line usage.
 */
void printUsage(uint major, uint minor, string gdcInfo)
{
    writefln("GDMD D Compiler %s.%03d using", major, minor);
    write(gdcInfo);

    write(q"EOF
Documentation: http://dlang.org/
               http://www.gdcproject.org/
Usage:
  gdmd files.d ... { -switch }

  files.d        D source files
  @cmdfile       read arguments from cmdfile

  -gdc=value     path to or name of gdc executable to use
  -ar=value      path to or name of ar executable to use
  -vdmd          print commands run by this script
  -q=arg1        pass arg1 to gdc

  -allinst       generate code for all template instantiations
  -c             do not link
  -color[=on|off]   force colored console output on or off
  -cov           do code coverage analysis
  -cov=nnn       require at least nnn%% code coverage
  -D             generate documentation
  -Dddocdir      write documentation file to docdir directory
  -Dffilename    write documentation file to filename
  -d             silently allow deprecated features
  -dw            show use of deprecated features as warnings (default)
  -de            show use of deprecated features as errors (halt compilation)
  -debug         compile in debug code
  -debug=level   compile in debug code <= level
  -debug=ident   compile in debug code identified by ident
  -debuglib=name    set symbolic debug library to name
  -defaultlib=name  set default library to name
  -deps          print module dependencies (imports/file/version/debug/lib)
  -deps=filename write module dependencies to filename (only imports)
  -fPIC          generate position independent code
  -g             add symbolic debug info
  -gc            add symbolic debug info, optimize for non D debuggers
  -gs            always emit stack frame
  -gx            add stack stomp code
  -H             generate 'header' file
  -Hddirectory   write 'header' file to directory
  -Hffilename    write 'header' file to filename
  --help         print help
  -Ipath         where to look for imports
  -ignore        ignore unsupported pragmas
  -inline        do function inlining
  -Jpath         where to look for string imports
  -Llinkerflag   pass linkerflag to link
  -lib           generate library rather than object files
  -m32           generate 32 bit code
  -m64           generate 64 bit code
  -main          add default main() (e.g. for unittesting)
  -man           open web browser on manual page
  -map           generate linker .map file
  -boundscheck=[on|safeonly|off]   bounds checks on, in @safe only, or off
  -noboundscheck no array bounds checking (deprecated, use -boundscheck=off)
  -O             optimize
  -o-            do not write object file
  -odobjdir      write object & library files to directory objdir
  -offilename    name output file to filename
  -op            preserve source path for output files
  -profile       profile runtime performance of generated code
  -property      enforce property syntax
  -release       compile release version
  -run srcfile args...   run resulting program, passing args
  -shared        generate shared library (DLL)
  -transition=id show additional info about language change identified by 'id'
  -transition=?  list all language changes
  -unittest      compile in unit tests
  -v             verbose
  -vcolumns      print character (column) numbers in diagnostics
  -version=level compile in version code >= level
  -version=ident compile in version code identified by ident
  -vtls          list all variables going into thread local storage
  -vgc           list all gc allocations including hidden ones
  -w             warnings as errors (compilation will halt)
  -wi            warnings as messages (compilation will continue)
  -X             generate JSON file
  -Xffilename    write JSON file to filename
EOF");
}

struct Arguments
{
    /// User specified path to gdc or gdc name
    string gdcOption;
    /// User specified path to ar or ar name
    string arOption;

    /// GDC flags, used for compilation
    string[] gdcFlags;

    /// list of source files
    string[] sources;
    /// arguments to pass to the executable when running
    string[] runArguments;

    /// path to prepend to output files
    string outputDir;
    /// User specified output file
    string outputFile;
    /// ddoc output directory
    string ddocDir;
    /// ddoc output filename
    string ddocFile;
    /// header output directory
    string headerDir;
    /// header output filename
    string headerFile;
    /// json output file
    string jsonFile;
    /// .map output file
    string mapFile;

    /// whether to preserve source directory path for output files
    bool keepSourcePath;
    /// whether to skip linking stage (-c mode)
    bool dontLink;

    /// Create map file
    bool createMapFile;
    /// Show columns in error messages
    bool columns;
    /// Generate .a static library
    bool staticLib;
    /// Generate a main function
    bool main;
    /// Run the compiled executable
    bool run;
    /// Generate .di header files
    bool doHeaders;
    /// Generate .json files
    bool doJSON;
    /// Generate DDOC output
    bool doDDOC;

    /// Print executed gdc commands
    bool debugCommands;
}

private struct ArgsParser
{
    Arguments _args;
    string[] _options;

    bool parse()
    {
        while (!_options.empty)
        {
            if (handleArgument())
                return true;
        }
        return false;
    }

    bool handleArgument()
    {
        auto arg = _options[0];
        _options = _options[1 .. $];

        if (arg.startsWith("-"))
        {
            return handleDMDArgument(arg);
        }
        else if (arg.startsWith("@"))
        {
            _options = parseResponse(arg) ~ _options;
            return false;
        }
        else
        {
            if (arg.extension == ".ddoc")
                _args.gdcFlags ~= "-fdoc-inc=" ~ arg;
            else if (arg.extension == ".map")
                _args.mapFile = arg;
            else if (arg.extension == "")
                _args.sources ~= arg.setExtension(".d");
            else
                _args.sources ~= arg;
            return false;
        }
    }

    /**
    * FIXME:
    * -de can't be represented without implying -w
    */
    bool handleDMDArgument(string arg)
    {
        auto name = arg.getName();
        void abortNeedArgument()
        {
            abort("Parameter " ~ arg ~ " needs an argument!");
        }

        void abortInvalidArgument()
        {
            abort("Unknown argument in parameter " ~ arg);
        }

        switch (name)
        {
        case "":
            abortInvalidArgument();
            return false;
        case "allinst":
            _args.gdcFlags ~= "-femit-templates";
            return false;
        case "de":
            //FIXME
            _args.gdcFlags ~= ["-Wdeprecated", "-Werror"];
            return false;
        case "d":
            // Default
            return false;
        case "dw":
            _args.gdcFlags ~= "-Wdeprecated";
            return false;
        case "c":
            _args.dontLink = true;
            return false;
        case "color":
            switch (arg.getValue)
            {
            case "off":
                version (GCC_49_Plus)
                    _args.gdcFlags ~= "-fdiagnostics-color=never";
                return false;
            case "on":
                version (GCC_49_Plus)
                    _args.gdcFlags ~= "-fdiagnostics-color=always";
                return false;
            case noValue:
                return false;
            default:
                abortInvalidArgument();
                return false;
            }
        case "cov":
            // Note: Use the GNU mechanism
            _args.gdcFlags ~= ["-fprofile-arcs", "-ftest-coverage"];
            return false;
        case "shared":
            goto case;
        case "dylib":
            // FIXME
            abort("Shared library generation is not supported in GDC");
            return false;
        case "fPIC":
            // Note: Should actually for windows targets
            _args.gdcFlags ~= "-fPIC";
            return false;
        case "map":
            _args.createMapFile = true;
            return false;
        case "multiobj":
            abort("The -multiobj option is not available in GDC");
            return false;
        case "g":
            goto case;
        case "gc":
            _args.gdcFlags ~= "-g";
            return false;
        case "gs":
            _args.gdcFlags ~= "-fno-omit-frame-pointer";
            return false;
        case "gx":
            _args.gdcFlags ~= "-fstack-protector";
            return false;
        case "gt":
            abort("Use -profile instead of -gt");
            return false;
        case "m32":
            _args.gdcFlags ~= "-m32";
            return false;
        case "m64":
            _args.gdcFlags ~= "-m64";
            return false;
        case "profile":
            _args.gdcFlags ~= "-pg";
            return false;
        case "v":
            _args.gdcFlags ~= "-v";
            return false;
        case "vtls":
            _args.gdcFlags ~= "-fd-vtls";
            return false;
        case "vcolumns":
            _args.columns = true;
            return false;
        case "vgc":
            _args.gdcFlags ~= "-fd-vgc";
            return false;
        case "transition":
            switch (arg.getValue)
            {
            case "?":
                exit("Valid options for -transition= switch: tls, 3449");
                return false;
            case "3449":
                // FIXME
                abort("-transtion=3449 not implemented in GDC");
                return false;
            case "tls":
                _args.gdcFlags ~= "-fd-vtls";
                return false;
            case noValue:
                abortNeedArgument();
                return false;
            default:
                abortInvalidArgument();
                return false;
            }
        case "w":
            _args.gdcFlags ~= ["-Wall", "-Werror"];
            return false;
        case "wi":
            _args.gdcFlags ~= "-Wall";
            return false;
        case "O":
            _args.gdcFlags ~= "-O2";
            return false;
        case "ignore":
            _args.gdcFlags ~= "-fignore-unknown-pragmas";
            return false;
        case "property":
            _args.gdcFlags ~= "-fproperty";
            return false;
        case "inline":
            _args.gdcFlags ~= "-finline-functions";
            return false;
        case "lib":
            _args.staticLib = true;
            return false;
        case "nofloat":
            abort("-nofloat not supported in GDC");
            return false;
        case "quiet":
            // ignore
            return false;
        case "release":
            _args.gdcFlags ~= "-frelease";
            return false;
        case "betterC":
            _args.gdcFlags ~= "-fno-emit-moduleinfo";
            return false;
        case "noboundscheck":
            _args.gdcFlags ~= "-fno-bounds-check";
            return false;
        case "boundscheck":
            switch (arg.getValue)
            {
            case "on":
                _args.gdcFlags ~= "-fbounds-check";
                return false;
            case "safeonly":
                _args.gdcFlags ~= "-fbounds-check=safe";
                return false;
            case "off":
                _args.gdcFlags ~= "-fno-bounds-check";
                return false;
            case noValue:
                abortNeedArgument();
                return false;
            default:
                abortInvalidArgument();
                return false;
            }
        case "unittest":
            _args.gdcFlags ~= "-funittest";
            return false;
        case "debug":
            switch (arg.getValue)
            {
            case noValue:
                _args.gdcFlags ~= "-fdebug";
                return false;
            default:
                _args.gdcFlags ~= "-fdebug=" ~ arg.getValue;
                return false;
            }
        case "version":
            switch (arg.getValue)
            {
            case noValue:
                abortNeedArgument();
                return false;
            default:
                _args.gdcFlags ~= "-fversion=" ~ arg.getValue;
                return false;
            }
        case "-b":
            // 'Hidden debug switches' according to DMD source, unused
            return false;
        case "-c":
            // 'Hidden debug switches' according to DMD source, unused
            return false;
        case "-f":
            // 'Hidden debug switches' according to DMD source, unused
            return false;
        case "-help":
            return true;
        case "-r":
            // 'Hidden debug switches' according to DMD source, unused
            return false;
        case "-x":
            // 'Hidden debug switches' according to DMD source, unused
            return false;
        case "-y":
            // 'Hidden debug switches' according to DMD source, unused
            return false;
        case "defaultlib":
            if (arg.getValue == noValue)
                abortNeedArgument();
            _args.gdcFlags ~= "-defaultlib=" ~ arg.getValue;
            return false;
        case "debuglib":
            if (arg.getValue == noValue)
                abortNeedArgument();
            _args.gdcFlags ~= "-debuglib=" ~ arg.getValue;
            return false;
        case "deps":
            if (arg.getValue == noValue)
                _args.gdcFlags ~= "-fdeps";
            else
                _args.gdcFlags ~= "-fdeps=" ~ arg.getValue;
            return false;
        case "main":
            _args.main = true;
            return false;
        case "run":
            if (!_options.length)
                abortNeedArgument();
            if (_options[0].extension != ".d" && _options[0].extension != ".di")
                abort("First argument after -run must be a .d or .di file");

            _args.sources ~= _options[0];
            _args.runArguments ~= _options[1 .. $];
            _options = [];

            _args.run = true;
            return false;
            // GDC-specific options
        case "vdmd":
            _args.debugCommands = true;
            return false;
        case "q":
            if (arg.getValue == noValue)
                abortNeedArgument();
            _args.gdcFlags ~= arg.getValue();
            return false;
        case "gdc":
            if (arg.getValue == noValue)
                abortNeedArgument();
            _args.gdcOption = arg.getValue;
            return false;
        case "ar":
            if (arg.getValue == noValue)
                abortNeedArgument();
            _args.arOption = arg.getValue;
            return false;
        default:
        }

        // Now handle DMD's 'special' format switches
        switch (name[0])
        {
        case 'o':
            enforceAbort(name.length > 1, "Unknown -o switch");
            if (name[1] == '-')
            {
                _args.gdcFlags ~= "-fsyntax-only";
                return false;
            }
            else if (name[1] == 'd')
            {
                _args.outputDir = name[2 .. $];
                return false;
            }
            else if (name[1] == 'f')
            {
                _args.outputFile = name[2 .. $];
                return false;
            }
            else if (name[1] == 'p')
            {
                if (name.length > 2)
                    abort("-op does not accept arguments");
                _args.keepSourcePath = true;
                return false;
            }
            abort("Unknown -o switch");
            return false;
        case 'D':
            _args.doDDOC = true;
            if (name.length <= 1)
                return false;
            if (name[1] == 'd')
                _args.ddocDir = name[2 .. $];
            else if (name[1] == 'f')
                _args.ddocFile = name[2 .. $];
            else
                abort("Unknown -D flag");
            return false;
        case 'H':
            _args.doHeaders = true;
            if (name.length <= 1)
                return false;
            if (name[1] == 'd')
                _args.headerDir = name[2 .. $];
            else if (name[1] == 'f')
                _args.headerFile = name[2 .. $];
            else
                abort("Unknown -H flag");
            return false;
        case 'X':
            _args.doJSON = true;
            if (name.length <= 1)
                return false;
            if (name[1] == 'f')
                _args.jsonFile = name[2 .. $];
            else
                abort("Unknown -X flag");
            return false;
        case 'I':
            auto path = name[1 .. $];
            _args.gdcFlags ~= "-I" ~ path.expandTilde;
            return false;
        case 'J':
            auto path = name[1 .. $];
            _args.gdcFlags ~= "-J" ~ path.expandTilde;
            return false;
        case 'L':
            auto path = name[1 .. $];
            _args.gdcFlags ~= "-Wl," ~ path;
            return false;
        default:
            if (name.length > 2 && name[0 .. 3] == "man")
            {
                exit("http://www.gdcproject.org");
            }
        }

        // Pass argument to gdc
        _args.gdcFlags ~= arg;
        return false;
    }
}

alias HelpTuple = Tuple!(bool, "help", Arguments, "args");
/**
 * Parse arguments.
 * Returns:
 * help = true if help output should be printed
 * args = parsed Arguments
 */
HelpTuple parseCommandLine(string[] options, Arguments merge = Arguments.init)
{
    auto parser = ArgsParser(merge, options);
    auto help = parser.parse();
    return HelpTuple(help, parser._args);
}

private enum string noValue = "\0";

/**
 * Get the name part of an argument.
 */
private string getName(string arg)
{
    return arg[1 .. $].findSplitBefore("=")[0];
}

unittest
{
    assert("-".getName() == "");
    assert("-test".getName() == "test");
    assert("-test=".getName() == "test");
    assert("-test==".getName() == "test");
    assert("-test=test".getName() == "test");
}

/**
 * Get the value of an argument, or noValue if no value was given.
 */
private string getValue(string arg)
{
    auto result = arg.findSplitAfter("=");
    if (result[0].empty)
        return noValue;
    return result[1];
}

unittest
{
    assert("-".getValue() == noValue);
    assert("-test".getValue() == noValue);
    assert("-test=".getValue() == "");
    assert("-test==".getValue() == "=");
    assert("-test=test".getValue() == "test");
}
