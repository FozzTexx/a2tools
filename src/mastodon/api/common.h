#ifndef __common_h
#define __common_h

#include "account.h"

#define ENDPOINT_BUF_SIZE 128
extern char endpoint_buf[ENDPOINT_BUF_SIZE];

/* FIXME make that configurable */
#define US_CHARSET "US-ASCII"
#define FR_CHARSET "ISO646-FR1"

#define SELECTOR_SIZE 255
extern char selector[SELECTOR_SIZE];
#define BUF_SIZE 255
extern char gen_buf[BUF_SIZE];

extern char *instance_url;
extern char *oauth_token;
extern char *translit_charset;
extern char arobase;

#define ACCOUNTS_ENDPOINT "/api/v1/accounts"
#define TIMELINE_ENDPOINT "/api/v1/timelines"
#define STATUS_ENDPOINT   "/api/v1/statuses"

#define COMPOSE_PUBLIC 0
#define COMPOSE_UNLISTED 1
#define COMPOSE_PRIVATE 2
#define COMPOSE_MENTION 3

#define HOME_TIMELINE "home"

surl_response *get_surl_for_endpoint(char *method, char *endpoint);
account *api_get_profile(char *id);

#endif
