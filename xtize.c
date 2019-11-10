#include <stdio.h>
#include <string.h>
#include <dir.h>
#include <dos.h>

typedef unsigned char byte;

struct ExecParameters {
    unsigned env_segment;
    char far* cmdline;
    struct fcb far* arg1;
    struct fcb far* arg2;
    byte far* entry_stack;
    void (far* __cdecl entry_point)(int dummy);
    unsigned psp_segment;
};

void setpsp(unsigned newpsp)
{
    union REGS r;
    r.h.ah = 0x50;
    r.x.bx = newpsp;
    intdos(&r, &r);
}

int LoadForDebugging(const char *program, struct ExecParameters *state)
{
    union REGS r;
    struct SREGS sr;
    r.x.ax = 0x4B01;
    sr.es  = FP_SEG((void far*)state);
    r.x.bx = FP_OFF((void far*)state);
    sr.ds  = FP_SEG((void far*)program);
    r.x.dx = FP_OFF((void far*)program);
    intdosx(&r, &r, &sr);
    if (r.x.cflag)
        return -1;
    state->psp_segment = getpsp();
    setpsp(_psp);
    return 0;
}

void far EnterSingleStep(struct ExecParameters far *state);
void interrupt CountingSS();
long far GetCount(void);
void interrupt EmulatingSS();

void do_assert_eq(const char* x, unsigned v1, unsigned v2)
{
    if (v1 != v2)
        printf("FAIL: %s - %04X != %04X\n", x, v1, v2);
}

#define ASSERT_EQ(word1, word2) do_assert_eq(#word1 ## " == " ## #word2, word1, word2)

int main(int argc, char** argv)
{
    static int i = 0x1234;
    struct ExecParameters p;
    char *target;
    p.env_segment = 0;
    p.cmdline = MK_FP(_psp, 0x81);
    p.arg1 = 0;
    p.arg2 = 0;

    if (argc == 1)
    {
        fputs("Missing program name\n", stderr);
        return 2;
    }
    if (stricmp(argv[1], "/T") == 0)
    {
        unsigned old_sp = _SP;
        unsigned new_sp;
        unsigned new_bp;
        unsigned leave_sp;
        unsigned old_bp = _BP;
        unsigned leave_bp;
        unsigned shl_80_3;
        unsigned char rol_F7_2;
        unsigned mul_3_4, mul_6_8, mul_2_5, mul_7_11;
        unsigned tempds, tempes;
        puts("Test mode.");
        setvect(0xA1, EmulatingSS);
        asm {
            int 0xA1
            //enter 10, 0
            db 0xC8, 0x0A, 0x00, 0x00
            mov     cx, sp
            mov     dx, bp
            int 0xA1
            // push 0
            db 0x6A, 0x00
            int 0xA1
            // push 0x80
            db 0x68, 0x80, 0x00
            int 0xA1
            // shl [WORD PTR bp-14], 3
            db 0xC1, 0x66, 0xF2, 0x03
            mov     bx, WORD PTR [bp-14]
            //leave
            int 0xA1
            db 0xC9

            mov     [new_sp], cx
            mov     [new_bp], dx
            mov     [shl_80_3], bx

            mov al, 0xF7
            int 0xA1
            //rol al, 2
            db 0xC0, 0xC0, 2
            mov     [rol_F7_2], al
            int 0xA1
            //ror [i], 3
            db 0xC1, 0x0E
            dw offset i
            db 3

            mov     ax, 3
            int 0xA1
            //imul  bx, ax, 4
            db      0x6B, 0xD8, 0x04
            mov     [mul_3_4], bx

            mov     bx, 6
            int 0xA1
            // imul ax, bx, 8
            db      0x6B, 0xC3, 0x08
            mov     [mul_6_8], ax

            mov     cx, 2
            int 0xA1
            // imul    bx, cx, 5
            db      0x6B, 0xD9, 0x05
            mov     [mul_2_5], bx

            mov     ax, 7
            int 0xA1
            //imul    ax, ax, 11
            db      0x6B, 0xC0, 0x0B
            mov     [mul_7_11], ax

            mov     ax, es
            int 0xA1
            mov     es, ax

            mov     ax, ss
            int 0xA1
            mov     ss, ax

            push    ds

            push    cs
            int 0xA1
            pop     ds
            mov     [tempds], ds

            pop     ds

            push    cs
            int 0xA1
            pop     es
            mov     [tempes], es
        }
        leave_bp = _BP;
        leave_sp = _SP;
        ASSERT_EQ(old_sp,      leave_sp);
        ASSERT_EQ(old_sp - 2,  new_bp);
        ASSERT_EQ(old_sp - 12, new_sp);
        ASSERT_EQ(old_bp,      leave_bp);
        ASSERT_EQ(0x80 << 3,   shl_80_3);
        ASSERT_EQ(0xDF,        rol_F7_2);
        ASSERT_EQ((0x1234 >> 3) | 0x8000, i);
        ASSERT_EQ(3*4,         mul_3_4);
        ASSERT_EQ(6*8,         mul_6_8);
        ASSERT_EQ(2*5,         mul_2_5);
        ASSERT_EQ(7*11,        mul_7_11);
        ASSERT_EQ(_CS,         tempds);
        ASSERT_EQ(_CS,         tempes);
        return 0;
    }
    target = searchpath(argv[1]);
    if (target == NULL)
    {
        fprintf(stderr, "%s not found\n", argv[1]);
        return 1;
    }

    while(*p.cmdline == ' ')
        p.cmdline++;
    while(*p.cmdline > ' ')
        p.cmdline++;
    p.cmdline--;
    *p.cmdline = *(unsigned char*)(MK_FP(_psp, 0x80)) - (FP_OFF(p.cmdline) - 0x80);
    if (LoadForDebugging(target, &p) < 0)
    {
        fputs("Error\n", stderr);
        return 1;
    }
    setvect(1, EmulatingSS);
    EnterSingleStep(&p);
    //printf("\n%ld steps observed", GetCount());
    return 0;
}