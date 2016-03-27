/**
 * Handles gdc related functionality, such as finding gdc,
 * obtaining the gdc version, ...
 */
module gdmd.gdc;

import std.array, std.file, std.path, std.string;
import gdmd.exception;

version (unittest)
{
    import std.exception, std.stdio, std.file;
}

/**
 * Returns the environment variable used to specify the gdc path.
 * Format is ${toUpper(PREFIX).replace(-, _)}gdc${toUpper(POSTFIX).replace(-, _)}
 */
@property string environmentVariable()
{
    return environmentVariable(thisExePath().baseName());
}

/// ditto
private @property string environmentVariable(string fileName)
{
    import std.uni : toUpper;

    fileName = fileName.adaptGDC("gdc");
    if (fileName.extension == ".exe")
        fileName = fileName.stripExtension;

    return fileName.toUpper().replace("-", "_").replace(".", "");
}

unittest
{
    assert(environmentVariable("gdmd") == "GDC");
    assert(environmentVariable("gdmd.exe") == "GDC");
    assert(environmentVariable("gdmd-4.9") == "GDC_49");
    assert(environmentVariable("gdmd-4.9.exe") == "GDC_49");
    assert(environmentVariable("arm-linux-gnueabi-gdmd") == "ARM_LINUX_GNUEABI_GDC");
    assert(environmentVariable("arm-linux-gnueabi-gdmd.exe") == "ARM_LINUX_GNUEABI_GDC");
    assert(environmentVariable("arm-linux-gnueabi-gdmd-4.9") == "ARM_LINUX_GNUEABI_GDC_49");
    assert(environmentVariable("arm-linux-gnueabi-gdmd-4.9.exe") == "ARM_LINUX_GNUEABI_GDC_49");
    assert(environmentVariable("gdmd-arm-linux-gnueabi-gdmd-4.9") == "GDMD_ARM_LINUX_GNUEABI_GDC_49");
    assert(
        environmentVariable("gdmd-arm-linux-gnueabi-gdmd-4.9.exe") == "GDMD_ARM_LINUX_GNUEABI_GDC_49");
}

/**
 * Compute name of the env variable to specifiy AR path.
 */
@property string environmentVariableAR()
{
    return environmentVariableAR(thisExePath().baseName());
}

/// ditto
private @property string environmentVariableAR(string fileName)
{
    import std.uni : toUpper;

    fileName = fileName.adaptGDC("ar", false);
    if (fileName.extension == ".exe")
        fileName = fileName.stripExtension;

    return fileName.toUpper().replace("-", "_".replace(".", ""));
}

unittest
{
    assert(environmentVariableAR("gdmd") == "AR");
    assert(environmentVariableAR("gdmd.exe") == "AR");
    assert(environmentVariableAR("gdmd-4.9") == "AR");
    assert(environmentVariableAR("gdmd-4.9.exe") == "AR");
    assert(environmentVariableAR("arm-linux-gnueabi-gdmd") == "ARM_LINUX_GNUEABI_AR");
    assert(environmentVariableAR("arm-linux-gnueabi-gdmd.exe") == "ARM_LINUX_GNUEABI_AR");
    assert(environmentVariableAR("arm-linux-gnueabi-gdmd-4.9") == "ARM_LINUX_GNUEABI_AR");
    assert(environmentVariableAR("arm-linux-gnueabi-gdmd-4.9.exe") == "ARM_LINUX_GNUEABI_AR");
    assert(environmentVariableAR("gdmd-arm-linux-gnueabi-gdmd-4.9") == "GDMD_ARM_LINUX_GNUEABI_AR");
    assert(
        environmentVariableAR("gdmd-arm-linux-gnueabi-gdmd-4.9.exe") == "GDMD_ARM_LINUX_GNUEABI_AR");
}

/**
 * Compute tool path from GDMD path.
 * Parameters:
 *   gdmd = path to gdmd
 *   replacement = gdmd is replaced with this tool name
 *   postfix = if the postfix value (gdmd-postfix) should be kept
 */
private string adaptGDC(string gdmd, string replacement, bool postfix = true)
{
    enum searchValue = "gdmd";
    auto idx = gdmd.lastIndexOf(searchValue, std.string.CaseSensitive.no);
    enforceAbort(idx != -1,
        "gdmd executable has got an invalid filename: '" ~ gdmd ~ "'." ~ "The filename must contain the string 'gdmd'!");
    if (postfix)
        return gdmd[0 .. idx] ~ replacement ~ gdmd[idx + searchValue.length .. $];
    else
        return gdmd[0 .. idx] ~ replacement;
}

unittest
{
    assert(adaptGDC("gdmd", "gdc") == "gdc");
    assert(adaptGDC("gdmd.exe", "gdc") == "gdc.exe");
    assert(adaptGDC("gdmd-4.9", "gdc") == "gdc-4.9");
    assert(adaptGDC("gdmd-4.9.exe", "gdc") == "gdc-4.9.exe");
    // Accept case insensitive input, but assume this can only happen on case insensitive systems
    // and user lowercase gdc anyway.
    assert(adaptGDC("GDmD-4.9", "gdc") == "gdc-4.9");
    assert(adaptGDC("GDmD-4.9.exe", "gdc") == "gdc-4.9.exe");
    assert(adaptGDC("arm-linux-gnueabi-gdmd", "gdc") == "arm-linux-gnueabi-gdc");
    assert(adaptGDC("arm-linux-gnueabi-gdmd.exe", "gdc") == "arm-linux-gnueabi-gdc.exe");
    assert(adaptGDC("arm-linux-gnueabi-gdmd-4.9", "gdc") == "arm-linux-gnueabi-gdc-4.9");
    assert(adaptGDC("arm-linux-gnueabi-gdmd-4.9.exe", "gdc") == "arm-linux-gnueabi-gdc-4.9.exe");
    assert(adaptGDC("gdmd-arm-linux-gnueabi-gdmd-4.9", "gdc") == "gdmd-arm-linux-gnueabi-gdc-4.9");
    assert(adaptGDC("gdmd-arm-linux-gnueabi-gdmd-4.9.exe",
        "gdc") == "gdmd-arm-linux-gnueabi-gdc-4.9.exe");

    assert(adaptGDC("/usr/gdmd/arm-linux-gnueabi-gdmd-4.9",
        "gdc") == "/usr/gdmd/arm-linux-gnueabi-gdc-4.9");
    assert(adaptGDC("/usr/gdmd/arm-linux-gnueabi-gdmd-4.9.exe",
        "gdc") == "/usr/gdmd/arm-linux-gnueabi-gdc-4.9.exe");
    assert(adaptGDC("./gdmd/arm-linux-gnueabi-gdmd-4.9",
        "gdc") == "./gdmd/arm-linux-gnueabi-gdc-4.9");
    assert(adaptGDC("./gdmd/arm-linux-gnueabi-gdmd-4.9.exe",
        "gdc") == "./gdmd/arm-linux-gnueabi-gdc-4.9.exe");
}

/**
 * Search GDC using a user supplied path, which can be an absolute path,
 * relative path or a name of a binary in $PATH.
 */
string searchProgram(string entry, string program)
{
    import std.file : exists;
    import std.path;

    string result;
    if (entry.isAbsolute())
        result = entry;
    else if (entry.baseName() == entry)
        result = which(entry);
    else
        result = entry.absolutePath();

    enforceAbort(!result.empty && result.exists(),
        "Invalid path '" ~ entry ~ "' to " ~ program ~ " binary specified on command line or in environment!");
    return result;
}

/// ditto
string searchGDC(string entry)
{
    return searchProgram(entry, "gdc");
}

/// ditto
string searchAR(string entry)
{
    return searchProgram(entry, "gcc-ar");
}

unittest
{
    import std.stdio;

    assert(!searchGDC("gdc").empty);
    assertThrown(searchGDC("gdca"));
    auto gdcaPath = "./gdca".absolutePath();
    {
        auto f = File(gdcaPath, "w");
        assert(searchGDC("./gdca") == gdcaPath);
        scope (exit)
        {
            f.close();
            std.file.remove(gdcaPath);
        }
    }
    assertThrown(searchGDC("./gdc"));
    assertThrown(searchGDC("/usr/bin/gdca"));
}

/// Similar to unix tool "which", that shows the full path of an executable
string which(string executableName)
{
    import std.process : environment;
    import std.path : pathSeparator, buildPath;
    import std.file : exists;
    import std.algorithm : splitter;

    // pathSeparator: Windows uses ";" separator, POSIX uses ":"
    foreach (dir; splitter(environment["PATH"], pathSeparator))
    {
        auto path = buildPath(dir, executableName);
        if (exists(path))
            return path;
    }
    return "";
}

/**
 * Find the correct gdc in the same folder as the gdmd executable.
 */
string autodetectGDC()
{
    auto gdcPath = thisExePath.adaptGDC("gdc").buildNormalizedPath();
    enforceAbort(!gdcPath.empty && gdcPath.exists(),
        "Couldn't autodetect gdc at '" ~ gdcPath ~ "'." ~ " Specify the path to the gdc executable using -gdc= or the environment variable '" ~ environmentVariable ~ "'");
    return gdcPath;
}

unittest
{
    auto gdcPath = "./gdc".absolutePath().buildNormalizedPath();
    {
        auto f = File(gdcPath, "w");
        scope (exit)
        {
            f.close();
            gdcPath.remove();
        }
        assert(autodetectGDC() == gdcPath);
    }
    assertThrown(autodetectGDC());
}
