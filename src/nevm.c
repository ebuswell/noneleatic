/****************************************************************************
 * nevm.c virtual machine for the noneleatic languages                      *
 *                                                                          *
 * This virtual machine follows closely to the spec in doc/machine.txt      *
 * It makes no effort to make up for big/little endian differences in the   *
 * underlying machine, and so some programs won't work the same when the VM *
 * is compiled for a machine of different endianness from the one on which  *
 * the program was written.                                                 *
 *                                                                          *
 * The general run strategy is:                                             *
 * (1) update displays                                                      *
 * (2) read IP, read and parse opcode                                       *
 * (3) advance IP - it is crucial to advance IP before actually executing   *
 *     the operation, as this way changes the operation makes to the IP     *
 *     will be reflected in the next opcode read.                           *
 * (3) execute opcode using underlying c instruction, first casting all     *
 *     data types to the opcode's return type.                              *
 *                                                                          *
 * The memory is managed as a flat, malloc'd pointer. Whenever a read or    *
 * write is made outside of the malloc'd area, the pointer is realloc'd to  *
 * be large enough to accomodate the memory. A proper implementation would  *
 * allow for sparsely allocated memory, but this isn't a proper             *
 * implementation.                                                          *
 ****************************************************************************/
#include <curses.h>
#include <time.h>
#include <ctype.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <math.h>
#include "arg.h"

#define SCREEN_ROWS 25
#define SCREEN_COLS 80
#define SCREEN_START 0xF000
#define SCREEN_LEN (SCREEN_ROWS * SCREEN_COLS)
#define SCREEN_END (SCREEN_START + SCREEN_LEN)
#define DEBUG_DEFAULT_WAIT 2
#define DEBUG_SCREEN_COLS 45

typedef struct {
	char op;
	char dst_type;
	char src1_type;
	char src2_type;
	union {
		uint32_t u;
		int32_t i;
		float f;
	} dst;
	union {
		uint32_t u;
		int32_t i;
		float f;
	} src1;
	union {
		uint32_t u;
		int32_t i;
		float f;
	} src2;
} operation;

/* the debugging screen */
WINDOW *debugscr = NULL;

/* configuration for the VM */
static struct {
	uint32_t brk_max;
	struct timespec delay;
} config = { 0xFFFF, { 0, 0 } };

/* a representation of the machine */
static struct {
	char *mem;
	uint32_t brk;
	WINDOW *screen;
} machine = { NULL, 0, NULL };

#define fatal(...) do {							\
	endwin();							\
	fprintf(stderr, __VA_ARGS__);					\
	exit(EXIT_FAILURE);						\
} while (0)


/* memory translation and addressing */

#define caddr2addr(caddr)						\
	 ((uint32_t) (((char *) (caddr)) - machine.mem))

#define addr2caddr(addr)						\
	 (machine.mem + (addr))

#define indirect(addr, ctype)						\
	(*((ctype *) addr2caddr(addr)))

#define valaddr(arg, type)						\
	(  (type) == 'U' ? caddr2addr(&(arg).u)				\
	 : (type) == 'I' ? caddr2addr(&(arg).u)				\
	 : (type) == 'F' ? caddr2addr(&(arg).u)				\
	 : (arg).u)

#define valsize(type)							\
	(  (type) == 'U' ? (uint32_t) 4					\
	 : (type) == 'I' ? (uint32_t) 4					\
	 : (type) == 'F' ? (uint32_t) 4					\
	 : (type) == 'z' ? (uint32_t) 8					\
	 : (type) == 'l' ? (uint32_t) 8					\
	 : (type) == 'd' ? (uint32_t) 8					\
	 : (type) == 'u' ? (uint32_t) 4					\
	 : (type) == 'i' ? (uint32_t) 4					\
	 : (type) == 'f' ? (uint32_t) 4					\
	 : (type) == 'h' ? (uint32_t) 2					\
	 : (type) == 's' ? (uint32_t) 2					\
	 : (type) == 'c' ? (uint32_t) 1					\
	 : (type) == 'b' ? (uint32_t) 1					\
	 : (uint32_t) 0)

#define val(arg, type, ctype)						\
	(  (type) == 'U' ? (ctype) (arg).u				\
	 : (type) == 'I' ? (ctype) (arg).i				\
	 : (type) == 'F' ? (ctype) (arg).f				\
	 : (type) == 'z' ? (ctype) indirect((arg).u, uint64_t)		\
	 : (type) == 'l' ? (ctype) indirect((arg).u, int64_t)		\
	 : (type) == 'd' ? (ctype) indirect((arg).u, double)		\
	 : (type) == 'u' ? (ctype) indirect((arg).u, uint32_t)		\
	 : (type) == 'i' ? (ctype) indirect((arg).u, int32_t)		\
	 : (type) == 'f' ? (ctype) indirect((arg).u, float)		\
	 : (type) == 'h' ? (ctype) indirect((arg).u, uint16_t)		\
	 : (type) == 's' ? (ctype) indirect((arg).u, int16_t)		\
	 : (type) == 'c' ? (ctype) indirect((arg).u, uint8_t)		\
	 : (type) == 'b' ? (ctype) indirect((arg).u, int8_t)		\
	 : (ctype) 0)


/* memory management */

static int check_brk(uint32_t addr) {
	if (addr > machine.brk) {
		void *newmem;
		if (addr > config.brk_max) {
			errno = ENOMEM;
			return -1;
		}
		newmem = realloc(machine.mem, addr);
		if (newmem == NULL) {
			return -1;
		}
		machine.mem = newmem;
		machine.brk = addr;
	}
	return 0;
}

static void assert_brk(uint32_t addr, uint32_t addr_addr) {
	if (check_brk(addr) != 0) {
		fatal("0x%x:Could not create memory for address at 0x%x: 0x%x\n",
		      indirect(0, uint32_t), addr_addr, addr);
	}
}


/* validation */

static bool is_arg_type(char arg_type) {
	switch (arg_type) {
	case 'U':
	case 'I':
	case 'F':
	case 'z':
	case 'l':
	case 'd':
	case 'u':
	case 'i':
	case 'f':
	case 'h':
	case 's':
	case 'c':
	case 'b':
		return true;
	default:
		return false;
	}
}

static void validate_arg(uint32_t addr, char arg_type,
			 uint32_t addr_addr, uint32_t arg_type_addr) {
	switch (arg_type) {
	case 'U':
	case 'I':
	case 'F':
		break;
	case 'z':
	case 'l':
	case 'd':
		assert_brk(addr + 8, addr_addr);
		break;
	case 'u':
	case 'i':
	case 'f':
		assert_brk(addr + 4, addr_addr);
		break;
	case 'h':
	case 's':
		assert_brk(addr + 2, addr_addr);
		break;
	case 'c':
	case 'b':
		assert_brk(addr + 1, addr_addr);
		break;
	default:
		fatal("0x%x:Invalid type at 0x%x: %c\n",
		      indirect(0, uint32_t), arg_type_addr, arg_type);
	}
}

static bool is_op(char op) {
	switch (op) {
	case '_': /* No op */
	case '=': /* Assign */
	case '@': /* Block transfer */
	case '!': /* Not */
	case '&': /* And */
	case '|': /* Or */
	case '^': /* Xor */
	case '<': /* Shift left */
	case '>': /* Shift right */
	case '~': /* Negate */
	case '+': /* Add */
	case '-': /* Subtract */
	case '*': /* Multiply */
	case '/': /* Divide */
	case '%': /* Remainder */
	case '#': /* Halt */
		return true;
	default:
		return false;
	}
}

static void validate_op(char op, uint32_t op_addr) {
	if (!is_op(op)) {
		fatal("0x%x:Invalid operation at 0x%x: %c\n",
		      indirect(0, uint32_t), op_addr, op);
	}
}

/* macros for translating between operations and C operations */

#define unary_op(op, cop)						\
do {									\
	switch (op->dst_type) {						\
	case 'U':							\
		op->dst.u = cop val(op->src1, op->src1_type, uint32_t); \
		break;							\
	case 'I':							\
		op->dst.i = cop val(op->src1, op->src1_type, int32_t);	\
		break;							\
	case 'F':							\
		op->dst.f = cop val(op->src1, op->src1_type, float);	\
		break;							\
	case 'z':							\
		indirect(op->dst.u, uint64_t)				\
			= cop val(op->src1, op->src1_type, uint64_t);	\
		break;							\
	case 'l':							\
		indirect(op->dst.u, int64_t)				\
			= cop val(op->src1, op->src1_type, int64_t);	\
		break;							\
	case 'd':							\
		indirect(op->dst.u, double)				\
			= cop val(op->src1, op->src1_type, double);	\
		break;							\
	case 'u':							\
		indirect(op->dst.u, uint32_t)				\
			= cop val(op->src1, op->src1_type, uint32_t);	\
		break;							\
	case 'i':							\
		indirect(op->dst.u, int32_t)				\
			= cop val(op->src1, op->src1_type, int32_t);	\
		break;							\
	case 'f':							\
		indirect(op->dst.u, float)				\
			= cop val(op->src1, op->src1_type, float);	\
		break;							\
	case 'h':							\
		indirect(op->dst.u, uint16_t)				\
			= cop val(op->src1, op->src1_type, uint16_t);	\
		break;							\
	case 's':							\
		indirect(op->dst.u, int16_t)				\
			= cop val(op->src1, op->src1_type, int16_t);	\
		break;							\
	case 'c':							\
		indirect(op->dst.u, uint8_t)				\
			= cop val(op->src1, op->src1_type, uint8_t);	\
		break;							\
	case 'b':							\
		indirect(op->dst.u, int8_t)				\
			= cop val(op->src1, op->src1_type, int8_t);	\
		break;							\
	}								\
} while (0)

#define unary_op_nofloat(op, cop)					\
do {									\
	switch (op->dst_type) {						\
	case 'U':							\
		op->dst.u = cop val(op->src1, op->src1_type, uint32_t); \
		break;							\
	case 'I':							\
		op->dst.i = cop val(op->src1, op->src1_type, int32_t);	\
		break;							\
	case 'z':							\
		indirect(op->dst.u, uint64_t)				\
			= cop val(op->src1, op->src1_type, uint64_t);	\
		break;							\
	case 'l':							\
		indirect(op->dst.u, int64_t)				\
			= cop val(op->src1, op->src1_type, int64_t);	\
		break;							\
	case 'u':							\
		indirect(op->dst.u, uint32_t)				\
			= cop val(op->src1, op->src1_type, uint32_t);	\
		break;							\
	case 'i':							\
		indirect(op->dst.u, int32_t)				\
			= cop val(op->src1, op->src1_type, int32_t);	\
		break;							\
	case 'h':							\
		indirect(op->dst.u, uint16_t)				\
			= cop val(op->src1, op->src1_type, uint16_t);	\
		break;							\
	case 's':							\
		indirect(op->dst.u, int16_t)				\
			= cop val(op->src1, op->src1_type, int16_t);	\
		break;							\
	case 'c':							\
		indirect(op->dst.u, uint8_t)				\
			= cop val(op->src1, op->src1_type, uint8_t);	\
		break;							\
	case 'b':							\
		indirect(op->dst.u, int8_t)				\
			= cop val(op->src1, op->src1_type, int8_t);	\
		break;							\
	}								\
} while (0)

#define binary_op(op, cop)						\
do {									\
	switch (op->dst_type) {						\
	case 'U':							\
		op->dst.u = val(op->src1, op->src1_type, uint32_t)	\
			    cop val(op->src2, op->src2_type, uint32_t); \
		break;							\
	case 'I':							\
		op->dst.i = val(op->src1, op->src1_type, int32_t)	\
			    cop val(op->src2, op->src2_type, int32_t);	\
		break;							\
	case 'F':							\
		op->dst.f = val(op->src1, op->src1_type, float)		\
			    cop val(op->src2, op->src2_type, float);	\
		break;							\
	case 'z':							\
		indirect(op->dst.u, uint64_t)				\
			= val(op->src1, op->src1_type, uint64_t)	\
			  cop val(op->src2, op->src2_type, uint64_t);	\
		break;							\
	case 'l':							\
		indirect(op->dst.u, int64_t)				\
			= val(op->src1, op->src1_type, int64_t)		\
			  cop val(op->src2, op->src2_type, int64_t);	\
		break;							\
	case 'd':							\
		indirect(op->dst.u, double)				\
			= val(op->src1, op->src1_type, double)		\
			  cop val(op->src2, op->src2_type, double);	\
		break;							\
	case 'u':							\
		indirect(op->dst.u, uint32_t)				\
			= val(op->src1, op->src1_type, uint32_t)	\
			  cop val(op->src2, op->src2_type, uint32_t);	\
		break;							\
	case 'i':							\
		indirect(op->dst.u, int32_t)				\
			= val(op->src1, op->src1_type, int32_t)		\
			  cop val(op->src2, op->src2_type, int32_t);	\
		break;							\
	case 'f':							\
		indirect(op->dst.u, float)				\
			= val(op->src1, op->src1_type, float)		\
			  cop val(op->src2, op->src2_type, float);	\
		break;							\
	case 'h':							\
		indirect(op->dst.u, uint16_t)				\
			= val(op->src1, op->src1_type, uint16_t)	\
			  cop val(op->src2, op->src2_type, uint16_t);	\
		break;							\
	case 's':							\
		indirect(op->dst.u, int16_t)				\
			= val(op->src1, op->src1_type, int16_t)		\
			  cop val(op->src2, op->src2_type, int16_t);	\
		break;							\
	case 'c':							\
		indirect(op->dst.u, uint8_t)				\
			= val(op->src1, op->src1_type, uint8_t)		\
			  cop val(op->src2, op->src2_type, uint8_t);	\
		break;							\
	case 'b':							\
		indirect(op->dst.u, int8_t)				\
			= val(op->src1, op->src1_type, int8_t)		\
			  cop val(op->src2, op->src2_type, int8_t);	\
		break;							\
	}								\
} while (0)

#define binary_op_nofloat(op, cop)					\
do {									\
	switch (op->dst_type) {						\
	case 'U':							\
		op->dst.u = val(op->src1, op->src1_type, uint32_t)	\
			    cop val(op->src2, op->src2_type, uint32_t); \
		break;							\
	case 'I':							\
		op->dst.i = val(op->src1, op->src1_type, int32_t)	\
			    cop val(op->src2, op->src2_type, int32_t);	\
		break;							\
	case 'z':							\
		indirect(op->dst.u, uint64_t)				\
			= val(op->src1, op->src1_type, uint64_t)	\
			  cop val(op->src2, op->src2_type, uint64_t);	\
		break;							\
	case 'l':							\
		indirect(op->dst.u, int64_t)				\
			= val(op->src1, op->src1_type, int64_t)		\
			  cop val(op->src2, op->src2_type, int64_t);	\
		break;							\
	case 'u':							\
		indirect(op->dst.u, uint32_t)				\
			= val(op->src1, op->src1_type, uint32_t)	\
			  cop val(op->src2, op->src2_type, uint32_t);	\
		break;							\
	case 'i':							\
		indirect(op->dst.u, int32_t)				\
			= val(op->src1, op->src1_type, int32_t)		\
			  cop val(op->src2, op->src2_type, int32_t);	\
		break;							\
	case 'h':							\
		indirect(op->dst.u, uint16_t)				\
			= val(op->src1, op->src1_type, uint16_t)	\
			  cop val(op->src2, op->src2_type, uint16_t);	\
		break;							\
	case 's':							\
		indirect(op->dst.u, int16_t)				\
			= val(op->src1, op->src1_type, int16_t)		\
			  cop val(op->src2, op->src2_type, int16_t);	\
		break;							\
	case 'c':							\
		indirect(op->dst.u, uint8_t)				\
			= val(op->src1, op->src1_type, uint8_t)		\
			  cop val(op->src2, op->src2_type, uint8_t);	\
		break;							\
	case 'b':							\
		indirect(op->dst.u, int8_t)				\
			= val(op->src1, op->src1_type, int8_t)		\
			  cop val(op->src2, op->src2_type, int8_t);	\
		break;							\
	}								\
} while (0)

/* display update routines */

#define debug_printop(i) do {						\
	int j;								\
	wprintw(debugscr, "%.4s", addr2caddr(i));			\
	i += 4;								\
	for (j = 1; j < 4; j++) {					\
		wprintw(debugscr, " ");					\
		debug_printword(i);					\
	}								\
} while (0)

#define debug_printword(i) do {						\
	if (isprint(indirect(i, char))					\
	    && isprint(indirect(i + 1, char))				\
	    && isprint(indirect(i + 2, char))				\
	    && isprint(indirect(i + 3, char))) {			\
		/* printable */						\
		wprintw(debugscr, "%.4s", addr2caddr(i));		\
	} else {							\
		/* number */						\
		wprintw(debugscr, "0x%x", indirect(i, uint32_t));	\
	}								\
	i += 4;								\
} while (0)


static void update_debugscr() {
	uint32_t i;
	int row;
	werase(debugscr);
	for (i = 0, row = 0; i < machine.brk && row < getmaxy(debugscr);
	     row++) {
		mvwprintw(debugscr, row, 0, "0x%03x: ", i);
		if (i % 16 == 0 && is_op(indirect(i, char))
		    && is_arg_type(indirect(i + 1, char))
		    && is_arg_type(indirect(i + 2, char))
		    && is_arg_type(indirect(i + 3, char))) {
			debug_printop(i);
	    	} else {
 		       debug_printword(i);
		}
	}
	wrefresh(debugscr);
}

static void update_screen() {
	int i;
	werase(machine.screen);
	for (i = 0; i < SCREEN_ROWS; i++) {
		mvwaddnstr(machine.screen, i, 0,
			   addr2caddr(SCREEN_START + i*SCREEN_COLS),
			   SCREEN_COLS);
	}
	wrefresh(machine.screen);
}


/* the VM run loop */

static void run() {
	operation *op;
	uint32_t ip;
	int r;
	for (;;) {
		/* update screens */
		if (debugscr != NULL) {
			update_debugscr();
		}
		update_screen();

		/* delay, if specified */
		nanosleep(&config.delay, NULL);

		/* read the IP */
		ip = indirect(0, uint32_t);

		/* check that the IP is pointing to existing memory */
		r = check_brk(ip + sizeof(operation));
		if (r != 0) {
			fatal("Invalid IP: 0x%x\n", ip);
		}
		/* read the operation */
		op = (operation *) (machine.mem + ip);
		/* validate the operation and its arguments */
		validate_op(op->op, caddr2addr(&op->op));
		validate_arg(op->dst.u, op->dst_type,
			     caddr2addr(&op->dst.u),
			     caddr2addr(&op->dst_type));
		validate_arg(op->src1.u, op->src1_type,
			     caddr2addr(&op->src1.u),
			     caddr2addr(&op->src1_type));
		validate_arg(op->src2.u, op->src2_type,
			     caddr2addr(&op->src2.u),
			     caddr2addr(&op->src2_type));
		/* op-specific validation */
		switch (op->op) {
		case '@':
			assert_brk(valaddr(op->dst, op->dst_type)
				   + valsize(op->dst_type)
				     * val(op->src2, op->src2_type, uint32_t),
				   caddr2addr(&op->dst.u));
			assert_brk(valaddr(op->src1, op->src1_type)
				   + valsize(op->dst_type)
				     * val(op->src2, op->src2_type, uint32_t),
				   caddr2addr(&op->src1.u));
			break;
		case '!':
		case '&':
		case '|':
		case '^':
		case '<':
		case '>':
			if (op->dst_type == 'F'
			    || op->dst_type == 'f'
			    || op->dst_type == 'd') {
				fatal("0x%x:Invalid type at 0x%x: %c. Floating"
				      " type cannot be used with bitwise"
				      " operator %c\n",
				      ip, caddr2addr(&op->dst_type),
				      op->dst_type, op->op);
			}
			break;
		}
		/* advance the IP */
		indirect(0, uint32_t) = ip + sizeof(operation);
		/* perform the operation */
		switch (op->op) {
		case '_':
			/* No-op */
			break;
		case '=':
			/* Assign */
			unary_op(op, +);
			break;
		case '@':
			memmove(addr2caddr(valaddr(op->dst, op->dst_type)),
				addr2caddr(valaddr(op->src1, op->src1_type)),
				valsize(op->dst_type)
				  * val(op->src2, op->src2_type, uint32_t));
			break;
		case '!':
			unary_op_nofloat(op, ~);
			break;
		case '&':
			binary_op_nofloat(op, &);
			break;
		case '|':
			binary_op_nofloat(op, |);
			break;
		case '^':
			binary_op_nofloat(op, ^);
			break;
		case '<':
			binary_op_nofloat(op, <<);
			break;
		case '>':
			binary_op_nofloat(op, >>);
			break;
		case '~':
			unary_op(op, -);
			break;
		case '+':
			binary_op(op, +);
			break;
		case '-':
			binary_op(op, -);
			break;
		case '*':
			binary_op(op, *);
			break;
		case '/':
			binary_op(op, /);
			break;
		case '%':
			switch (op->dst_type) {
			case 'F':
				op->dst.f
				  = fmodf(val(op->src1, op->src1_type, float),
					  val(op->src2, op->src2_type, float));
				break;
			case 'f':
				indirect(op->dst.u, float)
				  = fmodf(val(op->src1, op->src1_type, float),
					  val(op->src2, op->src2_type, float));
				break;
			case 'd':
				indirect(op->dst.u, double)
				  = fmod(val(op->src1, op->src1_type, double),
					 val(op->src2, op->src2_type, double));
				break;
			default:
				binary_op_nofloat(op, %);
				break;
			}
			break;
		case '#':
			return;
		}
	}
}

/* arguments and file loading */

static void usage() {
	fatal("%s [-d delay] [-g] [-l location] file [[-l location] file] ...\n",
	      argv0);
}

#define FILE_CHUNK 4096

static void load_file(uint32_t *mem_cursor, char *filename) {
	FILE *f;
	size_t r;
	fprintf(stderr, "Loading %s at %u\n", filename, *mem_cursor);
	f = fopen(filename, "r");
	if (f == NULL) {
		fatal("Couldn't open file \"%s\": %s\n",
		      filename, strerror(errno));
	}
	for (;;) {
		if (check_brk(*mem_cursor + FILE_CHUNK) != 0) {
			fatal("Could not create memory for file \"%s\" at %u\n",
			      filename, *mem_cursor + FILE_CHUNK);
		}
		r = fread(addr2caddr(*mem_cursor), 1, FILE_CHUNK, f);
		*mem_cursor += r;
		if (r != FILE_CHUNK) {
			if (feof(f)) {
				fclose(f);
				return;
			} else if (ferror(f)) {
				fatal("Couldn't read from file \"%s\": %s\n",
				      filename, strerror(errno));
			}
		}
	}
}

int main(int argc, char **argv) {
	uint32_t mem_cursor = 0;
	bool delay_set = false, debug = false;
	double delay, delay_f;

	/* parse arguments and load files */
	ARGBEGIN {
	case 'l':
		mem_cursor = atoi(EARGF(usage()));
		break;
	case 'd':
		/* set delay */
		delay_f = modf(atof(EARGF(usage())), &delay);
		config.delay.tv_sec
			= (typeof(config.delay.tv_sec))delay;
		config.delay.tv_nsec
			= (typeof(config.delay.tv_nsec))(delay_f*1000000000.0f);
		delay_set = true;
		break;
	case 'g':
		/* enter debugging mode */
		debug = true;
		break;
	default:
		usage();
	ARG:
		load_file(&mem_cursor, argv[0]);
	} ARGEND;

	if (machine.brk == 0) {
		/* nothing was loaded */
		usage();
	}

	/* initialize curses */
	initscr(); curs_set(0); cbreak(); noecho(); clear();
	machine.screen = stdscr;
	debugscr = NULL;
	/* set up debugging */
	if (debug) {
		/* set delay time */
		if (!delay_set) {
			config.delay.tv_sec = DEBUG_DEFAULT_WAIT;
		}
		/* split into two windows, if possible */
		if (getmaxx(stdscr) > SCREEN_COLS + DEBUG_SCREEN_COLS) {
			/* vertical windows */
			machine.screen = newwin(getmaxy(stdscr), SCREEN_COLS,
						0, 0);
			debugscr = newwin(getmaxy(stdscr),
					  DEBUG_SCREEN_COLS, 0,
					  getmaxx(stdscr) - DEBUG_SCREEN_COLS);
		} else if (getmaxy(stdscr) > SCREEN_ROWS) {
			/* horizontal windows */
			machine.screen = newwin(SCREEN_ROWS, getmaxx(stdscr),
						0, 0);
			debugscr = newwin(getmaxy(stdscr) - SCREEN_ROWS - 1,
					  getmaxx(stdscr),
					  SCREEN_ROWS + 1, 0);
		}
	}
	/* run the vm */
	run();
	/* wait for a key press */
	wgetch(machine.screen);
	/* tear down curses */
	endwin();

	exit(EXIT_SUCCESS);
}
