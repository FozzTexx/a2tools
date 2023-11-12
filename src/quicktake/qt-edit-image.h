#ifndef __qt_edit_image_h
#define __qt_edit_image_h

#include "platform.h"

void qt_convert_image(const char *filename);
uint8 qt_edit_image(const char *ofname);
void qt_view_image(const char *filename);
void get_program_disk(void);

void convert_temp_to_hgr(const char *ifname, const char *ofname, uint16 p_width, uint16 p_height);

#endif
