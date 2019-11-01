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

int main(int argc, char** argv)
{
	static int i = 0x1234;
	struct ExecParameters p;
	char *target;
	p.cmdline = MK_FP(_psp, 0x81);

	if (argc == 1)
	{
		fputs("Missing program name\n", stderr);
		return 2;
	}
	if (stricmp(argv[1], "/T") == 0)
	{
		puts("Test mode.");
		setvect(0xA1, EmulatingSS);
		asm {
			int 0xA1
			//enter 10, 0
			db 0xC8, 0x0A, 0x00, 0x00
			int 0xA1
			// push 0
			db 0x6A, 0x00
			int 0xA1
			// push 0x80
			db 0x68, 0x80, 0x00
			int 0xA1
			// shl [WORD PTR bp-12], 3
			db 0xC1, 0x66, 0xF4, 0x03
			int 0xA1
			//leave
			db 0xC9
			mov al, 0xF7
			int 0xA1
			//rol al, 2
			db 0xC0, 0xC0, 2
			int 0xA1
			//ror [i], 3
			db 0xC1, 0x0E
			dw offset i
			db 3
		}
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