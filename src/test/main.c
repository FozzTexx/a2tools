#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <errno.h>
#include <conio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <time.h>
#include "dputc.h"
#include "scroll.h"
#include "scrollwindow.h"
#include "platform.h"

int main(int argc, char *argv[]) {
  //while(1) {
  dputc(0x07);
  platform_sleep(1);
  dputc(0x07);
  //}
  printf("done\n");
  cgetc();
}
