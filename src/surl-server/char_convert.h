#ifndef __char_convert_h
#define __char_convert_h

char *do_apple_convert(char *in, int way, size_t *new_len);

enum {
  INCOMING,
  OUTGOING
};

#endif
