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
    if (!environment.get("AR"))
        environment["AR"] = "ar";
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

    test.runSuccess("--version");
    test.files([]);

    test.runSuccess("src/a.d --version");
    test.files([]);

    test.runFail("src/a.d -conf=foo.conf");
    test.files([]);

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

void test3()
{
    auto test = GDMDTest("3");
    auto oldGDC = environment["GDC"];
    environment.remove("GDC");
    test.runSuccess("-gdc=" ~ oldGDC ~ " src/a.d");
    test.files(["a"]);

    // ar might not be in same folder as gdc
    //test.runSuccess("-gdc=gdc src/a.d -lib");
    //test.files(["a.a"]);

    test.runSuccess("-gdc=gdc -ar=ar src/a.d -lib");
    test.files(["a.a"]);
    environment["GDC"] = oldGDC;

    test.runSuccess("-vdmd src/a.d -lib");
    test.files(["a.a"]);

    test.runSuccess("src/a.d -q=-O3");
    test.files(["a"]);

    test.runSuccess("src/a.d -O3");
    test.files(["a"]);

    test.runSuccess("src/a.d -allinst");
    test.files(["a"]);

    test.runSuccess("src/a.d -c");
    test.files(["a.o"]);

    test.runSuccess("src/a.d -color");
    test.files(["a"]);

    test.runSuccess("src/a.d -color=on");
    test.files(["a"]);

    test.runSuccess("src/a.d -color=off");
    test.files(["a"]);

    test.runSuccess("src/a.d -cov");
    test.files(["a", "a.gcno"]);

    test.runSuccess("src/a.d -cov=12");
    test.files(["a", "a.gcno"]);

    test.runSuccess("src/a.d -D");
    test.files(["a", "a.html"]);

    test.runSuccess("src/a.d -D -Dddoc");
    test.files(["a", "doc/a.html"]);

    test.runSuccess("src/a.d -D -Dfdoc.html");
    test.files(["a", "doc.html"]);

    test.runSuccess("src/a.d -D -Dfdoc.html -Dddoc");
    test.files(["a", "doc.html"]);

    test.runSuccess("src/a.d -d");
    test.files(["a"]);

    test.runSuccess("src/a.d -dw");
    test.files(["a"]);

    test.runSuccess("src/a.d -de");
    test.files(["a"]);

    test.runSuccess("src/a.d -debug=12");
    test.files(["a"]);

    test.runSuccess("src/a.d -debug=test");
    test.files(["a"]);

    // Seems to be broken in GDC
    //test.runSuccess("src/a.d -debuglib=gphobos2");
    //test.files(["a"]);

    //test.runSuccess("src/a.d -defaultlib=gphobos2");
    //test.files(["a"]);

    test.runSuccess("src/a.d -deps");
    test.files(["a"]);

    test.runSuccess("src/a.d -deps=dep.txt");
    test.files(["a", "dep.txt"]);

    test.runSuccess("src/a.d -fPIC");
    test.files(["a"]);

    test.runSuccess("src/a.d -g");
    test.files(["a"]);

    test.runSuccess("src/a.d -gc");
    test.files(["a"]);

    test.runSuccess("src/a.d -gs");
    test.files(["a"]);

    test.runSuccess("src/a.d -gx");
    test.files(["a"]);

    test.runSuccess("src/a.d -H");
    test.files(["a", "a.di"]);

    test.runSuccess("src/a.d -H -Hftest.di");
    test.files(["a", "test.di"]);

    test.runSuccess("src/a.d -H -Hdimport");
    test.files(["a", "import/a.di"]);

    test.runSuccess("src/a.d --help");
    test.files([]);

    test.runSuccess("src/a.d -I.");
    test.files(["a"]);

    test.runSuccess("src/a.d -ignore");
    test.files(["a"]);

    test.runSuccess("src/a.d -inline");
    test.files(["a"]);

    test.runSuccess("src/a.d -J.");
    test.files(["a"]);

    test.runSuccess("src/a.d -lib");
    test.files(["a.a"]);

    //test.runSuccess("src/a.d -m32");
    //test.files(["a"]);

    test.runSuccess("src/a.d -m64");
    test.files(["a"]);

    test.runSuccess("src/b.d -main");
    test.files(["b"]);

    test.runSuccess("src/a.d -man");
    test.files([]);

    test.runSuccess("src/a.d -map");
    test.files(["a", "a.map"]);

    test.runSuccess("src/a.d -boundscheck=on");
    test.files(["a"]);

    test.runSuccess("src/a.d -boundscheck=safeonly");
    test.files(["a"]);

    test.runSuccess("src/a.d -boundscheck=off");
    test.files(["a"]);

    test.runSuccess("src/a.d -noboundscheck");
    test.files(["a"]);

    test.runSuccess("src/a.d -O");
    test.files(["a"]);

    test.runSuccess("src/a.d -o-");
    test.files([]);

    test.runSuccess("src/a.d -profile");
    test.files(["a"]);

    test.runFail("src/a.d -profile=");
    test.files([]);

    test.runFail("src/a.d -profile=gc");
    test.files([]);

    test.runSuccess("src/a.d -property");
    test.files(["a"]);

    test.runSuccess("src/a.d -release");
    test.files(["a"]);

    test.runSuccess("-run src/a.d abcd");
    test.files([]);

    test.runFail("src/a.d -shared");
    test.files([]);

    test.runSuccess("src/a.d -transition=?");
    test.files([]);

    test.runSuccess("src/a.d -transition=tls");
    test.files(["a"]);

    test.runSuccess("src/a.d -transition=3449");
    test.files(["a"]);

    test.runSuccess("src/a.d -transition=field");
    test.files(["a"]);

    test.runSuccess("src/a.d -transition=14488");
    test.files(["a"]);

    test.runSuccess("src/a.d -transition=complex");
    test.files(["a"]);

    test.runSuccess("src/a.d -transition=all");
    test.files(["a"]);

    test.runFail("src/a.d -transition=");
    test.files([]);

    test.runFail("src/a.d -transition");
    test.files([]);

    test.runSuccess("src/a.d -dip25");
    test.files(["a"]);

    test.runSuccess("src/a.d -unittest");
    test.files(["a"]);

    test.runSuccess("src/a.d -v");
    test.files(["a"]);

    test.runSuccess("src/a.d -vcolumns");
    test.files(["a"]);

    test.runSuccess("src/a.d -verrors=10");
    test.files(["a"]);

    test.runSuccess("src/a.d -version=10");
    test.files(["a"]);

    test.runSuccess("src/a.d -version=foo");
    test.files(["a"]);

    test.runSuccess("src/a.d -vtls");
    test.files(["a"]);

    test.runSuccess("src/a.d -vgc");
    test.files(["a"]);

    test.runSuccess("src/a.d -w");
    test.files(["a"]);

    test.runSuccess("src/a.d -wi");
    test.files(["a"]);

    test.runSuccess("src/a.d -boundscheck=off -X");
    test.files(["a", "a.json"]);

    test.runSuccess("src/a.d -boundscheck=off -Xffoo.json");
    test.files(["a", "foo.json"]);
}

void main()
{
    test1();
    test2();
    test3();
}
