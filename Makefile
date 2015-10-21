.PHONY: shared static all install-headers install-pkgconfig install-shared \
	install-static install-static-strip install-shared-strip \
	install-all-static install-all-shared install-all-static-strip \
	install-all-shared-strip install install-strip uninstall clean \
        check-shared check-static check

.SUFFIXES: .o

include config.mk

NEVM_VERSION=0.1

NEVM_SRCS=src/nevm.c

NEVM_LIBS=

NEASM_VERSION=0.1

NEASM_GEN_SRCS=src/neasm.c

NEASM_SRCS=

NEASM_LIBS=-ll

TESTSRCS=

NEVM_OBJS=${NEVM_SRCS:.c=.o}
NEASM_OBJS=${NEASM_GEN_SRCS:.c=.o} ${NEASM_SRCS:.c=.o}
TESTOBJS=${TESTSRCS:.c=.o}

all: nevm neasm

.l.c:
	${LEX} ${LEXFLAGS} -o $@ $<
.c.o:
	${CC} ${CFLAGS} -c -o $@ $<

.c.pic.o:
	${CC} ${CFLAGS} -fPIC -c -o $@ $<

nevm: ${NEVM_OBJS}
	${CC} ${CFLAGS} ${LDFLAGS} ${NEVM_OBJS} ${NEVM_LIBS} -o nevm

neasm: ${NEASM_GEN_SRCS} ${NEASM_OBJS}
	${CC} ${CFLAGS} ${LDFLAGS} ${NEASM_OBJS} ${NEASM_LIBS} -o neasm

unittest: ${TESTOBJS}
	${CC} ${CFLAGS} ${LDFLAGS} -L`pwd` -Wl,-rpath,`pwd` \
	      ${TESTOBJS} ${LIBS} -o unittest

install-nevm: nevm
	(umask 022; mkdir -p ${DESTDIR}${BINDIR})
	install -m 755 nevm ${DESTDIR}${BINDIR}/nevm

install-neasm: neasm
	(umask 022; mkdir -p ${DESTDIR}${BINDIR})
	install -m 755 neasm ${DESTDIR}${BINDIR}/neasm

install-nevm-strip: install-nevm
	strip --strip-unneeded ${DESTDIR}${BINDIR}/nevm

install-neasm-strip: install-neasm
	strip --strip-unneeded ${DESTDIR}${BINDIR}/neasm

install-all: all install-nevm install-neasm

install-all-strip: install-all install-nevm-strip install-neasm-strip

install: install-all

uninstall-nevm: 
	rm -f ${DESTDIR}${BINDIR}/nevm

uninstall-neasm: 
	rm -f ${DESTDIR}${BINDIR}/neasm

uninstall: uninstall-nevm uninstall-neasm

clean:
	rm -f nevm
	rm -f neasm
	rm -f ${NEVM_OBJS}
	rm -f ${NEASM_OBJS}
	rm -f ${NEASM_GEN_SRCS}
	rm -f ${TESTOBJS}
	rm -f unittest

check: unittest
	./unittest
