/* Inert direct CUI root for the real suspended-job/console-host classifier.
 * No game/runtime, SDL, input, network or window APIs. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
int main(int argc,char **argv){puts("inert own console root");fflush(stdout);if(argc>1&&!strcmp(argv[1],"fast"))return 0;Sleep(argc>1?200:2500);return 0;}
