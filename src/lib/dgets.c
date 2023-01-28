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

char * __fastcall__ dget_text(char *buf, size_t size, cmd_handler_func cmd_cb) {
#ifdef __CC65__
  char c;
  size_t i = 0, max_i = 0, k;
  int cur_x, cur_y;
  char has_nl = 0;
  int prev_cursor = 0;
  unsigned char start_x, start_y;
  unsigned char sx, wx, x;
  unsigned char sy, ey, hy, y;

  get_hscrollwindow(&sx, &wx);
  get_scrollwindow(&sy, &ey);
  hy = ey - sy;

  memset(buf, '\0', size - 1);
  prev_cursor = cursor(1);

  start_x = wherex();
  start_y = wherey();

  while (i < size - 1) {
    cur_x = wherex();
    cur_y = wherey();

    c = cgetc();

    if ((c & 0x80) != 0) {
      if (cmd_cb((c & ~0x80))) {
        goto out;
      }
    } else if (c == CH_ESC) {
      continue;
    } else if (c == CH_CURS_LEFT) {
      if (i > 0) {
        i--;
        cur_x--;
        has_nl = (buf[i] == '\n');
      }
      if (cur_x < 0) {
up_a_line:
        if (i > 0) {
          cur_y--;
          cur_x = wx - 1;
          while (has_nl) {
            gotoxy(cur_x, cur_y);
            if (cpeekc() != ' ') {
              has_nl = 0;
              i--; /* one more char back */
            } else
              cur_x--;
              if (cur_x < 0) {
                goto up_a_line;
              }
          }
        }
      }
      gotoxy(cur_x, cur_y);
    } else if (c == CH_CURS_RIGHT) {
      if (i < max_i) {
        i++;
        cur_x++;
        has_nl = (buf[i] == '\n');
      }
      if (has_nl || cur_x > wx - 1) {
        cur_x = 0;
        cur_y++;
        if (has_nl) {
          has_nl = 0;
          i++; /* one more char forward */
        }
      }
      gotoxy(cur_x, cur_y);
      if (cur_x > wx - 1) {
        cur_x = 0;
        cur_y++;
      }
      gotoxy(cur_x, cur_y);
    } else {
      if (i < max_i) {
        if (c == CH_ENTER) {
          /* Clear to end of line */
          clrzone(cur_x, cur_y, wx - 1, cur_y);
          if (cur_y + 1 < hy- 1) {
            /* Clear next line */
            clrzone(0, cur_y + 1, wx - 1, cur_y + 1);
          }
          gotoxy(cur_x, cur_y);
          dputc('\r');
          dputc('\n');
        } else {
          /* advance cursor */
          dputc(c);
        }
        /* insert */
        if (max_i < size - 1)
          max_i++;
        for (k = max_i - 2; k >= i; k--) {
          buf[k + 1] = buf[k];
        }
        for (k = i + 1; k < max_i; k++) {
          x = wherex();
          y = wherey();
          if (buf[k] == '\n') {
            clrzone(x, y, wx - 1, y);
            gotoxy(x, y);
          }
          if (x == wx) {
            if (y + 1 < hy- 1) {
              clrzone(0, y + 1, wx - 1, y + 1);
              gotoxy(x, y);
            }
          }
          if (buf[k] == '\n') {
            dputc('\r');
          }
          dputc(buf[k]);
        }
        gotoxy(cur_x, cur_y);
        /* put back inserted char for cursor
         * advance again */
      }
      if (c == CH_ENTER) {
        dputc('\r');
        dputc('\n');
        buf[i] = '\n';
        i++;
        cur_x = 0;
      } else {
        dputc(c);
        buf[i] = c;
        i++;
        cur_x++;
      }
    }
    if (i > max_i) {
      max_i = i;
    }    
  }
out:
  cursor(prev_cursor);
  buf[i] = '\0';

  return buf;
#else
  return fgets(buf, size, stdin);
#endif
}
