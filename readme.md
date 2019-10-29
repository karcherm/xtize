XTIZE
=====

Goal
----

The goal of the XTIZE project is to be able to run unmodified executables generated
by Borland/Turbo C or Microsoft C targetting the 286 instruction set on a 8088 class
computer, aka an XT.

The performance of an XT is quite limited. The performance of emulation without
suitable hardware assistance (heck! the 8088 does not even have an invalid opcode
trap) is even more limited. XTIZE is not supposed to be magic, but it will definitely
cause a notable slowdown compared to native 8088 executables.

This project was started because I got annoyed that soft configuration and
initialization tools for plug-in cards like sound cards that were put to the
market in the early 90's often are compiled targetting a 286 processor, although
the hardware component itself would work adequately in an XT class computer. I
decided against manually reengineering the tools, and I considered an "80286 emulating
automatic debugger" that breaks on all 286 instructions and emulates them a viable way.

This project is developed to find out the viability of this approach - it comes with not
guarantee to ever deliver a working product. As long as this project does not even
contain just basic functionality, I don't bother to provide executables, I just publish
the source code yet.

Running hand-written 286 assembly code is *not* a goal of XTIZE. As far as I know, compilers
of the day did not generate tail calls and did not embed data between instructions of a
procedure, so tracing out the instructions of a single procedure should be a straight-forward
task. Code that breaks this assumption is going to break XTIZE.

Toolchain
---------

To project is developed using Borland C++, but it should work with Turbo C as well.
The assembler file should not use any TASM features not present in MASM, so porting
it to MASM / Microsoft C should be possible, too.

Approach
--------

The first approach I am trying to test the basic viability is plain single stepping,
which is likely too slow for anything useful. Optimizations will likely be added in later.

My first intention was to auto-patch the code to contain breakpoints on the 286 instructions,
but telling code and data apart is not that easy, even if only compiler-generated code is
supported, because compilers add jump tables to the code segment, which do not parse as valid
80286 instructions.
