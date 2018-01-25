PREFIX?=/usr/local
BINDIR?=${PREFIX}/bin
DESTDIR?=

CC?=cc
CFLAGS?=-O0 -g
LDFLAGS?=
LEX?=lex
LEXFLAGS=-8 -X

CFLAGS+=-Wall -Wextra -Wmissing-prototypes -Wredundant-decls
CFLAGS+=-Iinclude

NEVM_LIBS?=-lcurses -lm
NEASM_LIBS?=-ll
TESTLIBS?=
