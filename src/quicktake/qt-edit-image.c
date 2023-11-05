#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "dgets.h"
#include "dputc.h"
#include "dputs.h"
#include "extended_conio.h"
#include "file_select.h"
#include "hgr.h"
#include "path_helper.h"
#include "progress_bar.h"
#include "scrollwindow.h"

#include "qt-conv.h"

extern uint8 scrw, scrh;

#ifdef __CC65__
  #pragma static-locals(push, on)
#endif

#define BUF_SIZE 64

#define DITHER_NONE   0
#define DITHER_BURKES 1
#define DITHER_BAYER  2
#define DEFAULT_DITHER_THRESHOLD 128

int16 angle = 0;
uint8 auto_level = 1;
uint8 dither_alg = DITHER_BURKES;
uint8 resize = 1;
uint8 mix_is_on = 0;
uint8 dither_threshold = DEFAULT_DITHER_THRESHOLD;

static void convert_temp_to_hgr(const char *ofname);

void get_program_disk(void) {
  while (reopen_start_device() != 0) {
    clrscr();
    gotoxy(13, 12);
    printf("Please reinsert the program disk, then press any key.");
    cgetc();
  }
}

void qt_convert_image(const char *filename) {
  static char imgname[BUF_SIZE];

  clrscr();
  dputs("Image conversion\r\n\r\n");
  if (!filename) {
    char *tmp;
    
    dputs("Image (QTK): ");
    tmp = file_select(wherex(), wherey(), scrw - wherex(), wherey() + 10, 0, "Select a QTK file");
    if (tmp == NULL)
      return;
    strcpy(imgname, tmp);
    free(tmp);
  } else {
    strcpy(imgname, filename);
  }

  if (imgname[0]) {
    FILE *fp = fopen(imgname, "rb");
    if (fp) {
      fread(magic, 1, 4, fp);
      magic[4] = '\0';
      fclose(fp);
    }

    get_program_disk();

    if (!strcmp(magic, QT100_MAGIC)) {
      exec("qt100conv", imgname);
    } else if (!strcmp(magic, QT150_MAGIC)) {
      exec("qt150conv", imgname);
    } else {
      cputs("Unknown file type.\r\n");
    }
  }
}

static unsigned baseaddr[HGR_HEIGHT];
static uint8 div7_table[HGR_WIDTH];
static uint8 mod7_table[HGR_WIDTH];
static uint16 histogram[256];
static uint8 opt_histogram[256];
#define NUM_PIXELS 49152U //256*192

static void histogram_equalize(void) {
  uint16 x;
  uint16 curr_hist = 0;

  if (auto_level) {
    ifp = fopen(HIST_NAME, "r");
    if (ifp != NULL) {
      fread(histogram, sizeof(uint16), 256, ifp);
      fclose(ifp);

      printf("Histogram equalization...\n");
      for (x = 0; x < 256; x++) {
        curr_hist += histogram[x];
        opt_histogram[x] = (uint8)((((uint32)curr_hist * 255)) / NUM_PIXELS);
      }
    } else {
      printf("Can't open "HIST_NAME"\n");
    }
  } else {
    for (x = 0; x < 256; x++) {
      opt_histogram[x] = x;
    }
  }
}

static void init_base_addrs (void)
{
  static uint8 base_init_done = 0;
  uint16 i, group_of_eight, line_of_eight, group_of_sixtyfour;
  if (base_init_done) {
    return;
  }

  for (i = 0; i < HGR_HEIGHT; ++i)
  {
    line_of_eight = i % 8;
    group_of_eight = (i % 64) / 8;
    group_of_sixtyfour = i / 64;

    baseaddr[i] = line_of_eight * 1024 + group_of_eight * 128 + group_of_sixtyfour * 40;
  }
  for (i = 0; i < HGR_WIDTH; i++) {
    div7_table[i] = i / 7;
    mod7_table[i] = i % 7;
  }
  histogram_equalize();
  base_init_done = 1;
}

#define X_OFFSET ((HGR_WIDTH - FILE_WIDTH) / 2)

#ifndef __CC65__
char HGR_PAGE[HGR_LEN];
#endif

static uint8 reedit_image(const char *ofname) {
  char c;

start_edit:
  do {
    clrscr();
    gotoxy(0, 20);
    printf("L: Rotate left - U: Rotate upside-down - R: Rotate right (Angle %d)",
           angle);
    if (angle == 90 || angle == 270) {
      if (resize)
        printf(" - C: Crop\n");
      else
        printf(" - C: Fit\n");
    } else {
      printf("\n");
    }
    printf("H: Auto-level %s - B: Brighten - D: Darken (Threshold %d)\n",
           auto_level ? "off":"on", dither_threshold);
    printf("Dither with K: Burkes / Y: Bayer / N: Don't dither (Current: %s)\n"
           "S: Save - Escape: Exit without saving - Any other key: Hide help",
           dither_alg == DITHER_BURKES ? "Burkes"
            : dither_alg == DITHER_BAYER ? "Bayer" : "None");

    c = tolower(cgetc());
    if (!mix_is_on) {
      hgr_mixon();
      mix_is_on = 1;
    } else {
      switch(c) {
        case CH_ESC:
          clrscr();
          gotoxy(0, 20);
          printf("Exit without saving? (y/N) ");
          c = tolower(cgetc());
          if (c == 'y')
            goto done;
          break;
        case 's':
          clrscr();
          gotoxy(0, 20);
          printf("Once saved, image edition will require a new full conversion.\n"
                 "Save? (Y/n)\n");
          c = tolower(cgetc());
          if (c != 'n')
            goto save;
          break;
        case 'r':
          angle += 90;
          return 1;
        case 'l':
          angle -= 90;
          return 1;
        case 'u':
          angle += 180;
          return 1;
        case 'h':
          auto_level = !auto_level;
          histogram_equalize();
          return 1;
        case 'c':
          resize = !resize;
          return 1;
        case 'k':
          dither_alg = DITHER_BURKES;
          dither_threshold = DEFAULT_DITHER_THRESHOLD;
          return 1;
        case 'y':
          dither_alg = DITHER_BAYER;
          dither_threshold = DEFAULT_DITHER_THRESHOLD;
          return 1;
        case 'n':
          dither_alg = DITHER_NONE;
          dither_threshold = DEFAULT_DITHER_THRESHOLD;
          return 1;
        case 'b':
          dither_threshold -= 32;
          return 1;
        case 'd':
          dither_threshold += 32;
          return 1;
        default:
          hgr_mixoff();
          mix_is_on = 0;
      }
    }
  } while (1);

save:
  ofp = fopen(ofname, "w");
  if (ofp == NULL) {
    printf("Please insert image floppy for %s, or Escape to return\n", ofname);
    if (cgetc() != CH_ESC)
      goto save;
    goto start_edit;
  }
  printf("\nSaving %s...\n", ofname);
  fseek(ofp, 0, SEEK_SET);
  fwrite((char *)HGR_PAGE, 1, HGR_LEN, ofp);
  fclose(ofp);
done:
  hgr_mixoff();
  init_text();
  return 0;
}

static uint8 buf[FILE_WIDTH];
static uint8 err[FILE_WIDTH * 2];

FILE *ifp, *ofp;

static void convert_temp_to_hgr(const char *ofname) {
  /* Rotation/cropping variables */
  uint16 x, off_x, start_x, end_x;
  uint16 y, off_y;
  uint16 dx, dy, scaled_dx, scaled_dy;
  int8 xdir, ydir;
  int16 cur_err;
  uint8 *ptr;
  uint8 pixel;
  uint8 invert_coords;

  /* Burkes variables */
  uint8 buf_plus_err;
  uint16 x_plus1;
  uint16 x_plus2;
  int16 x_minus1;
  int16 x_minus2;
  int16 err8, err4, err2;

  /* Bayer variables */
  uint8 map[8][8] = {
    { 1, 49, 13, 61, 4, 52, 16, 64 },
    { 33, 17, 45, 29, 36, 20, 48, 32 },
    { 9, 57, 5, 53, 12, 60, 8, 56 },
    { 41, 25, 37, 21, 44, 28, 40, 24 },
    { 3, 51, 15, 63, 2, 50, 14, 62 },
    { 25, 19, 47, 31, 34, 18, 46, 30 },
    { 11, 59, 7, 55, 10, 58, 6, 54 },
    { 43, 27, 39, 23, 42, 26, 38, 22 }
  };
  uint8 y_mod8;

  /* General variables */
  uint8 *cur_err_line = err;
  uint8 *next_err_line = err + FILE_WIDTH;
  uint16 h_plus1 = FILE_HEIGHT + 1;
  unsigned char dhbmono[] = {0x7e,0x7d,0x7b,0x77,0x6f,0x5f,0x3f};
  unsigned char dhwmono[] = {0x01,0x02,0x04,0x08,0x10,0x20,0x40};
  uint8 *cur_hgr_line;
  uint16 cur_hgr_row;
  uint8 cur_hgr_mod;

  init_base_addrs();

  clrscr();
  gotoxy(0, 20);
  printf("Converting %s (Esc to stop)...\n", ofname);

  ifp = fopen(TMP_NAME, "r");
  if (ifp == NULL) {
    printf("Can't open "TMP_NAME"\n");
    return;
  }

  printf("Dithering...\n");
  memset(err, 0, sizeof err);
  memset((char *)HGR_PAGE, 0, HGR_LEN);

  progress_bar(wherex(), wherey(), scrw, 0, FILE_HEIGHT);

  start_x = 0;
  end_x = FILE_WIDTH;
  switch (angle) {
    case 0:
      off_x = X_OFFSET;
      off_y = 0;
      xdir = +1;
      ydir = +1;
      invert_coords = 0;
      break;
    case 90:
      if (resize) {
        off_x = 0;
        off_y = 212 * 4 / 3;
      } else {
        off_x = 0;
        off_y = HGR_WIDTH - 45;
        start_x = 32;
        end_x = FILE_WIDTH - 33;
      }
      xdir = +1;
      ydir = -1;
      invert_coords = 1;
      break;
    case 270:
      if (resize) {
        off_x = FILE_WIDTH - 1;
        off_y = 68 * 4 / 3;
      } else {
        off_x = HGR_HEIGHT - 1;
        off_y = 44;
        start_x = 32;
        end_x = FILE_WIDTH - 33;
      }
      xdir = -1;
      ydir = +1;
      invert_coords = 1;
      break;
    case 180:
      off_x = HGR_WIDTH - X_OFFSET;
      off_y = FILE_HEIGHT - 1;
      xdir = -1;
      ydir = -1;
      invert_coords = 0;
      break;
  }

  for(y = 0, dy = off_y; y != FILE_HEIGHT; y++, dy+= ydir) {
    fread(buf, 1, FILE_WIDTH, ifp);

    if (kbhit()) {
      if (cgetc() == CH_ESC)
        goto stop;
    }

    if (dither_alg == DITHER_BURKES) {
      /* Rollover next error line */
      uint8 *tmp = cur_err_line;
      cur_err_line = next_err_line;
      next_err_line = tmp;
      memset(next_err_line, 0, FILE_WIDTH);
    } else {
      /* Precompute y modulo for the line */
      y_mod8 = y % 8;
    }
    if (invert_coords) {
      if (resize) {
        scaled_dy = dy * 3 / 4;
        cur_hgr_row = div7_table[scaled_dy];
        cur_hgr_mod = mod7_table[scaled_dy];
      } else {
        cur_hgr_row = div7_table[dy];
        cur_hgr_mod = mod7_table[dy];
      }
    } else {
      cur_hgr_line = (unsigned char *)HGR_PAGE + baseaddr[dy];
    }

    for(x = start_x, dx = off_x; x != end_x; x++, dx += xdir) {
      /* Get destination pixel */
      if (invert_coords) {
        if (resize) {
          scaled_dx = dx * 3 / 4;
          ptr = (unsigned char *)HGR_PAGE + baseaddr[scaled_dx] + cur_hgr_row;
          pixel = cur_hgr_mod;
        } else {
          ptr = (unsigned char *)HGR_PAGE + baseaddr[dx] + cur_hgr_row;
          pixel = cur_hgr_mod;
        }
      } else {
        ptr = cur_hgr_line + div7_table[dx];
        pixel = mod7_table[dx];
      }

      /* Dither */
      if (dither_alg == DITHER_BURKES) {
        buf_plus_err = opt_histogram[buf[x]] + cur_err_line[x];
        x_plus1 = x + 1;
        x_plus2 = x_plus1 + 1;
        x_minus1 = x - 1;
        x_minus2 = x_minus1 - 1;

        if (dither_threshold > buf_plus_err) {
          cur_err = buf_plus_err;
          ptr[0] &= dhbmono[pixel];
        } else {
          cur_err = buf_plus_err - 255;
          ptr[0] |= dhwmono[pixel];
        }
        err8 = cur_err >> 2; /* cur_err * 8 / 32 */
        err4 = err8 >> 1;    /* cur_err * 4 / 32 */
        err2 = err4 >> 1;    /* cur_err * 2 / 32 */

        if (x_plus1 < FILE_WIDTH) {
          cur_err_line[x_plus1]    += err8;
          next_err_line[x_plus1]   += err4;
          if (x_plus2 < FILE_WIDTH) {
            cur_err_line[x_plus2]  += err4;
            next_err_line[x_plus2] += err2;
          }
        }
        if (x_minus1 > 0) {
          next_err_line[x_minus1]  += err4;
          if (x_minus2 > 0) {
            next_err_line[x_minus2]+= err2;
          }
        }
        next_err_line[x]           += err8;
      } else if (dither_alg == DITHER_BAYER) {
        uint16 val = opt_histogram[buf[x]];

        val += val * map[y_mod8][x % 8] / 63;
        if (dither_threshold > val) {
          ptr[0] &= dhbmono[pixel];
        } else {
          ptr[0] |= dhwmono[pixel];
        }
      } else if (dither_alg == DITHER_NONE) {
        if (dither_threshold > opt_histogram[buf[x]]) {
          ptr[0] &= dhbmono[pixel];
        } else {
          ptr[0] |= dhwmono[pixel];
        }      
      }
    }
    progress_bar(-1, -1, scrw, y, FILE_HEIGHT);
  }
stop:
  fclose(ifp);
}

void qt_edit_image(const char *ofname) {
  do {
    if (angle >= 360)
      angle -= 360;
    if (angle < 0)
      angle += 360;
    convert_temp_to_hgr(ofname);
  } while (reedit_image(ofname));
}

void qt_view_image(const char *filename) {
  FILE *fp = NULL;
  static char imgname[BUF_SIZE];
  uint16 len;
  #define BLOCK_SIZE 512

  clrscr();

  dputs("Image view\r\n\r\n");
  if (!filename) {
    char *tmp;
    dputs("Image (HGR): ");
    tmp = file_select(wherex(), wherey(), scrw - wherex(), wherey() + 10, 0, "Select an HGR file");
    if (tmp == NULL)
      return;
    strcpy(imgname, tmp);
    free(tmp);
  } else {
    strcpy(imgname, filename);
  }

  fp = fopen(imgname, "rb");
  if (fp == NULL) {
    dputs("Can not open image.\r\n");
    cgetc();
    return;
  }

  memset((char *)HGR_PAGE, 0x00, HGR_LEN);
  init_text();
  gotoxy(0, 18);
  cputs("Loading image...");

  progress_bar(0, 19, scrw, 0, HGR_LEN);

  len = 0;
  while (len < HGR_LEN) {
#ifdef __CC65__
    fread((char *)(HGR_PAGE + len), 1, BLOCK_SIZE, fp);
#endif
    progress_bar(-1, -1, scrw, len, HGR_LEN);
    len += BLOCK_SIZE;
  }

  init_hgr();
  hgr_mixoff();
  mix_is_on = 0;

  fclose(fp);

  cgetc();
  init_text();

  get_program_disk();
  clrscr();
  return;
}

#ifdef __CC65__
  #pragma static-locals(pop)
#endif
