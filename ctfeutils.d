// CTFE-friendly helper functions for generating code.
module gdmd.ctfeutils;

@safe pure nothrow:
package:

// Returns the index of the first occurrence of `c` in the string `sub`.
// Returns -1 if not found.
ptrdiff_t indexOf(string sub, char c) @nogc
{
    ptrdiff_t i;
    foreach (s; sub)
    {
        if (s == c)
            return i;
        ++i;
    }
    return -1;
}

private // unittest
{
    static assert(indexOf("Hello World", 'W') == 6);
    static assert(indexOf("Hello World", 'Z') == -1);
}

// Returns the index of the first occurrence of any character in `cs` in the
// string `sub`.  Returns -1 if not found.
ptrdiff_t indexOfAny(string sub, string cs) @nogc
{
    ptrdiff_t i;
    foreach (s; sub)
    {
        foreach (c; cs)
        {
            if (s == c)
                return i;
        }
        ++i;
    }
    return -1;
}

private // unittest
{
    static assert("helloWorld".indexOfAny("rW") == 5);
    static assert("helloWorld".indexOfAny("zZ") == -1);
}

// True if `c` is a letter or a number (0 .. 9, a .. z, A .. Z)
bool isAlphaNum(char c) @nogc
{
    return c <= 'z' && c >= '0' &&
        (c <= '9' || c >= 'a' || (c >= 'A' && c <= 'Z'));
}

private // unittest
{
    static assert(isAlphaNum('a'));
    static assert(isAlphaNum('A'));
    static assert(isAlphaNum('1'));
    static assert(!isAlphaNum('#'));
}

// Convert a positive integer `i` to a string.
string intToString(ptrdiff_t i)
{
    assert(i >= 0);

    string s;
    while (i >= 10)
    {
        s = cast(char)('0' + (i % 10)) ~ s;
        i = i / 10;
    }
    s = cast(char)(i + '0') ~ s;
    return s;
}

private // unittest
{
    static assert(intToString(0) == "0");
    static assert(intToString(9) == "9");
    static assert(intToString(42) == "42");
    static assert(intToString(10099) == "10099");
    static assert(!__traits(compiles, {
        static assert(intToString(-1) == "-1");
    }));
}

// Splits all variations in `str` into an array, using `|` as the delimiter.
private string[] splitVariations(string str)
{
    string[] ret;
    string variation;
    int brackets;

    for (size_t idx = 0; idx < str.length; idx++)
    {
        // Append variation if we are not inside a subvariation `[ .. ]`.
        if (str[idx] == '|' && !brackets)
        {
            ret ~= variation;
            variation = null;
        }
        else
        {
            // Keep track of whether we saw `[`, and how often.  This is so
            // that the string `[foo|bar][=[on|off]]|help` won't be split at
            // every interval as `["[foo", "bar][=[on", "off]", "help"]`.
            // Rather, we want to ignore any delimiters inside subvariants, as
            // they will be handled in recursive calls to extractVariants().
            if (str[idx] == '[')
                brackets++;
            else if (str[idx] == ']')
                brackets--;
            variation ~= str[idx];
        }
    }
    assert(brackets == 0);
    ret ~= variation;

    return ret;
}

private // unittest
{
    static assert("".splitVariations() == [""]);
    static assert("on|safeonly|off".splitVariations() ==
                  ["on", "safeonly", "off"]);
    static assert("[foo|bar][=[on|off]]|h|help|?".splitVariations() ==
                  ["[foo|bar][=[on|off]]", "h", "help", "?"]);
}

// Extract all pattern variants in `pattern` and return as an array.
// For example, `[foo|bar]baz` would be expanded as `[foobaz, barbaz]`.
string[] extractVariants(string pattern)
{
    // Find the first positions of `[` and `]` if any.
    ptrdiff_t beg = pattern.indexOf('[');
    ptrdiff_t end = pattern.indexOf(']');
    string[] ret;

    // Variant found that requires expansion.  What follows here is the
    // determination that the index of `]` pointed at by `end` is the correct
    // matching closing bracket for the opening `[` pointed at by `beg`.
    // This is done by ensuring that the index of the next opening `[` does not
    // fall inside the range `beg .. end`, and if it does, then `end` needs to
    // be adjusted to point at the next closing `]` in the pattern string.
    if (beg > -1 && end > beg)
    {
        // `brackets` are the number of opening `[` found between `beg .. end`.
        // `pos` is the index position in the pattern string of the next
        // opening `[` found between `beg + 1 .. $`
        int brackets = 1;
        ptrdiff_t pos = beg;

        // Find the closing `]` for the opening `[`.
        while (brackets > 0)
        {
            if (pos < end)
            {
                // `pos` is found between `[beg .. end]`, advance to the next
                // opening `[` in the pattern.  If `brackets > 1`, then we are
                // inside a nested bracket, and `end` will need to be adjusted
                // `brackets - 1` times to get the matching closing bracket.
                ptrdiff_t next = (pattern[pos + 1 .. $]).indexOf('[');
                // If not found, set to end of pattern to finish the search.
                if (next < 0)
                    pos = pattern.length;
                else
                    pos += next + 1;
            }
            else
            {
                // `pos` is outside of `[beg .. end]`, adjust `end` to the next
                // closing `]` in the pattern. If `brackets >= 1`, then we are
                // inside a nested bracket, and `end` will need to be adjusted
                // another `brackets` times to get the matching closing bracket.
                ptrdiff_t next = (pattern[end + 1.. $]).indexOf(']');
                assert (next != -1);
                end += next + 1;
            }

            if (pos < end)
            {
                // Nested `[` found, current indexes of `pos` and `end` in the
                // pattern string will look like `[beg .. [pos .. end] .. ]`.
                brackets++;
            }
            else
            {
                // Close nesting level, if `brackets == 1`, then current indexes
                // in the pattern will look like `[beg .. end][pos .. ]`.
                // If `brackets > 1`, then `end` still needs adjusting and the
                // current indexes of `pos` and `end` in the pattern will
                // instead look like `[beg .. [ .. end] .. ][pos .. ]`.
                brackets--;
            }
        }

        // Split out all variations between `[beg .. | .. end]`.
        string[] variations = pattern[beg + 1 .. end].splitVariations();

        // Start building all variants of the pattern.
        string[] variants;
        foreach (variation; variations)
        {
            // Replace `<...>` variations, with `*`.  This is understood by
            // `gdmd.driver.CheckValue` to mean that any or no value can be
            // matched for the option this pattern is for.
            if (variation[0] == '<' && variation[$ - 1] == '>')
            {
                variation = "*";
                // Don't add `*` more than once.
                bool found;
                foreach (variant; variants)
                {
                    if (variant == variation)
                    {
                        found = true;
                        break;
                    }
                }
                if (found)
                    continue;
            }

            // If we see that the current slice in the pattern is followed by
            // an opening `[`, such as `[option][=on]`, then take that to mean
            // the `[=on]` part is optional.  Add two variants, first for
            // `option`, and second for `option[=on]`.
            if (end + 1 < pattern.length && pattern[end + 1] == '[')
            {
                ptrdiff_t optend = end + 2;
                brackets = 1;

                while (brackets > 0)
                {
                    if (pattern[optend] == '[')
                        brackets++;
                    else if (pattern[optend] == ']')
                        brackets--;
                    optend++;
                }
                variants ~= pattern[0 .. beg] ~ variation ~ pattern[optend .. $];
            }
            // Include the pattern before and after the variation slice, such
            // that `h[e|a]llo` gets the variants `["hello", "hallo"]`.
            variants ~= pattern[0 .. beg] ~ variation ~ pattern[end + 1 .. $];
        }

        // Check all variants for nested brackets, and expand them as well.
        foreach (variant; variants)
        {
            foreach (extracted; extractVariants(variant))
                ret ~= extracted;
        }
    }
    else
    {
        // No `[...]` variants found that require expansion.  Check the pattern
        // for /^<...>$/, and replace it with `*`.  This is understood by
        // `gdmd.driver.checkValue` to mean that any or no value can be matched
        // for the option this pattern is for.
        if (pattern[0] == '<' && pattern[$ - 1] == '>')
        {
            // Don't add `*` more than once.
            foreach (r; ret)
            {
                if (r == "*")
                    return ret;
            }
            ret ~= "*";
        }
        else
            ret ~= pattern;
    }
    return ret;
}

private // unittest
{
    static assert(extractVariants("h[e|a]llo") == ["hello", "hallo"]);
    static assert(extractVariants("h[e|a][l]lo") ==
                  ["helo", "hello", "halo", "hallo"]);
    static assert(extractVariants("[h|help|?]") == ["h", "help", "?"]);
    static assert(extractVariants("check[=[on|off]]") ==
                  ["check=on", "check=off"]);
    static assert(extractVariants("[check][=[on|off]]") ==
                  ["check", "check=on", "check=off"]);
    static assert(extractVariants("<name>") == ["*"]);
    static assert(extractVariants("[<level>|<ident>]") == ["*"]);
}
