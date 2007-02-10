/*
 * gcc -I/usr/include/rpm -o rpmvercmp rpmvercmp.c -lrpm -lpopt
 */
#include <stdio.h>
#include <stdlib.h>
#include <rpm/rpmbuild.h>

int main (int ac, char *av[])
{
   int r;
   
   if (ac != 3)
     {
	fprintf (stderr, "%s ver1 ver2\n", av[0]);
	exit (EXIT_SUCCESS);
     }
   r = rpmvercmp (av[1], av[2]);
   if (r > 0)
     printf (">\n");
   else if (r == 0)
     printf ("=\n");
   else
     printf ("<\n");

   return r;
}
