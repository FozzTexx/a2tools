#ifndef __simple_serial_h
#define __simple_serial_h
#include <stdlib.h>
#include <unistd.h>
#ifdef __CC65__
#include <serial.h>
#else
#include <termios.h>
#endif

#ifndef __CC65__
#define __fastcall__
#endif

#define SIMPLE_SERIAL_BUF_SIZE 512

/* Setup */

void simple_serial_set_speed(int b);
void simple_serial_set_flow_control(unsigned char fc);

void simple_serial_set_parity(unsigned int p);
void simple_serial_dtr_onoff(unsigned char on);
void simple_serial_acia_onoff(unsigned char slot_num, unsigned char on);

#ifdef __CC65__
char __fastcall__ simple_serial_open(void);
char __fastcall__ simple_serial_close(void);
void __fastcall__ simple_serial_flush(void);
void __fastcall__ simple_serial_configure(void);

#define simple_serial_putc(c) ser_put(c)
#else
int simple_serial_open(void);
int simple_serial_close(void);
void simple_serial_flush(void);
#define simple_serial_configure()
unsigned char __fastcall__ simple_serial_putc(char c);
char *tty_speed_to_str(int speed);
#endif

/* Input */
char __fastcall__ simple_serial_getc(void);
int __fastcall__ simple_serial_getc_with_timeout(void);
int __fastcall__ simple_serial_getc_immediate(void);

char * __fastcall__ simple_serial_gets(char *out, size_t size);

void __fastcall__ simple_serial_read(char *ptr, size_t nmemb);

/* Output */
void __fastcall__ simple_serial_puts(const char *buf);
void __fastcall__ simple_serial_write(const char *ptr, size_t nmemb);

void simple_serial_printf(const char* format, ...);
#endif
