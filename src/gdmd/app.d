/**
 * Contains the main GDMD logic.
 */
module gdmd.app;

import std.array, std.conv, std.exception, std.file, std.path, std.process,
    std.string, std.stdio;
import gdmd.args, gdmd.gdc, gdmd.exception, gdmd.response, gdmd.util;

string setExeExtension(string program)
{
    version (Windows)
    {
        if (program.endsWith(".exe"))
            return program;
        else
            return program ~ ".exe";
    }
    else
    {
        return program;
    }
}

struct GDMD
{
private:
    Arguments args;

    string gdcPath;
    string arPath;
    enum objectExtension = ".o";
    enum libExtension = ".a";
    enum mapExtension = ".map";
    string exeExetension;

    /**
     * Algorithm:
     * * User provided GDC location
     *   * If cmd args --gdc, use that location (check+error)
     *     * absolute path => ok
     *     * relative path => ok
     *     * name only => search in PATH
     *   * Otherwise, check if ${PREFIX}GDC${POSTFIX} env variable is set.
     *   * Otherwise, check if GDMD_GDC is set
     * * Automated detection
     *   * Check if an executable ${PREFIX}gdc{POSTFIX} is in the same
     *     directory as the gdmd executable
     */
    void findGDC()
    {
        import std.process;

        // Check first if we have some sort of user supplied GDC path
        if (!args.gdcOption.empty)
            gdcPath = searchGDC(args.gdcOption.setExeExtension());
        else if (auto entry = environment.get(environmentVariable))
            gdcPath = searchGDC(entry.setExeExtension());
        else if (auto entry = environment.get("GDMD_GDC"))
            gdcPath = searchGDC(entry.setExeExtension());
        else
            gdcPath = autodetectGDC();
    }

    /**
     * Find the ar archiver.
     */
    void findAR()
    {
        import std.process;

        // Check first if we have some sort of user supplied AR path
        if (!args.arOption.empty)
            arPath = searchAR(args.arOption.setExeExtension());
        else if (auto entry = environment.get(environmentVariableAR))
            arPath = searchAR(entry.setExeExtension());
        else if (auto entry = environment.get("GDMD_AR"))
            arPath = searchAR(entry.setExeExtension());
        else
        {
            auto idx = gdcPath.lastIndexOf("gdc", std.string.CaseSensitive.no);
            arPath = gdcPath[0 .. idx] ~ "gcc-ar";
            arPath = arPath.setExeExtension();
            // If gdc was found in PATH, search for AR in different PATH directories as well
            if (!arPath.exists() && !args.gdcOption.empty
                    && args.gdcOption.baseName() == args.gdcOption)
            {
                idx = args.gdcOption.lastIndexOf("gdc", std.string.CaseSensitive.no);
                arPath = searchAR((args.gdcOption[0 .. idx] ~ "gcc-ar").setExeExtension());
            }
        }
    }

    /**
     * Compile dummy code to inquire some compiler information using CTFE.
     * 
     * Returns: GDC output
     * Throws: If gdc returns a non-0 status or if gdc can't be executed
     */
    string compileDummy(string code)
    {
        auto randomID = randomLetters(10);
        auto tempSource = tempDir().buildPath("gdc_%s.d".format(randomID));
        if (args.debugCommands)
            writefln("[exec] Writing D code '%s' to %s", code, tempSource);
        std.file.write(tempSource, code);

        scope (exit)
        {
            if (tempSource.exists())
                tempSource.remove();
        }

        auto result = executeResponse([gdcPath, "-fsyntax-only", tempSource],
            args.debugCommands, true);

        enforce(result.status == 0, "Couldn't call gdc compiler to inquire some information!");
        return result.output;
    }

    uint detectGDCVersion()
    {
        auto result = compileDummy("pragma(msg, __VERSION__);");
        return result.parse!uint();
    }

    /**
     * Print usage information and GDC version.
     */
    void printHelp()
    {
        auto ver = detectGDCVersion();
        printUsage(ver / 1000, ver % 1000, getGDCInfo("--version"));
    }

    /**
     * Run the compiler with arg, verify the return code and return the console output.
     */
    string getGDCInfo(string arg)
    {
        auto result = executeResponse([gdcPath, arg], args.debugCommands, true);
        enforce(result.status == 0, "Couldn't call gdc compiler to inquire some information!");
        return result.output;
    }

    /**
     * Determine output file given current configuration.
     */
    string determineOutputFile()
    {
        assert(args.sources.length >= 1);
        return (args.outputFile.empty) ? src2outSimple(baseName(args.sources[0]), exeExetension)
            : args.outputFile;
    }

    /**
     * Determine path of the output library.
     */
    string determineOutputLib()
    {
        assert(args.sources.length >= 1);
        return (args.outputFile.empty) ? src2outSimple(baseName(args.sources[0]), libExtension)
            : args.outputFile.setExtension(libExtension);
    }

    /**
     * Determine path of the map output file.
     */
    string determineMapFile()
    {
        return (args.mapFile.empty) ? src2out(baseName(args.sources[0]), mapExtension)
            : args.outputFile.setExtension(mapExtension);
    }

    /**
     * Determine the executable extension to use.
     */
    void findExeExtension()
    {
        // Best way is to actually invoke the compiler
        // If at some point multiarch GCC becomes possible, we may have to pass -m flags
        auto result = compileDummy(
            `version(Windows) {pragma(msg, "true");} else {pragma(msg, "false");}`);

        if (result.parse!bool())
            exeExetension = ".exe";
        else
            exeExetension = "";
    }

    /**
     * Convenience function for determining output filename given a source file.
     * Simple version.
     */
    string src2outSimple(string srcfile, string targetExt)
    {
        return baseName(srcfile).setExtension(targetExt);
    }

    /**
     * Convenience function for determining output filename given a source file.
     */
    string src2out(string srcfile, string targetExt)
    {
        string[] outpath;

        if (!args.outputDir.empty)
            outpath ~= args.outputDir;

        if (args.keepSourcePath)
        {
            // Ignore outputDir if we've got an absolute path
            if (srcfile.isAbsolute())
                outpath = [srcfile.setExtension(targetExt)];
            else
                outpath ~= srcfile.setExtension(targetExt);
        }
        else
        {
            outpath ~= baseName(srcfile).setExtension(targetExt);
        }

        return buildPath(outpath);
    }

    /// ditto
    string src2out(string srcfile)
    {
        string[] outpath;

        if (!args.outputDir.empty)
            outpath ~= args.outputDir;

        if (args.keepSourcePath)
        {
            // Ignore outputDir if we've got an absolute path
            if (srcfile.isAbsolute())
                outpath = [srcfile];
            else
                outpath ~= srcfile;
        }
        else
        {
            outpath ~= baseName(srcfile);
        }

        return buildPath(outpath);
    }

    /**
     * Some arguments can't be converted directly in parseCommandLine.
     * These are stored in the args struct and converted into GDC arguments
     * and stored in args.gdcFlags here.
     */
    void prepareExtraArgs()
    {
        string[] extraFlags;
        if (args.createMapFile)
            extraFlags ~= "-Wl,-Map=" ~ determineMapFile();

        if (args.columns)
            extraFlags ~= ["-fdiagnostics-show-option", "-fdiagnostics-show-caret"];
        else
            extraFlags ~= ["-fno-diagnostics-show-option", "-fno-diagnostics-show-caret"];

        if (args.doHeaders)
        {
            extraFlags ~= "-fintfc";
            if (!args.headerDir.empty)
                extraFlags ~= "-fintfc-dir=" ~ args.headerDir;
            if (!args.headerFile.empty)
            {
                string headerFile = src2out(args.headerFile, ".di");
                auto headerDir = dirName(headerFile);
                if (!exists(headerDir))
                {
                    if (args.debugCommands)
                        writefln("[exec] mkdirRecurse(%s)", headerDir);
                    mkdirRecurse(headerDir);
                }
                extraFlags ~= "-fintfc-file=" ~ headerFile;
            }
        }

        if (args.doJSON)
        {
            if (args.jsonFile.empty)
                extraFlags ~= "-fXf=" ~ src2outSimple(baseName(args.sources[0]), ".json");
            else
                extraFlags ~= "-fXf=" ~ args.jsonFile.setExtension(".json");
        }

        if (args.doDDOC)
        {
            extraFlags ~= "-fdoc";
            if (!args.ddocDir.empty)
                extraFlags ~= "-fdoc-dir=" ~ args.ddocDir;
            if (!args.ddocFile.empty)
            {
                string ddocFile = src2out(args.ddocFile);
                auto ddocDir = dirName(ddocFile);
                if (!exists(ddocDir))
                {
                    if (args.debugCommands)
                        writefln("[exec] mkdirRecurse(%s)", ddocDir);
                    mkdirRecurse(ddocDir);
                }
                extraFlags ~= "-fdoc-file=" ~ ddocFile;
            }
        }

        // prepend flags to allow user to override these
        args.gdcFlags = extraFlags ~ args.gdcFlags;
    }

    /**
     * Compiles every source into one object file. Used for multiobj support.
     * 
     * BUGS: In some cases we can't properly emulate the multiobj support. Consider
     * source files in src/a.d and src/b.d where b.d imports a.d and this dmd command
     * line: dmd src/a.d src/b.d -c. We have to compile the sources one by one, but then
     * we won't find a.d when compiling b.d as we don't use the correct import path.
     */
    void compileSeparately()
    {
        foreach (srcfile; args.sources)
        {
            auto objfile = src2out(srcfile, objectExtension);
            compileOneObject(objfile, [srcfile]);
        }
    }

    /**
     * Compile only but have a -of option so compile everything in one call
     * into one object file.
     */
    void compileOneObject()
    {
        compileOneObject(args.outputFile, args.sources);
    }

    /// ditto
    void compileOneObject(string objfile, string[] srcfiles)
    {
        // If target directory doesn't exist yet, create it.
        auto objdir = dirName(objfile);
        if (!exists(objdir))
        {
            if (args.debugCommands)
                writefln("[exec] mkdirRecurse(%s)", objdir);
            mkdirRecurse(objdir);
        }

        // Invoke compiler
        auto cmd = [gdcPath] ~ args.gdcFlags ~ ["-c"] ~ srcfiles ~ ["-o", objfile];
        auto rc = executeResponse(cmd, args.debugCommands);
        write(rc.output);
        enforceAbort(rc.status == 0, "Compile of %s failed".format(srcfiles));
    }

    /**
     * Compiles and links the given sources files into the final executable.
     */
    void compileLink()
    {
        compileLink(determineOutputFile());
    }

    /// ditto
    void compileLink(string exeFile)
    {
        // Create target directory if it doesn't exist yet.
        auto exeDir = exeFile.dirName();
        if (!exists(exeDir))
        {
            if (args.debugCommands)
                writefln("[exec] mkdirRecurse(%s)", exeDir);
            mkdirRecurse(exeDir);
        }

        // Autogenerate main if requested
        auto mainName = "gdc_%s".format(randomLetters(10)).setExtension(".d");
        auto mainFile = tempDir().buildPath(mainName);

        scope (exit)
        {
            if (mainFile.exists())
                mainFile.remove();
        }

        // Construct link command
        auto cmd = [gdcPath] ~ args.gdcFlags ~ args.sources;
        if (args.main)
        {
            std.file.write(mainFile, "void main() {}");
            cmd ~= mainFile;
        }
        cmd ~= ["-o", exeFile];

        auto rc = executeResponse(cmd, args.debugCommands);
        write(rc.output);
        enforceAbort(rc.status == 0, "Compile and link failed");
    }

    /**
     * Compile into a temporary file and run the compiled executable.
     */
    int compileLinkRun()
    {
        auto fileName = "gdc_%s".format(randomLetters(10)).setExtension(exeExetension);
        auto tempOutput = tempDir().buildPath(fileName);

        scope (exit)
        {
            if (tempOutput.exists())
                tempOutput.remove();
        }

        compileLink(tempOutput);
        auto cmd = [tempOutput] ~ args.runArguments;
        return spawnWaitResponse(cmd, args.debugCommands);
    }

    /**
     * Compile source files into a static library.
     * 
     * BUGS: This compiles everything into one object file first. This is a workaround for the issue
     * mentioned in compileSeparately. Not sure if there's any drawback in compiling one object file only
     * (except for memory usage).
     */
    void compileStaticLib()
    {
        auto fileName = "gdc_%s".format(randomLetters(10)).setExtension(objectExtension);
        auto tempOutput = tempDir().buildPath(fileName);

        scope (exit)
        {
            if (tempOutput.exists())
                tempOutput.remove();
        }

        compileOneObject(tempOutput, args.sources);
        auto cmd = [arPath, "rcs", determineOutputLib(), tempOutput];
        auto rc = executeResponse(cmd, args.debugCommands);
        write(rc.output);
        enforceAbort(rc.status == 0, "Creating library failed");
    }

public:
    /**
     * Parse arguments from the DFLAGS environment variable.
     */
    void parseEnvironment()
    {
        import std.regex : split, regex;

        parseCMD(environment.get("DFLAGS", "").split(regex(r"\s+")));
    }

    /**
     * Parse command line arguments.
     */
    void parseCMD(string[] cmd)
    {
        auto result = parseCommandLine(cmd, args);
        args = result.args;
        if (result.help)
        {
            // We need gdc to print the help output
            findGDC();
            printHelp();
            exit();
        }
    }

    /**
     * Do the final compilation steps.
     */
    int run()
    {
        findGDC();
        findExeExtension();

        if (args.sources.empty)
        {
            printHelp();
            exit();
        }

        prepareExtraArgs();

        enforceAbort([args.staticLib, args.run, args.dontLink].count(true) <= 1,
            "Can only use one of -c, -run and -lib!");

        if (args.staticLib)
        {
            findAR();
            enforceAbort(arPath.exists,
                "Couldn't autodetect ar at '" ~ arPath ~ "'." ~ " Specify the path to the ar executable using -ar= or the environment variable '" ~ environmentVariableAR ~ "'");
            compileStaticLib();
        }
        else if (args.run)
        {
            return compileLinkRun();
        }
        else if (args.dontLink)
        {
            if (args.outputFile.empty)
                compileSeparately();
            else
                compileOneObject();
        }
        else
        {
            compileLink();
        }
        return 0;
    }
}
