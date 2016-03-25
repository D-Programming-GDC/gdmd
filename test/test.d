/**
 * Test suite for GDMD.
 */
module gdmd.test;
import std.array, std.file, std.path, std.process, std.stdio, std.string;

string basePath;
string gdmdPath;

static this()
{
    basePath = getcwd().buildPath("test");
    gdmdPath = getcwd().buildPath("gdmd");

    // So our tested gdmd uses the system local gdc
    if (!environment.get("GDC"))
        environment["GDC"] = "gdc";
}

auto removeElement(R, N)(R haystack, N needle)
{
    import std.algorithm : countUntil, remove;

    auto index = haystack.countUntil(needle);
    return (index != -1) ? haystack.remove(index) : haystack;
}

struct GDMDTest
{
private:
    string _path;
    string _runPath;

    void copySources()
    {

        foreach (entry; dirEntries(_path, SpanMode.breadth))
        {

            if (entry.isDir)
                mkdirRecurse(_runPath.buildPath(entry.relativePath(_path)));
            if (entry.isFile)
                copy(entry, _runPath.buildPath(entry.relativePath(_path)));
        }
    }

public:
    this(string name)
    {
        _path = basePath.buildPath(name);
        _runPath = basePath.buildPath(name ~ ".run");
        assert(_path.exists() && _path.isDir());
    }

    string runSuccess(string args)
    {
        return run(args, true);
    }

    string runFail(string args)
    {
        return run(args, false);
    }

    string run(string args, bool success)
    {
        writefln("=> %s \t (%s)", _path.relativePath(basePath), args);

        if (_runPath.exists())
            _runPath.rmdirRecurse();

        copySources();
        chdir(_runPath);
        auto result = executeShell(gdmdPath ~ " " ~ args);
        if (success)
            assert(result.status == 0, result.output);
        else
            assert(result.status != 0, result.output);

        return result.output;
    }

    void files(string[] result)
    {
        assert(_runPath.exists());
        string[] files;
        foreach (entry; dirEntries(_runPath, SpanMode.breadth))
        {
            if (entry.isFile && !_path.buildPath(entry.relativePath(_runPath)).exists)
                files ~= entry.relativePath(_runPath);
        }

        foreach (entry; result)
        {
            import std.algorithm;

            assert(files.canFind(entry), "Can't find file: " ~ entry);
            files = files.removeElement(entry);
        }

        assert(files.empty, "Found additional files: " ~ files.join(" "));
    }

    ~this()
    {
        if (_runPath.exists())
            _runPath.rmdirRecurse();
    }
}

void test1()
{
    auto test = GDMDTest("1");
    test.runSuccess("src/a.d -c");
    test.files(["a.o"]);

    test.runSuccess("src/a.d src/b.d -c");
    test.files(["a.o", "b.o"]);

    test.runSuccess("src/a.d src/b.d -c -oftest.o");
    test.files(["test.o"]);

    test.runSuccess("src/a.d src/b.d -c -odobj");
    test.files(["obj/a.o", "obj/b.o"]);

    test.runSuccess("src/a.d src/b.d -c -odobj -oftest.o");
    test.files(["test.o"]);

    test.runSuccess("src/a.d src/b.d -c -odobj -op");
    test.files(["obj/src/a.o", "obj/src/b.o"]);

    test.runSuccess("src/a.d src/b.d -c -odobj -op -oftest.o");
    test.files(["test.o"]);

    test.runSuccess("src/a.d src/b.d -c -op -oftest.o");
    test.files(["test.o"]);

    test.runSuccess("src/a.d src/b.d -c -op");
    test.files(["src/a.o", "src/b.o"]);

    test.runSuccess("%s/src/a.d %s/src/b.d -c -op".format(test._runPath, test._runPath));
    test.files(["src/a.o", "src/b.o"]);

    test.runSuccess("%s/src/a.d %s/src/b.d -c -odobj -op".format(test._runPath, test._runPath));
    test.files(["src/a.o", "src/b.o"]);
}

void test2()
{
    auto test = GDMDTest("2");
    test.runSuccess("src/a.d");
    test.files(["a"]);

    test.runSuccess("src/a.d src/b.d");
    test.files(["a"]);

    test.runSuccess("src/a.d src/b.d -oftest");
    test.files(["test"]);

    test.runSuccess("src/a.d src/b.d -odobj");
    test.files(["a"]);

    test.runSuccess("src/a.d src/b.d -odobj -oftest");
    test.files(["test"]);

    //FIXME: Fix this if somebody complains
    //test.runSuccess("src/a.d src/b.d -odobj -op");
    //test.files(["a", "obj/a.o"]);

    test.runSuccess("src/a.d src/b.d -odobj -op -oftest");
    test.files(["test"]);

    test.runSuccess("src/a.d src/b.d -op -oftest");
    test.files(["test"]);

    test.runSuccess("src/a.d src/b.d -op");
    test.files(["a"]);

    test.runSuccess("%s/src/a.d %s/src/b.d -op".format(test._runPath, test._runPath));
    test.files(["a"]);

    test.runSuccess("%s/src/a.d %s/src/b.d -odobj -op".format(test._runPath, test._runPath));
    test.files(["a"]);
}

void main()
{
    test1();
    test2();
}
