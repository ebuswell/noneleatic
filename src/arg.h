#ifndef ARG_H
#define ARG_H 1

static char *argv0;

/* use main(int argc, char **argv) */
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

#define EARGF(error)							\
	(argv[0][1] != '\0' ? &argv[0][1]				\
	 : argc == 1 ? (error, abort(), (char *)0)			\
	 : (argc--, argv++, argv[0]))

#define ARGF(error)							\
	(argv[0][1] != '\0' ? &argv[0][1]				\
	 : argc == 1 ? ((char *)0)					\
	 : (argc--, argv++, argv[0]))

#endif
