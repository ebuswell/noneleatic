/******************************************
 * arg.h Parse arguments in Unix style    *
 *                                        *
 * Copied with changes from 20h's version *
 ******************************************/
#ifndef ARG_H
#define ARG_H 1

static char *argv0; /* argv[0] - the name of the program as called */

/* Use as:
 * ARGBEGIN {
 *         case 'a': option a
 *         case 'b': option b
 *         default: an option that isn't caught by a or b
 *         ARG: a non-option argument
 * } ARGEND;
 * note: depends on standard main naming, i.e. main(int argc, char **argv) */
#define ARGBEGIN							\
	do {								\
	for (argv0 = *argv, argv++, argc--; argc > 0; argv++, argc--) {	\
		int argdone = 0;					\
		int thisc = 0;						\
		if (argv[0][0] != '-') {				\
			goto ARG;					\
		} else if (argv[0][1] == '-' && argv[0][2] == '\0') {	\
 			argv++, argc--;					\
			if (argc == 0) {				\
				break;					\
			}						\
			goto ARG;					\
		} else if (argv[0][1] == '\0') {			\
			goto ARG;					\
		}							\
		for (thisc = argc, argv[0]++;				\
		     thisc == argc && argv[0][0]; argv[0]++) {		\
			switch (argv[0][0])

#define ARGEND								\
		}							\
		if (argdone) {						\
 			argv++, argc--;					\
			if (argc == 0) {				\
				break;					\
			}						\
			goto ARG;					\
		}							\
	}								\
	} while (0)

/* Get the argument to an option, which gets arg when specified as -o arg
 * or as -oarg. This version aborts via error if arg isn't specified. */
#define EARGF(error)							\
	(argv[0][1] != '\0' ? &argv[0][1]				\
	 : argc == 1 ? (error, abort(), (char *)0)			\
	 : (argc--, argv++, argv[0]))

/* Same as EARGF but returns null instead of aborting. */
#define ARGF(error)							\
	(argv[0][1] != '\0' ? &argv[0][1]				\
	 : argc == 1 ? ((char *)0)					\
	 : (argc--, argv++, argv[0]))

#endif
