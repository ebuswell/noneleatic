%{

#include <stdint.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <search.h>
#include <math.h>
#include <ctype.h>
#include "arg.h"

#define SYMT_LEN 4096
#define AST_LEN	1024

typedef union {
	uint64_t z;
	int64_t l;
	double d;
	uint32_t u;
	int32_t i;
	float f;
	uint16_t h;
	int16_t s;
	uint8_t c;
	int8_t b;
	char op[4];
	char buf[16];
} atom;

typedef struct {
	atom data;
	uint32_t size;
	int lineno;
	char *symbol;
	int setsymbol;
} lexeme;

static lexeme *ast;
static uint32_t ast_cap;
static uint32_t ast_len;
static char *infile;
static int lineno = 1;
static int qslineno;
static int cursor;

#define fatal(...) do {							\
	fprintf(stderr, __VA_ARGS__);					\
	exit(EXIT_FAILURE);						\
} while(0)

#define ensure_ast() do {						\
	if (ast_len == ast_cap) {					\
		ast_cap *= 2;						\
		ast = realloc(ast, ast_cap * sizeof(lexeme));		\
		if (ast == NULL) {					\
			fatal("Could not allocate memory for AST\n");	\
		}							\
	}								\
} while (0)

#define ast_align(align) do {						\
	while (cursor % align != 0) {					\
		ast[ast_len - 1].data.buf[ast[ast_len - 1].size++] = 0; \
		cursor++;						\
	}								\
} while (0)

#define ast_append(t, v) do {						\
	ensure_ast();							\
	ast_align(sizeof(ast[ast_len].data.t));				\
	memset(&ast[ast_len], 0, sizeof(lexeme));			\
	ast[ast_len].data.t = v;					\
	ast[ast_len].size = sizeof(ast[ast_len].data.t);		\
	ast[ast_len].lineno = lineno;					\
	ast_len++;							\
	cursor += sizeof(ast[ast_len].data.t);				\
} while (0)

#define ast_append_op(v) do {						\
	ensure_ast();							\
	ast_align(16);							\
	memset(&ast[ast_len], 0, sizeof(lexeme));			\
	memcpy(ast[ast_len].data.op, v, 4);				\
	ast[ast_len].size = 4;						\
	ast[ast_len].lineno = lineno;					\
	ast_len++;							\
	cursor += 4;							\
} while (0)

#define ast_append_sym(v) do {						\
	ensure_ast();							\
	ast_align(4);							\
	memset(&ast[ast_len], 0, sizeof(lexeme));			\
	ast[ast_len].size = 4;						\
	ast[ast_len].symbol = strdup(v);				\
	if (ast[ast_len].symbol == NULL) {				\
		fatal("Could not strdup symbol\n");			\
	}								\
	ast_len++;							\
	cursor += 4;							\
} while (0)

#define ast_append_setsym(v) do {					\
	ensure_ast();							\
	memset(&ast[ast_len], 0, sizeof(lexeme));			\
	ast[ast_len].size = 0;						\
	ast[ast_len].symbol = strdup(v);				\
	ast[ast_len].setsymbol = 1;					\
	if (ast[ast_len].symbol == NULL) {				\
		fatal("Could not strdup symbol\n");			\
	}								\
	ast_len++;							\
} while (0)

%}

%option noyywrap
%option noinput
%option nounput

%x QUOTE

OP					[_=@!&\|\^<>~\+\-\*\/%#]
TYPE					[UIFzlduifhscb]
ID					[^ \t\v\f\r\n;:_=@!&\|\^<>~\+\-\*\/%#"0-9][^ \t\v\f\r\n;:_=@!&\|\^<>~\+\-\*\/%#"]*
DEC					[1-9][0-9]*|0[0-9]*[8-9][0-9]*
OCT					0[0-7]*
HEX					0x[0-9a-fA-F]+
BIN					0b[0-1]+
FLOAT					[+-]?([0-9]+\.[0-9]+([Ee][+-]?[0-9]+)?|NAN|INFINITY)
SPACE					[ \t\v\f]

%%

{SPACE}+				/* eat whitespace */
;.*(\r\n?|\n|$)				{ lineno++; }
\r\n?|\n				{ lineno++; }

"\""					{ qslineno = lineno; BEGIN QUOTE; }
<QUOTE>"\\a"				{ ast_append(c, '\a'); }
<QUOTE>"\\b"				{ ast_append(c, '\b'); }
<QUOTE>"\\f"				{ ast_append(c, '\f'); }
<QUOTE>"\\n"				{ ast_append(c, '\n'); }
<QUOTE>"\\r"				{ ast_append(c, '\r'); }
<QUOTE>"\\t"				{ ast_append(c, '\t'); }
<QUOTE>"\\v"				{ ast_append(c, '\v'); }
<QUOTE>\\x[a-fA-F0-9][a-fA-F0-9]	{ ast_append(c, strtoull(yytext + 2, NULL, 16)); }
<QUOTE>\\[0-7][0-7]?[0-7]?		{ ast_append(c, strtoull(yytext + 1, NULL, 8)); }
<QUOTE>\\.				{ ast_append(c, *(((uint8_t *) yytext) + 1)); }
<QUOTE>"\""				BEGIN INITIAL;
<QUOTE>\r\n				{ ast_append(c, '\r'); ast_append(c, '\n'); lineno++; }
<QUOTE>\r				{ ast_append(c, '\r'); lineno++; }
<QUOTE>\n				{ ast_append(c, '\n'); lineno++; }
<QUOTE>[^"\\\r\n]			{ ast_append(c, *((uint8_t *) yytext)); }
<QUOTE><<EOF>>				{ fatal("%s:%d:Unterminated quote", infile, qslineno); }

{OP}{TYPE}{TYPE}{TYPE}			{ ast_append_op(yytext); }

{FLOAT}					{ ast_append(d, strtod(yytext, NULL)); }
{FLOAT}f				{ ast_append(f, strtof(yytext, NULL)); }

-{DEC}					{ ast_append(i, strtoll(yytext, NULL, 10)); }
-{OCT}					{ ast_append(i, strtoll(yytext, NULL, 8)); }
-{HEX}					{ ast_append(i, strtoll(yytext, NULL, 16)); }
-{BIN}					{ ast_append(i, -strtoll(yytext+3, NULL, 2)); }
\+?{DEC}				{ ast_append(u, strtoull(yytext, NULL, 10)); }
\+?{OCT}				{ ast_append(u, strtoull(yytext, NULL, 8)); }
\+?{HEX}				{ ast_append(u, strtoull(yytext, NULL, 16)); }
\+{BIN}					{ ast_append(u, strtoull(yytext+3, NULL, 2)); }
{BIN}					{ ast_append(u, strtoull(yytext+2, NULL, 2)); }

-{DEC}L					{ ast_append(l, strtoll(yytext, NULL, 10)); }
-{OCT}L					{ ast_append(l, strtoll(yytext, NULL, 8)); }
-{HEX}L					{ ast_append(l, strtoll(yytext, NULL, 16)); }
-{BIN}L					{ ast_append(l, -strtoll(yytext+3, NULL, 2)); }
\+?{DEC}L				{ ast_append(z, strtoull(yytext, NULL, 10)); }
\+?{OCT}L				{ ast_append(z, strtoull(yytext, NULL, 8)); }
\+?{HEX}L				{ ast_append(z, strtoull(yytext, NULL, 16)); }
\+{BIN}L				{ ast_append(z, strtoull(yytext+3, NULL, 2)); }
{BIN}L					{ ast_append(z, strtoull(yytext+2, NULL, 2)); }

-{DEC}S					{ ast_append(s, strtoll(yytext, NULL, 10)); }
-{OCT}S					{ ast_append(s, strtoll(yytext, NULL, 8)); }
-{HEX}S					{ ast_append(s, strtoll(yytext, NULL, 16)); }
-{BIN}S					{ ast_append(s, -strtoll(yytext+3, NULL, 2)); }
\+?{DEC}S				{ ast_append(u, strtoull(yytext, NULL, 10)); }
\+?{OCT}S				{ ast_append(u, strtoull(yytext, NULL, 8)); }
\+?{HEX}S				{ ast_append(u, strtoull(yytext, NULL, 16)); }
\+{BIN}S				{ ast_append(u, strtoull(yytext+3, NULL, 2)); }
{BIN}S					{ ast_append(u, strtoull(yytext+2, NULL, 2)); }

-{DEC}SS				{ ast_append(b, strtoll(yytext, NULL, 10)); }
-{OCT}SS				{ ast_append(b, strtoll(yytext, NULL, 8)); }
-{HEX}SS				{ ast_append(b, strtoll(yytext, NULL, 16)); }
-{BIN}SS				{ ast_append(b, -strtoll(yytext+3, NULL, 2)); }
\+?{DEC}SS				{ ast_append(c, strtoull(yytext, NULL, 10)); }
\+?{OCT}SS				{ ast_append(c, strtoull(yytext, NULL, 8)); }
\+?{HEX}SS				{ ast_append(c, strtoull(yytext, NULL, 16)); }
\+{BIN}SS				{ ast_append(c, strtoull(yytext+3, NULL, 2)); }
{BIN}SS					{ ast_append(c, strtoull(yytext+2, NULL, 2)); }

{ID}{SPACE}*:				{ yytext[--yyleng] = '\0';
					  while (isspace(yytext[yyleng - 1])) {
						  yytext[--yyleng] = '\0';
					  }
					  ast_append_setsym(yytext); }
{ID}					{ ast_append_sym(yytext); }

.					{ fatal("%s:%d:Unexpected character '%s'\n",
						infile, lineno, yytext); }

%%

static void usage(void) {
	fatal("usage: %s [-o file] file\n", argv0);
}

int main(int argc, char **argv) {
	char *outfile;
	FILE *in = NULL;
	FILE *out = NULL;
	size_t r;
	uint32_t i;
	uint32_t cursor = 0;
	ENTRY hq;
	ENTRY *hr;

	/* Parse arguments */
	ARGBEGIN {
	case 'o':
		if (out != NULL) {
			usage();
		}
		outfile = EARGF(usage());
		if (strcmp(outfile, "-") == 0) {
			out = stdout;
			outfile = "<stdout>";
			break;
		}
		out = fopen(outfile, "w");
		if (out == NULL) {
			fatal("Could not open file \"%s\": %s\n",
			      outfile, strerror(errno));
		}
		break;
	default:
		usage();
	ARG:
		if (infile != NULL) {
			usage();
		}
		infile = argv[0];
		if (strcmp(infile, "-") == 0) {
			in = stdin;
			infile = "<stdin>";
		} else {
			in = fopen(infile, "r");
			if (in == NULL) {
				fatal("Could not open file \"%s\": %s\n",
			      	      infile, strerror(errno));
			}
		}
	} ARGEND;

	/* Set default output and input */
	if (out == NULL) {
		out = stdout;
		outfile = "<stdout>";
	}
	if (in == NULL) {
		in = stdin;
		infile = "<stdin>";
	}

	/* Create AST */
	ast = malloc(sizeof(lexeme) * AST_LEN);
	if (ast == NULL) {
		fatal("Could not allocate memory for AST.");
	}
	ast_cap = AST_LEN;
	ast_len = 0;

	/* Parse input */
	yyin = in;
	yylex();
	fclose(in);

	/* Create symbol table */
	if(!hcreate(SYMT_LEN)) {
		fatal("Could not create symbol table: %s\n", strerror(errno));
	}

	/* set all symbols to their appropriate values */
	for (i = 0; i < ast_len; i++) {
		cursor += ast[i].size;
		if (ast[i].setsymbol) {
			hq.key = ast[i].symbol;
			hr = hsearch(hq, FIND);
			if (hr != NULL) {
				fatal("%s:%d:Duplicate symbol \"%s\"",
				      infile, ast[i].lineno, ast[i].symbol);
			}
			hq.data = (void *) (uintptr_t) cursor;
			hr = hsearch(hq, ENTER);
			if (hr == NULL) {
				fatal("Symbol table full\n");
			}
		}
	}

	/* write result, replacing all symbols with their values */
	for (i = 0; i < ast_len; i++) {
		if (!ast[i].setsymbol
		    && ast[i].symbol != NULL) {
			hq.key = ast[i].symbol;
			hr = hsearch(hq, FIND);
			if (hr == NULL) {
				fatal("%s:%d:Unknown symbol \"%s\"",
				      infile, ast[i].lineno, ast[i].symbol);
			}
			ast[i].data.u = (uint32_t) hr->data;
		}
		r = fwrite(&ast[i].data.buf, 1, ast[i].size, out);
		if (r != (size_t) ast[i].size) {
			fatal("Could not write to file \"%s\": %s",
			      outfile, strerror(errno));
		}
	}
	fclose(out);
}
