.SUFFIXES: .o .c

include config.mk

NEVM_SRCS=src/nevm.c

NEASM_GEN_SRCS=src/neasm.c

NEASM_SRCS=

TESTSRCS=

NEVM_OBJS=${NEVM_SRCS:.c=.o}
NEASM_OBJS=${NEASM_GEN_SRCS:.c=.o} ${NEASM_SRCS:.c=.o}
TESTOBJS=${TESTSRCS:.c=.o}

.PHONY: all
all: nevm neasm

.l.c:
	${LEX} ${LEXFLAGS} -o $@ $<
.c.o:
	${CC} ${CFLAGS} -c -o $@ $<

nevm: ${NEVM_OBJS}
	${CC} ${CFLAGS} ${LDFLAGS} ${NEVM_OBJS} ${NEVM_LIBS} -o nevm

neasm: ${NEASM_GEN_SRCS} ${NEASM_OBJS}
	${CC} ${CFLAGS} ${LDFLAGS} ${NEASM_OBJS} ${NEASM_LIBS} -o neasm

unittest: ${TESTOBJS}
	${CC} ${CFLAGS} ${LDFLAGS} -L`pwd` -Wl,-rpath,`pwd` \
	      ${TESTOBJS} ${TESTLIBS} -o unittest

.PHONY: install
install:
	(umask 022; mkdir -p ${DESTDIR}${BINDIR})
	install -m 755 nevm ${DESTDIR}${BINDIR}/nevm
	install -m 755 neasm ${DESTDIR}${BINDIR}/neasm

.PHONY: install-strip
install-strip: install
	strip --strip-unneeded ${DESTDIR}${BINDIR}/nevm
	strip --strip-unneeded ${DESTDIR}${BINDIR}/neasm

.PHONY: uninstall
uninstall:
	rm -f ${DESTDIR}${BINDIR}/nevm
	rm -f ${DESTDIR}${BINDIR}/neasm

.PHONY: clean
clean:
	rm -f nevm
	rm -f neasm
	rm -f ${NEVM_OBJS}
	rm -f ${NEASM_OBJS}
	rm -f ${NEASM_GEN_SRCS}
	rm -f ${TESTOBJS}
	rm -f unittest
	rm -f helloworld branch tenprint

.PHONY: check
check: unittest
	./unittest

.PHONY: examples
examples: branch helloworld tenprint

branch: examples/branch.s neasm
	./neasm -o branch examples/branch.s

helloworld: examples/helloworld.s neasm
	./neasm -o helloworld examples/helloworld.s

tenprint: examples/tenprint.s neasm
	./neasm -o tenprint examples/tenprint.s
