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

#include <stdio.h>
#include <stdlib.h>
#include "dgets.h"
#include "extended_conio.h"
#include "dputc.h"
#include "clrzone.h"
#include "scrollwindow.h"
#include "scroll.h"
#include "surl.h"

#ifdef __CC65__
#pragma optimize(push, on)
#endif

static char echo_on = 1;
void __fastcall__ echo(int on) {
  echo_on = on;
}

static char start_x, start_y;
static unsigned char win_width, win_height;
static size_t cur_insert, max_insert;
static char *text_buf;

static int __fastcall__ get_prev_line_len() {
  int back;
  int prev_line_len;

  back = cur_insert - 1;

  while (back >= 0 && text_buf[back] != '\n') {
    --back;
  }

  ++back;
  if (back == 0) {
    back -= start_x;
  }
  prev_line_len = (cur_insert - back) % win_width;
  return prev_line_len;
}

#ifndef __CC65__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#endif

static void __fastcall__ rewrite_start_of_buffer() {
  int prev_line_len, k;

  prev_line_len = get_prev_line_len() - start_x;
  /* print it */
  gotoxy(start_x, start_y);
  for (k = cur_insert - prev_line_len; k <= cur_insert; k++) {
    cputc(text_buf[k]);
  }
}

static char __fastcall__ rewrite_end_of_buffer(char full) {
  size_t k;
  unsigned char x, y;
  char overflowed;
  char first_crlf;

  overflowed = 0;
  first_crlf = !full;

  x = wherex();
  y = wherey();

  if (cur_insert == max_insert) {
    /* Just clear EOL */
    clrzone(x, y, win_width - 1, y);
    return 0;
  }

  for (k = cur_insert; k < max_insert; k++) {
    char c = text_buf[k];
    if (c == '\n' || k == max_insert - 1) {
      clrzone(x, y, win_width - 1, y);
      gotoxy(x, y);
    }
    if (x == win_width || k == max_insert - 1) {
      if (y + 1 < win_height) {
        clrzone(0, y + 1, win_width - 1, y + 1);
        gotoxy(x, y);
      }
    }
    if (c == '\n') {
      if (x != 0 && x != win_width - 1 && first_crlf) {
        /* we can stop there, we won't shift lines down or up */
        break;
      }
      first_crlf = 0;
      cputc('\r');
    }
    cputc(c);
    x = wherex();
    if (y == win_height - 1 && wherey() == 0) {
      /* overflowed bottom */
      overflowed = 1;
      break;
    }
    y = wherey();
  }
  return overflowed;
}

#ifndef __CC65__
#pragma GCC diagnostic pop
#endif

char * __fastcall__ dget_text(char *buf, size_t size, cmd_handler_func cmd_cb, char enter_accepted) {
  char c;
  size_t k;
  int cur_x, cur_y;
#ifdef __CC65__
  int prev_cursor = 0;
#endif
  unsigned char sx;
  unsigned char sy, ey, tmp;
  char overflowed = 0;

  cur_insert = 0;
  max_insert = 0;
  text_buf = buf;

  get_hscrollwindow(&sx, &win_width);
  get_scrollwindow(&sy, &ey);
  start_x = wherex();
  start_y = wherey();

  win_height = ey - sy;

  if (text_buf[0] != '\0') {
    max_insert = strlen(text_buf);
    for (cur_insert = 0; cur_insert < max_insert; cur_insert++) {
      char c = text_buf[cur_insert];
      if (c != '\n') {
        dputc(c);
      } else {
        dputc('\r');
        dputc('\n');
      }
    }
  }
#ifdef __CC65__
  prev_cursor = cursor(1);
#endif
  while (1) {
    cur_x = wherex();
    cur_y = wherey();

    c = cgetc();

    if (cmd_cb && (c & 0x80) != 0) {
      if (cmd_cb((c & ~0x80))) {
        goto out;
      }
      gotoxy(cur_x, cur_y);
    } else if (c == CH_ESC) {
      if (cmd_cb && enter_accepted)
        continue;
      else {
        max_insert = 0;
        goto out;
      }
    } else if (c == CH_ENTER && (!cmd_cb || !enter_accepted)) {
      goto out;
    } else if (c == CH_CURS_LEFT || c == CH_DEL) {
      if (cur_insert > 0) {
        /* Go back one step in the buffer */
        cur_insert--;
        cur_x--;
        /* did we hit start of (soft) line ? */
        if (cur_x < 0) {
          /* recompute x */
          cur_x = get_prev_line_len();
          /* do we have to scroll (we were at line 0) ? */
          if (cur_y == 0) {
            scrolldown_one();
            rewrite_start_of_buffer();
          } else {
            /* go up */
            cur_y--;
          }
        }
        if (c == CH_DEL) {
          char deleted = text_buf[cur_insert];
          /* shift chars down */
          for (k = cur_insert; k < max_insert; k++) {
            text_buf[k] = text_buf[k + 1];
          }
          /* dec length */
          max_insert--;
          /* update display */
          gotoxy(cur_x, cur_y);
          rewrite_end_of_buffer(deleted == '\n');
        }
      } else {
        dputc(0x07);
      }
      gotoxy(cur_x, cur_y);
    } else if (c == CH_CURS_RIGHT) {
      /* are we at buffer end? */
      if (cur_insert < max_insert) {
        /* Are we at end of hard line ? */
        if (text_buf[cur_insert] != '\n') {
          /* We're not at end of line, go right */
          cur_x++;
        } else {
          /* We are, go down and left */
          cur_y++;
          cur_x = 0;
        }

        /* Are we at end of soft line now? */
        if (cur_x > win_width - 1) {
          /* We are, go down and left */
          cur_y++;
          cur_x = 0;
        }

        cur_insert++;

        /* Handle scroll up if needed */
        if (cur_y > win_height - 1) {
          cur_y--;
          scrollup_one();
          gotoxy(cur_x, cur_y);
          rewrite_end_of_buffer(0);
        }
      } else {
        dputc(0x07);
      }
      gotoxy(cur_x, cur_y);
    } else if (c == CH_CURS_UP) {
      if (!cmd_cb) {
        /* No up/down in standard line edit */
        dputc(0x07);
      } else if (cur_insert == cur_x) {
        /* we are at the first line, go at the beginning */
        cur_x = 0;
        cur_insert = 0;
      } else {
        /* Go back in the buffer to the character just 
         * before the current offset to left border */
        cur_insert -= cur_x + 1;
        /* and go up to previous line */
        /* Decompose because rewrite_start_of_buffer
         * expects us to be on a \n */
        if (cur_y == 0) {
          scrolldown_one();
          rewrite_start_of_buffer();
        } else {
          cur_y--;
        }

        /* are we at a  line hard end? */
        if (text_buf[cur_insert] == '\n') {
          /* we are, so don't go as far right as we were */
          tmp = get_prev_line_len();
          if (tmp < cur_x) {
            cur_x = tmp;
          } else {
            cur_insert -= tmp - cur_x;
          }
        } else {
          /* just going up in long line */
          cur_insert -= win_width - cur_x - 1;
        }
      }
      gotoxy(cur_x, cur_y);
    } else if (c == CH_CURS_DOWN) {
      if (!cmd_cb || cur_insert == max_insert) {
        /* No down in standard editor mode */
        dputc(0x07);
      } else {
        /* Save cur_x */
        tmp = cur_x;
        /* wrap to EOL, either hard or soft */
        while (cur_x < win_width - 1 && text_buf[cur_insert] != '\n') {
          cur_insert++;
          cur_x++;
          if (cur_insert == max_insert) {
            /* Can't go down, abort */
            goto stop_down;
          }
        }
        cur_insert++;
        cur_x = 0;

        /* Scroll if we need */
        if (cur_y == win_height - 1) {
          scrollup_one();
          gotoxy(cur_x, cur_y);
          rewrite_end_of_buffer(0);
        } else {
          cur_y++;
        }

        /* Advance to previous cur_x at most */
        while (cur_x < tmp) {
          if (cur_insert == max_insert || text_buf[cur_insert] == '\n') {
            break;
          }
          cur_insert++;
          cur_x++;
        }
      }
stop_down:
      gotoxy(cur_x, cur_y);
    } else {
      if (cur_insert == size - 1) {
        /* Full buffer */
        dputc(0x07);
        continue;
      }
      if (cur_insert < max_insert) {
        /* Insertion in the middle of the buffer.
         * Use cputc to avoid autoscroll there */
        if (c == CH_ENTER) {
          /* Clear to end of line */
          clrzone(cur_x, cur_y, win_width - 1, cur_y);
          /* Are we on the last line? */
          if (cur_y == win_height - 1) {
            /* we're on last line, scrollup */
            cur_y--;
            scrollup_one();
          }
          gotoxy(cur_x, cur_y);
          cputc('\r');
          cputc('\n');
        } else {
          /* advance cursor */
#ifdef __CC65__
          dputc(echo_on ? c : '*');
#endif
        }
        /* insert char */
        if (max_insert < size - 1)
          max_insert++;
        /* shift end of buffer */
        for (k = max_insert - 2; k >= cur_insert; k--) {
          text_buf[k + 1] = text_buf[k];
          if (k == 0) {
            break; /* size_t is unsigned, the for stop condition won't work */
          }
        }

        /* rewrite buffer after inserted char */
        cur_insert++;
        overflowed = rewrite_end_of_buffer(c == CH_ENTER);
        cur_insert--;

        if (cur_y == win_height - 1 && overflowed) {
          cur_y--;
          scrollup_one();
          /* rewrite again for last line */
          gotoxy(cur_x, cur_y);
          rewrite_end_of_buffer(0);
        }
        gotoxy(cur_x, cur_y);
        /* put back inserted char for cursor
         * advance again */
      }
      if (c == CH_ENTER) {
#ifdef __CC65__
        dputc('\r');
        dputc('\n');
#endif
        text_buf[cur_insert] = '\n';
        cur_insert++;
      } else {
#ifdef __CC65__
        dputc(echo_on ? c : '*');
#endif
        text_buf[cur_insert] = c;
        cur_insert++;
      }
    }
    if (cur_insert > max_insert) {
      max_insert = cur_insert;
    }    
  }
out:
  cursor(prev_cursor);
  text_buf[max_insert] = '\0';

  if (!cmd_cb) {
    dputc('\r');
    dputc('\n');
  }
  return text_buf;
}

#ifdef __CC65__
#pragma optimize(pop)
#endif
