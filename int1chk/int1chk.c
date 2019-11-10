#include <stdio.h>
#include <dos.h>

struct calldata {
       unsigned char far *rcsip;
       int rflags;
       unsigned char far *rcsip2;
       int rflags2;
};

struct calldata last_int1_calls[20];
int i1call_count;
int i1call_writeptr;

#define ARRAY_SIZE(arr_) (sizeof(arr_)/sizeof(arr_[0]))

const unsigned char just_iret = 0xCF;

void interrupt singlestep(int rbp, int rdi, int rsi, int res, int rds,
                          int rdx, int rcx, int rbx, int rax,
                          int rip, int rcs, int rflags,
                          int rip2,int rcs2,int rflags2)
{
    last_int1_calls[i1call_writeptr].rcsip = MK_FP(rcs, rip);
    last_int1_calls[i1call_writeptr].rflags = rflags;
    last_int1_calls[i1call_writeptr].rcsip2 = MK_FP(rcs2, rip2);
    last_int1_calls[i1call_writeptr].rflags2 = rflags2;
    i1call_writeptr = (i1call_writeptr + 1) % ARRAY_SIZE(last_int1_calls);
    if (i1call_count < ARRAY_SIZE(last_int1_calls))
    {
        i1call_count++;
    }
    delay(10);
}

int main()
{
    void (interrupt *timer_irq)(void);
    timer_irq = getvect(8);
    setvect(0xA1, (void(interrupt*)(void))&just_iret);
    setvect(1, singlestep);

                                // OPCODE         I1/dosbox  I1/XT
    __emit__(0x9C);             // pushf
    __emit__(0xB8, 0x0300u);    // mov  ax, 0x300
    __emit__(0x50);             // push ax
    __emit__(0x9D);             // popf
    __emit__(0xB8, 0x1234u);    // mov  ax, 0x1234  no        no
    __emit__(0xB3, 1);          // mov  bl, 1       YES       no
    __emit__(0x40);             // inc  ax          YES       YES
    __emit__(0x8C, 0xDA);       // mov  dx, ds      YES       YES
    __emit__(0x8E, 0xC2);       // mov  es, ax      YES       YES
    __emit__(0x90);             // nop              YES       no
    __emit__(0x8C, 0xD2);       // mov  dx, ss      YES       YES
    __emit__(0x8E, 0xD2);       // mov  ss, dx      YES       YES
    __emit__(0x90);             // nop              no        no
    __emit__(0xCD, 0xA1);       // int  0xA1        YES       YES
        // first insn of IntA1  //   iret           no      YES/NoTF -> int 0xA1
    __emit__(0x49);             // dec  cx          no        no
    __emit__(0x9D);             // popf             YES       YES
    __emit__(0x48);             // dex  ax        YES/NoTF  YES/NoTF

        // Timer-IRQ (1st insn) //                  no      YES/NoTF
    while(i1call_count)
    {
        struct calldata *cur;
        cur = &last_int1_calls[(i1call_writeptr
                                + 2*ARRAY_SIZE(last_int1_calls)
                                - i1call_count
                                ) % ARRAY_SIZE(last_int1_calls)];
        if (cur->rflags & 0x100)
            printf("     %Fp %02X\n", cur->rcsip, *cur->rcsip);
        else
        {
            if (cur->rcsip == &just_iret)
                printf("IntA1 from %Fp\n", cur->rcsip2);
            else if(cur->rcsip == (void far*)timer_irq)
                printf("IRQ 0 from %Fp\n", cur->rcsip2);
            else
                printf("NoTF %Fp %02X\n", cur->rcsip, *cur->rcsip);
        }
        i1call_count--;
    }
    return 0;
}