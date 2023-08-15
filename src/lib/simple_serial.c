/*
 * Copyright (C) 2022 Colin Leroy-Mira <colin@colino.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "simple_serial.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <errno.h>
#include "extended_conio.h"
#include "extended_string.h"

#ifdef __CC65__
#pragma static-locals(push, on)
#ifdef SURL_TO_LANGCARD
#pragma code-name (push, "LC")
#else
#pragma code-name (push, "LOWCODE")
#endif
#endif

static char serial_activity_indicator_enabled = 0;
static signed char serial_activity_indicator_x = -1;
static signed char serial_activity_indicator_y = -1;

void __fastcall__ simple_serial_set_activity_indicator(char enabled, int x, int y) {
  serial_activity_indicator_enabled = enabled;
  serial_activity_indicator_x = x;
  serial_activity_indicator_y = y;
}

#ifdef __CC65__
static void __fastcall__ activity_cb(int on) {
  char x, y;
  x = wherex();
  y = wherey();

  if (serial_activity_indicator_x == -1) {
    serial_activity_indicator_x = x;
    serial_activity_indicator_y = y;
  }

  gotoxy(serial_activity_indicator_x, serial_activity_indicator_y);
  cputc(on ? '*' : ' ');
  gotoxy(x, y);
}

/* Setup */
static int last_slot = 2;
static int last_baudrate = SER_BAUD_9600;

static struct ser_params default_params = {
    SER_BAUD_9600,     /* Baudrate */
    SER_BITS_8,         /* Number of data bits */
    SER_STOP_1,         /* Number of stop bits */
    SER_PAR_NONE,       /* Parity setting */
    SER_HS_HW           /* Type of handshake to use */
};

int __fastcall__ simple_serial_open(int slot, int baudrate) {
  int err;
  
#ifdef __APPLE2__
  if ((err = ser_install(&a2e_ssc_ser)) != 0)
    return err;
#endif

#ifdef __APPLE2__
  if ((err = ser_apple2_slot(slot)) != 0)
    return err;
#endif

  default_params.baudrate = baudrate;
  /* HW flow control ignored as it's always on */

  err = ser_open (&default_params);

  last_slot = slot;
  last_baudrate = baudrate;

  return err;
}

int __fastcall__ simple_serial_close(void) {
  return ser_close();
}

void __fastcall__ simple_serial_flush(void) {
  while(simple_serial_getc_with_timeout() != EOF);
}

#pragma optimize(push, on)
int __fastcall__ simple_serial_getc_immediate(void) {
  static char c;
  if (ser_get(&c) != SER_ERR_NO_DATA) {
    return c;
  }
  return EOF;
}

static int timeout_cycles = -1;

/* Input */
int __fastcall__ simple_serial_getc_with_timeout(void) {
    static char c;

    timeout_cycles = 10000;

    while (ser_get(&c) == SER_ERR_NO_DATA) {
      if (--timeout_cycles == 0) {
        return EOF;
      }
    }
    return (int)c;
}

char __fastcall__ simple_serial_getc(void) {
    static char c;

    while (ser_get(&c) == SER_ERR_NO_DATA);
    return c;
}

/* Output */
// static int send_delay;
int __fastcall__ simple_serial_putc(char c) {
  if ((ser_put(c)) != SER_ERR_OVERFLOW) {
    return c;
  }

  return EOF;
}
#pragma optimize(pop)

#else
/* POSIX */
#include <termios.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/ioctl.h>

#define DELAY_MS 3

static FILE *ttyfp = NULL;
static int flow_control_enabled;

static char *readbuf = NULL;
static int readbuf_idx = 0;
static int readbuf_avail = 0;
static int bps = B9600;
static void setup_tty(int port, int baudrate, int hw_flow_control) {
  struct termios tty;

  if(tcgetattr(port, &tty) != 0) {
    printf("tcgetattr error: %s\n", strerror(errno));
    close(port);
    exit(1);
  }
  cfsetispeed(&tty, baudrate);
  cfsetospeed(&tty, baudrate);

  bps = baudrate;

  tty.c_cflag &= ~PARENB;
  tty.c_cflag &= ~CSTOPB;
  tty.c_cflag |= CS8;
  tty.c_cflag |= CREAD | CLOCAL;

  if (hw_flow_control)
    tty.c_cflag |= CRTSCTS;
  else
    tty.c_cflag &= ~CRTSCTS;

  flow_control_enabled = hw_flow_control;

  tty.c_lflag &= ~ICANON;
  tty.c_lflag &= ~ECHO;
  tty.c_lflag &= ~ISIG;
  tty.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);

  tty.c_iflag &= ~(IXON | IXOFF | IXANY);
  tty.c_iflag &= ~(IGNBRK|BRKINT|PARMRK|ISTRIP|INLCR|IGNCR|ICRNL);

  tty.c_oflag &= ~OPOST;
  tty.c_oflag &= ~ONLCR;

  if (tcsetattr(port, TCSANOW, &tty) != 0) {
    printf("tcgetattr error: %s\n", strerror(errno));
    exit(1);
  }
}

#include "simple_serial_opts.c"

int simple_serial_open(void) {
  struct flock lock;

  lock.l_start = 0;
  lock.l_len = 0;
  lock.l_pid = getpid();
  lock.l_type = F_WRLCK;
  lock.l_whence = SEEK_SET;

  /* Get options */
  simple_serial_read_opts();
  
  /* Open file */
  ttyfp = fopen(opt_tty_path, "r+b");

  /* Try to lock file */
  if (ttyfp != NULL && fcntl(fileno(ttyfp), F_SETLK, &lock) < 0) {
    printf("%s is already opened by another process.\n", opt_tty_path);
    fclose(ttyfp);
    ttyfp = NULL;
  }
  if (ttyfp == NULL) {
    printf("Can't open %s\n", opt_tty_path);
    return -1;
  }

  simple_serial_flush();
  setup_tty(fileno(ttyfp), opt_tty_speed, opt_tty_hw_handshake);

  return 0;
}

int simple_serial_close(void) {
  if (ttyfp) {
    fclose(ttyfp);
  }
  ttyfp = NULL;
  if (readbuf) {
    free(readbuf);
    readbuf = NULL;
  }
  return 0;
}

void simple_serial_flush(void) {
  struct termios tty;

  /* Disable flow control if needed */
  if (flow_control_enabled) {
    if(tcgetattr(fileno(ttyfp), &tty) != 0) {
      printf("tcgetattr error: %s\n", strerror(errno));
    }

    tty.c_cflag &= ~CRTSCTS;
    if (tcsetattr(fileno(ttyfp), TCSANOW, &tty) != 0) {
      printf("tcgetattr error: %s\n", strerror(errno));
    }
  }

  /* flush */
  tcflush(fileno(ttyfp), TCIOFLUSH);
  tcdrain(fileno(ttyfp));

  /* Reenable flow control */
  if (flow_control_enabled) {
    tty.c_cflag |= CRTSCTS;

    if (tcsetattr(fileno(ttyfp), TCSANOW, &tty) != 0) {
      printf("tcgetattr error: %s\n", strerror(errno));
    }
  }
  while(simple_serial_getc_with_timeout() != EOF);
}
/* Input 
 * Very complicated because select() won't mark fd as readable 
 * if there was more than one byte available last time and we only
 * read one. So we're doing our own buffer.
 */
int __simple_serial_getc_with_tv_timeout(int timeout, int secs, int msecs) {
  fd_set fds;
  struct timeval tv_timeout;
  int n;

  if (readbuf == NULL) {
    readbuf = malloc(16384);
  }
  
send_from_buf:
  if (readbuf_avail > 0) {
    int r = (unsigned char)readbuf[readbuf_idx];
    readbuf_idx++;
    readbuf_avail--;

    return r;
  }

try_again:
  FD_ZERO(&fds);
  FD_SET(fileno(ttyfp), &fds);

  tv_timeout.tv_sec  = secs;
  tv_timeout.tv_usec = msecs*1000;

  n = select(fileno(ttyfp) + 1, &fds, NULL, NULL, &tv_timeout);

  if (n > 0 && FD_ISSET(fileno(ttyfp), &fds)) {
    int flags = fcntl(fileno(ttyfp), F_GETFL);
    int r;
    flags |= O_NONBLOCK;
    fcntl(fileno(ttyfp), F_SETFL, flags);
    
    r = fread(readbuf, sizeof(char), 16383, ttyfp);
    if (r > 0) {
      readbuf_avail = r;
    }
    readbuf_idx = 0;

    flags &= ~O_NONBLOCK;
    fcntl(fileno(ttyfp), F_SETFL, flags);

    goto send_from_buf;
  } else if (!timeout) {
    goto try_again;
  }
  return EOF;
}

int simple_serial_getc_with_timeout(void) {
  return __simple_serial_getc_with_tv_timeout(1, 0, 500);
}

char simple_serial_getc(void) {
  return (char)__simple_serial_getc_with_tv_timeout(0, 0, 500);
}

int simple_serial_getc_immediate(void) {
  return __simple_serial_getc_with_tv_timeout(1, 0, DELAY_MS);
}

/* Output */
int __fastcall__ simple_serial_putc(char c) {
  int r = fputc(c, ttyfp);
  fflush(ttyfp);

  if (!flow_control_enabled)
    usleep(1000);

  return r;
}

#endif /* End of platform-dependant code */

#ifdef __CC65__
#pragma optimize(push, on)
#endif

void __fastcall__ simple_serial_puts(char *buf) {
#ifdef __CC65__
  if (serial_activity_indicator_enabled) {
    activity_cb(1);
  }
#endif
  while (*buf) {
    simple_serial_putc(*buf);
    ++buf;
  }

#ifdef __CC65__
  if (serial_activity_indicator_enabled) {
    activity_cb(0);
  }
#endif
}

char * __fastcall__ simple_serial_gets(char *out, size_t size) {
  static char c;
  static char *cur;
  static char *end;

  if (size == 0) {
    return NULL;
  }

#ifdef __CC65__
  if (serial_activity_indicator_enabled) {
    activity_cb(1);
  }
#endif

  cur = out;
  end = cur + size - 1;
  while (cur < end) {
#ifdef __CC65__
    while (ser_get(&c) == SER_ERR_NO_DATA);
#else
    c = simple_serial_getc();
#endif
    
    if (c == '\r') {
      /* ignore \r */
      continue;
    }

    *cur = c;
    ++cur;

    if (c == '\n') {
      break;
    }
  }
  *cur = '\0';

#ifdef __CC65__
  if (serial_activity_indicator_enabled) {
    activity_cb(0);
  }
#endif

  return out;
}

void __fastcall__ simple_serial_read(char *ptr, size_t nmemb) {
  static char *cur;
  static char *end;
#ifdef __CC65__
  if (serial_activity_indicator_enabled) {
    activity_cb(1);
  }
#endif

  cur = ptr;
  end = ptr + nmemb;
  while (cur < end) {
#ifdef __CC65__
    while (ser_get(cur) == SER_ERR_NO_DATA);
#else
    *cur = simple_serial_getc();
#endif
    ++cur;
  }

#ifdef __CC65__
  if (serial_activity_indicator_enabled) {
    activity_cb(0);
  }
#endif
}
#ifdef __CC65__
#pragma optimize(pop)
#endif

/* Wrappers */

static char *simple_serial_buf = NULL;
void simple_serial_printf(const char* format, ...) {
  va_list args;

  if (simple_serial_buf == NULL)
    simple_serial_buf = malloc(512);

  va_start(args, format);
  vsnprintf(simple_serial_buf, 511, format, args);
  va_end(args);

  simple_serial_puts(simple_serial_buf);
}

void __fastcall__ simple_serial_write(char *ptr, size_t nmemb) {
  while (nmemb > 0) {
    simple_serial_putc(*ptr);
    ++ptr;
    --nmemb;
  }
}

#ifdef __CC65__
#pragma code-name (pop)
#pragma static-locals(pop)
#endif
