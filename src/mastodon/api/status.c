#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include "surl.h"
#include "simple_serial.h"
#include "strsplit.h"
#include "api.h"

#ifdef __CC65__
#pragma code-name (push, "LOWCODE")
#endif

#define TL_SPOILER_TEXT_BUF 54
#define TL_STATUS_SHORT_BUF 512
#define TL_STATUS_LARGE_BUF 4096

status *status_new(void) {
  status *s = malloc(sizeof(status));
  if (s == NULL) {
    return NULL;
  }
  memset(s, 0, sizeof(status));
  s->displayed_at = -1;
  return s;
}

#ifdef __CC65__
#pragma static-locals (push,off) /* need reentrancy */
#endif
static __fastcall__ char status_fill_from_json(status *s, char *id, char full, char is_reblog) {
  char **lines;
  char n_lines;
  int r;
  char *content;

  s->id = strdup(id);
  if (s->id == NULL) {
    nomem_msg(__FILE__, __LINE__);
    return -1;
  }

  s->account = account_new();

  if (s->account == NULL) {
    nomem_msg(__FILE__, __LINE__);
    return -1;
  }

  /* .reblog.id is the only one that can be null (and hence not there),
   * so put it at the end */
  if (is_reblog) {
    r = surl_get_json(gen_buf, BUF_SIZE, SURL_HTMLSTRIP_NONE, translit_charset,
                      ".reblog|(.created_at,.account.display_name,\"-\",.spoiler_text)");
  } else {
    r = surl_get_json(gen_buf, BUF_SIZE, SURL_HTMLSTRIP_NONE, translit_charset,
                      ".created_at,.account.display_name,.reblog.id//\"-\",.spoiler_text");
  }

  n_lines = strsplit_in_place(gen_buf, '\n', &lines);
  if (r >= 0 && n_lines >= 3) {
    if (!is_reblog && lines[2][0] != '-') {
      s->reblogged_by = strdup(lines[1]);
      s->reblog_id = s->id;
      s->id = NULL;
      r = status_fill_from_json(s, lines[2], full, 1);
      free(lines);
      return r;
    }

    s->created_at = date_format(lines[0], 1);
    s->account->display_name = strdup(lines[1]);
    if (n_lines > 3) {
      s->spoiler_text = malloc(TL_SPOILER_TEXT_BUF);
      if (!s->spoiler_text) {
        goto err_mem;
      }
      strncpy(s->spoiler_text, lines[3], TL_SPOILER_TEXT_BUF - 1);
      s->spoiler_text[TL_SPOILER_TEXT_BUF - 1] = '\0';
    }
  }
  free(lines);
  
  /* Get details of original toot */
  if (is_reblog) {
    r = surl_get_json(gen_buf, BUF_SIZE, SURL_HTMLSTRIP_NONE, NULL,
                      ".reblog|((.media_attachments|map(. | select(.type==\"image\"))|length),"
                      ".replies_count,.reblogs_count,.favourites_count,.reblogged,.favourited,"
                      ".bookmarked,.account.id,.account.acct,.account.username,.visibility)");
  } else {
    r = surl_get_json(gen_buf, BUF_SIZE, SURL_HTMLSTRIP_NONE, NULL,
                      "(.media_attachments|map(. | select(.type==\"image\"))|length),"
                      ".replies_count,.reblogs_count,.favourites_count,.reblogged,.favourited,"
                      ".bookmarked,.account.id,.account.acct,.account.username,.visibility");
  }

  n_lines = strsplit_in_place(gen_buf, '\n', &lines);
  if (r >= 0 && n_lines == 11) {
    r = atoi(lines[0]);
    s->n_images = r > 255 ? 255 : r;
    r = atoi(lines[1]);
    s->n_replies = r > 255 ? 255 : r;
    r = atoi(lines[2]);
    s->n_reblogs = r > 255 ? 255 : r;
    r = atoi(lines[3]);
    s->n_favourites = r > 255 ? 255 : r;
    if (lines[4][0] == 't') /* true */
      s->flags |= REBLOGGED;
    if (lines[5][0] == 't') /* true */
      s->flags |= FAVOURITED;
    if (lines[6][0] == 't') /* true */
      s->flags |= BOOKMARKED;
    s->account->id = strdup(lines[7]);
    s->account->acct = strdup(lines[8]);
    s->account->username = strdup(lines[9]);
    if (lines[10][1] == 'u') /* pUblic */
      s->visibility = COMPOSE_PUBLIC;
    else if (lines[10][1] == 'n') /* uNlisted */
      s->visibility = COMPOSE_UNLISTED;
    else if (lines[10][1] == 'r') /* pRivate */
      s->visibility = COMPOSE_PRIVATE;
    else
      s->visibility = COMPOSE_MENTION;
  }
  free(lines);

  content = malloc(full ? TL_STATUS_LARGE_BUF : TL_STATUS_SHORT_BUF);
  if (!content) {
err_mem:
    status_free(s);
    nomem_msg(__FILE__, __LINE__);
    return -1;
  }

  if (is_reblog) {
    r = surl_get_json(content, full ? TL_STATUS_LARGE_BUF : TL_STATUS_SHORT_BUF, SURL_HTMLSTRIP_FULL, translit_charset, ".reblog.content");
  } else {
    r = surl_get_json(content, full ? TL_STATUS_LARGE_BUF : TL_STATUS_SHORT_BUF, SURL_HTMLSTRIP_FULL, translit_charset, ".content");
  }
  if (!full && r == TL_STATUS_SHORT_BUF - 1) {
    strcpy(content + TL_STATUS_SHORT_BUF - 4, "...");
    s->content = content;
  } else if (r >= 0) {
    s->content = realloc(content, r + 1);
  }

  return 0;
}

#ifdef __CC65__
#pragma static-locals (pop)
#endif

void status_free(status *s) {
  if (s == NULL)
    return;
  free(s->id);
  free(s->reblog_id);
  free(s->created_at);
  free(s->spoiler_text);
  free(s->content);
  free(s->reblogged_by);
  account_free(s->account);
  free(s);
}

status *api_get_status(char *status_id, char full) {
  snprintf(endpoint_buf, ENDPOINT_BUF_SIZE, "%s/%s", STATUS_ENDPOINT, status_id);
  get_surl_for_endpoint(SURL_METHOD_GET, endpoint_buf);
  
  if (surl_response_ok()) {
    status *s = status_new();
    if (s != NULL && status_fill_from_json(s, status_id, full, 0) == 0)
      return s;
    else
      status_free(s);
  }

  return NULL;
}

#ifdef __CC65__
#pragma code-name (pop)
#endif
