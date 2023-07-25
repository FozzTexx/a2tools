#ifndef __compose_h
#define __compose_h

#include "common.h"

signed char api_send_toot(char *buffer, char *cw, char sensitive_medias,
                          char *in_reply_to_id, char **media_ids, char n_medias,
                          char compose_audience);

char *api_send_hgr_image(char *filename, char *description, char **err);
#endif
