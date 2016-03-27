/**
 * Contains small helper functions not fitting into other modules.
 */
module gdmd.util;

/**
 * Return a range of num random letters.
 */
auto randomLetters(size_t num)
{
    import std.range : iota;
    import std.random : uniform;
    import std.ascii : letters;
    import std.algorithm : map;

    return iota(num).map!(a => letters[uniform(0, $)]);
}
