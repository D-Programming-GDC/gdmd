// Types and static data for DMD cli options for use in gdmd.
module gdmd.options;

static import gdmd.generated;
static import dmd.root.array;

@safe pure nothrow:

// Represents an option flag.
struct Flag
{
    string flag;            // Option string (`--version`)
    bool argument;          // Option requires argument
    bool separated;         // True iff argument is separated by a space
    int overlapping = -1;   // Index of overlapping flag (`-Df=` -> `-Df`)
    string[] arguments;     // List of all valid arguments for option
}

// Publicly forward Option enum.
alias Option = gdmd.generated.Option;

// Statically define OptionFlags.
immutable Flag[Option.max] OptionFlags = gdmd.generated.OptionFlags;

alias OptionStrings = gdmd.generated.OptionStrings;

// Short hand alias for the internal DMD char[] type.
alias Strings = dmd.root.array.Array!(const(char)*);

// Options data handled by gdmd
struct OptionData
{
    Strings args;      // Arguments to pass to gdc.
    Strings objfiles;
    string objname;
    string objdir;
    string inifilename;
    bool preservePaths;
    bool verbose;
    bool lib;
    bool run;
    Strings runargs;
    bool map;           // Whether the `-map` option was used.
}

// File extensions for various handled sources.
enum FileType : string
{
    mars = ".d",    // D sources
    doc = ".dd",    // Ddoc input files
    hdr = ".di",    // D header files
    obj = ".o",     // Object files
    lib = ".a",     // Library archives
    dll = ".so",    // Dynamic libraries
    exe = ".exe",   // Executable suffix
    map = ".map",   // Linker map files
    ddoc = ".ddoc", // Ddoc macro includes files
    json = ".json", // JSON files
}
