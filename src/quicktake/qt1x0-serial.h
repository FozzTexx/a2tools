#ifndef __qt_1x0_serial_h
#define __qt_1x0_serial_h

uint8 qt_1x0_wakeup(uint16 speed);

uint8 qt1x0_send_ping(void);
uint8 qt1x0_set_speed(uint16 speed);

void qt1x0_set_camera_name(const char *name);
void qt1x0_set_camera_time(uint8 day, uint8 month, uint8 year, uint8 hour, uint8 minute, uint8 second);

uint8 qt1x0_take_picture(void);
uint8 qt1x0_get_picture(uint8 n_pic, const char *filename, uint8 full);
uint8 qt1x0_delete_pictures(void);
uint8 qt1x0_get_information(uint8 *num_pics, uint8 *left_pics, uint8 *quality_mode, uint8 *flash_mode, uint8 *battery_level, char **name, struct tm *time);

#endif
