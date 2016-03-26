GDMD [![Build Status](https://travis-ci.org/jpf91/GDMD.svg?branch=master)](https://travis-ci.org/jpf91/GDMD)
=============
GDMD is a wrapper for the [GDC](http://gdcproject.org/) [D](https://dlang.org) compiler to provide a [DMD](https://dlang.org/download.html#dmd) compatible interface. GDMD is written in D and has no external dependencies.

Currently targeting DMD version: 2.066

### Building
GDMD can be build with the D package manager [dub](http://code.dlang.org/download).

We provide different dub configurations depending on the GDC version to be used with the wrapper. Use one of these build commands to build the GDMD executable.

```bash
dub build --build=release --config=gdc4.8
dub build --build=release --config=gdc4.9
dub build --build=release --config=gdc5
dub build --build=release --config=gdc6
```

### Installing GDMD
GDMD is expected to be shipped by packagers in parallel to the `gdc` executable. If GDMD is installed correctly it will automatically find the `gdc` and `ar` executables. To make this auto detection work install the `gdmd` executable into the same folder as the `gdc` executable. Rename `gdmd` to make sure it has got the same prefix and postfix as the `gdc` executable. The following tables gives some examples of the names used for searching the `gdc` and `ar` executables depending on the `gdmd` executable name.

| GDMD                       | GDC                       | AR                   |
| ---------------------------|:-------------------------:|:--------------------:|
| gdmd                       | gdc                       | ar                   |
| gdmd-4.9                   | gdc-4.9                   | ar                   |
| gdmd.exe                   | gdc.exe                   | ar.exe               |
| arm-linux-gnueabi-gdmd     | arm-linux-gnueabi-gdc     | arm-linux-gnueabi-ar |
| arm-linux-gnueabi-gdmd-4.9 | arm-linux-gnueabi-gdc-4.9 | arm-linux-gnueabi-ar |

### Using GDMD
#### Overwriting the used gdc and ar executables
GDMD provides two ways to specify the `gdc` and `ar` executables if GDMD was not installed properly or to overwrite the autodetected executables:

1. **Using command line arguments**  
   The `-gdc=` and `-ar=` options can be used to specify the respective executables. The options support absolute and 
   relative paths to executables as well as name only arguments. If only a name is passed, the executable will be 
   searched in `PATH`. If only the `-gdc` option is given, GDMD will try to derive the `ar` location from the `gdc`
   location. Command line arguments overwrite environment variables.
2. **Using environment variables**  
   It is also possible to specify the locations of `gdc` and `ar` with environment variables. GDMD will first use 
   compiler specific environment variables which depend on the name of `GDMD`. These varibles are derived from the 
   `gdmd` executable name prefixes and postfixes: `arm-linux-gnueabi-gdmd-4.9` will result in `ARM_LINUX_GNUEABI_GDC_49`
   and `ARM_LINUX_GNUEABI_AR`. The variables use upper case letters, replace `'-'` with `'_'` and strip `'.'`. The `ar`
   variable does not use the postfix.  
   If these variables are not set, GDMD will also consider the `GDMD_GDC` and `GDMD_AR` variables. All environment 
   variables can contain absolute or relative paths or a simple name which means the executable will be searched in
   PATH.

#### GDMD specific arguments

The following additional arguments are available for GDMD:

| Argument    | Example                   | Description                                         |
| ------------|:-------------------------:|:---------------------------------------------------:|
| -gdc=value  | -gdc=/usr/bin/gdc         | `gdc` executable used to compile sources.           |
| -ar=value   | -ar=/usr/bin/gdc          | `ar` executable used to generate static libraries.  |
| -vdmd       | -vdmd                     | Print all commands executed by the wrapper.         |
| -q=arg1     | -q-O3                     | Pass argument `arg1` directly to `gdc`.             |

Additionally, all parameters not processed by the wrapper will be forwarded to gdc:
```bash
gdmd src/main.d -ffunction-sections
```

#### Supported command line arguments
```
GDMD D Compiler 2.066 using
gdc (GCC) 5.3.0
Copyright (C) 2015 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

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
```
