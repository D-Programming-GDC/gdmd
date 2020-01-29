module gdmd;

import dmd.cli;
import gdmd.driver;
import gdmd.options;
import core.stdc.stdlib;
import core.runtime;

private:

import dmd.root.array;

int main()
{
    OptionData params;
    auto args = Runtime.cArgs();
    if (parseArgs(args.argc, cast(const(char)**)args.argv, params))
        return EXIT_FAILURE;

    import std.stdio : writeln;
    writeln("args = ", params.args.toString());
    writeln("objfiles = ", params.objfiles.toString());
    writeln("objname = ", params.objname);
    writeln("objdir = ", params.objdir);
    writeln("inifilename = ", params.inifilename);
    writeln("preservePaths = ", params.preservePaths);
    writeln("verbose = ", params.verbose);
    writeln("lib = ", params.lib);
    writeln("run = ", params.run);
    writeln("runargs = ", params.runargs.toString());
    writeln("map = ", params.map);

    return EXIT_SUCCESS;
}
