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

The single-step emulator
------------------------

While I expected single-stepping to be too slow to be useful, it turned out to not be the case.
As the intended use case of XTIZE is hardware setup software and not productivity software, there
is a wide gap between "annoyingly slow" (which single-step emulation definitely is) and "unusably slow",
as even a one-minute run of a setup program on an XT is faster than swapping a piece of hardware into
a more modern computer, running the EEPROM modifying setup tool on that computer and swapping the piece
of hardware back. In practice, a run of the command-line hardware setup program provided with the
Aztech Sound Galaxy 16 Pro II is still within 10 seconds.

Using single-stepping for instruction emulation seems like a piece of cake at first, because you get
a single-step interrupt just before each instruction is executed. You can look at the instruction, and
if it is a 286 real-mode instruction, you emulate it. If it is a 8086 instruction, you just let the
processor execute it. And indeed, single-stepping quickly yielded first results in getting at least
something printed to the sceen when executing the hardware setup program without the necessary command
line parameters. Getting it to work "perfectly" turned out to be a considerable amount of work and
research (as always).

The main emulation primitive of the single-step emulator is "tail-call injection". If an instruction
is recognized as being in need of emulation, emulation code for that instruction is prepared (by
hot-patching a template inside the emulator), and the return address of the INT1 stack frame is
adjusted to point there. Also the TF is cleared to avoid stepping through emulator code. This
emulation code first performs the effect of the instruction to emulate using only 8086 instructions.
Then the emulation code sets up a fake INT1 frame (containing the address of the instruction following
the emulated instruction and having the TF set) and jumps into the single-step handler.

There are two main advantages of this approach: There is no interrupt stack frame on the stack and
all general-purpose registers and the flags have user-program values while the instruction is emulated.
This means the emulator does not need to fully understand operands of the instruction (although it does
need to if the emulation code is going to clobber registers. The `IMUL` emulation is a nice example of
the effort needed to deal with clobbered registers). Also it greatly simplifies emulation of stack
related instructions (like `PUSH imm8/16`, `ENTER` and `LEAVE`).

In the following situations, a single-step interrupt is triggered that is (usually) not relevant to
the currently runnning user program:

 - An external interrupt was recognized (IRQ or NMI in IBM PC naming). The debugger "gets notified" by
   getting a single-step with TF *clear* in the pushed flags and the return address pointing to the first
   instruction of the interrupt handler. As long as I assume that the user program does not install
   interrupt handlers, the emulator can just ignore this invocation of the handler. The stack frame
   looks like this:

     - IRQ handler entry offset
     - IRQ handler entry segment
     - flags with `TF` and `IF` cleared
     - user code IP
     - user code CS
     - user code flags (with `TF` set)

 - An internal interrupt is caused by the current instruction (`DIV` with error, `INT`, `INT3`, `INTO` with
   overflow flag set). The stack frame looks the same as in the case of an external interrupt. There are two
   important things to consider, though:

     - You do *not* get a single-step invocation pointing to the instruction the interrupt handler returns
       to (that is, the adderss called "user code CS:IP" in the stack frame listed above). You *do* get
       that single-step invocation for an external interrupt, though. If an `INT` instruction is followed by
       a 286 instruction, the 286 instruction is "missed" unless special precautions are taken.
     - There are BIOS and DOS requests that do not return using IRET from a software interrupt, and thus
       disable single-stepping as side effect:
          - For example, on the Phoenix XT BIOS, `INT 16h`, subfunction 1 (poll keyboard) returns using
            `RETF 2` to return the Zero Flag to indicate whether a key has been pressed.
          - The infamous partition read/write requests by DOS (`INT 25`/`INT 26`) return with `RETF` leaving
            the flags on the stack.

On the other hand, in some cases, you do *not* get a relevant single stepping interrupt:

 - As already mentioned in the previous paragraph, there is no single-step interrupt pointing to the instruction
   immediately following an instruction that triggers an sofware interrupt.

 - After any move to an segment register or popping a segment register, there is no single-step interrupt for
   the subsequent instruction. The intention is to prevent pushing the state to some invalid place for the
   single-step interrupt between setting `SS` and setting `SP` when switching stacks (Does not apply to the buggy
   first revision of the 8086/8088). This should generally be no issue for stack setup, because SP is nearly always
   initialized by a 8086-compatible MOV instruction. This *is* an issue for other destination segments, though. IBM
   observed the pattern of setting `ES` to the screen buffer segment (`B800` for color text mode page 0) immediately
   followed by multiplying the target y coordinate by 80: `IMUL BX, [bp+target_y], 80`. Missing this instruction is
   obviously fatal.

 - A conceptual issue: You never get a single-stack interrupt for the instruction you just returned to (which obviously
   would cause an infinite loop otherwise). You need to keep in mind that this also applies if the return address has been
   patched. So after emulating one instruction, you may not blindly return to the next instruction, but you need to check
   whether that instruction needs to be emulated, too. A common pattern that exhibits back-to-back 286 instructions is
   a function call with multiple constant parameters, all pushed using `PUSH imm8` or `PUSH imm16`.

The emulator deals with the challenges the following way:

 - single-step invocations with the TF clear are ignored. This gets rid of the spurious calls mentioned above, but currently
   means that user-installed hardware interrupt handlers do not undergo emulation. This is subject to change.

   - Software interrupts are dealt with by running the `INT` instruction in an injected tail call and setting TF on
     emulator-reentry. This solves several problems:

     - Setting TF after invoking the interrupt deals with the non-IRETting services mentioned above.

     - Not injecting the fix-up handler into the stack avoids issues with the `INT 25h` / `INT 26h`
       interface of MS-DOS, where the interrupt handler returns with the stack in an "unconventional
       state". The approach is independent of the way the stack looks after the handler returned.

     - Running the `INT` instruction inside emulator code and manually re-entering the single-step
       handler after the `INT` instruction returns avoids the issue that the single-step interrupt
       after a software interrupt call is "missing".

     The emulation still needs one special case: Program-terminating CP/M-like DOS calls (`INT 20h`, `INT 27h`,
     `INT 21h` with `AH = 0`) determine the identity of the caller program by looking at the return code segment.
     These instructions are just executed directly without tail-call injection.

 - Instructions that update segment registers (except SS) get copyied into an injected tail call. This moves
   the unwanted effect of missing the next instruction into emulator code. As always for injected tail calls,
   the call ends in setting up a fake stack frame to the next instruction (we were about to miss) and jumps
   into the emulator.