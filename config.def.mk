PREFIX?=/usr/local
INCLUDEDIR?=${PREFIX}/include
LIBDIR?=${PREFIX}/lib
DESTDIR?=
PKGCONFIGDIR?=${LIBDIR}/pkgconfig
SHAREDSUFFIX?=.so
STATICSUFFIX?=.a
VERSIONPOS?=suffix

CC?=cc
CFLAGS?=-O0 -g -ffast-math -freciprocal-math -fno-trapping-math
LDFLAGS?=
AR?=ar
ARFLAGS?=rv
LEX?=lex
LEXFLAGS=-8 -X

CFLAGS+=-Wall -Wextra -Wmissing-prototypes -Wredundant-decls
CFLAGS+=-Iinclude

LIBS=-lm
STATIC=-lm
