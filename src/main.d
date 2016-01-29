/**
 * D port of dmd-script aka gdmd.
 */
module main;

/**
 * Main program
 * FIXME: -q= instead of -q,arg1,... is breaking behaviour...
 */
int main(string[] args)
{
    import gdmd.app, gdmd.exception, std.stdio, std.array;

    version (unittest)
    {
        return 0;
    }
    else
    {
        try
        {
            auto app = GDMD();
            app.parseEnvironment();
            app.parseCMD(args[1 .. $]);
            return app.run();
        }
        catch (AbortException e)
        {
            writeln(e.msg);
            return 1;
        }
        catch (ExitException e)
        {
            if (!e.msg.empty)
                writeln(e.msg);
            return 0;
        }
    }
}
