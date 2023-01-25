#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "surl.h"
#include "simple_serial.h"
#include "extended_conio.h"
#include "extended_string.h"
#include "api.h"

static char endpoint_buf[BUF_SIZE];

extern char *instance_url;
extern char *oauth_token;

/* shared */
char gen_buf[BUF_SIZE];
char selector[SELECTOR_SIZE];

static surl_response *get_surl_for_endpoint(char *method, char *endpoint) {
  static char **token_hdr = NULL;
  surl_response *resp;

  if (token_hdr == NULL) {
    token_hdr = malloc(sizeof(char *));
    token_hdr[0] = malloc(BUF_SIZE);
    snprintf(token_hdr[0], BUF_SIZE, "Authorization: Bearer %s", oauth_token);
  }

  snprintf(gen_buf, BUF_SIZE, "%s%s", instance_url, endpoint);
  resp = surl_start_request(method, gen_buf, token_hdr, 1);
  
  return resp;
}

account *api_get_profile(char *id) {
  surl_response *resp;
  account *a = account_new();
  int r = -1;
  char n_lines, **lines;

  if (a == NULL) {
    return NULL;
  }

  snprintf(endpoint_buf, BUF_SIZE, "%s/%s", ACCOUNTS_ENDPOINT,
              id == NULL ? "verify_credentials" : id);
  resp = get_surl_for_endpoint("GET", endpoint_buf);

  if (resp == NULL || resp->code < 200 || resp->code >= 300)
    goto err_out;

  if (surl_get_json(resp, gen_buf, BUF_SIZE, 0, 1, ".id,.display_name,.username") == 0) {
    n_lines = strsplit_in_place(gen_buf,'\n',&lines);
    if (n_lines < 3) {
      account_free(a);
      free(lines);
      return NULL;
    }
    a->id = strdup(lines[0]);
    a->display_name = strdup(lines[1]);
    a->username = strdup(lines[2]);
    free(lines);
  }

err_out:
  surl_response_free(resp);
  return a;
}

int api_get_account_posts(account *a, char to_load, char *first_to_load, char **post_ids) {
  char buf[BUF_SIZE]; /* can't use endpoint_buf */

  snprintf(buf, BUF_SIZE, "%s%s/statuses", ACCOUNTS_ENDPOINT, a->id);

  return api_get_posts(buf, to_load, first_to_load, post_ids);
}

int api_get_posts(char *endpoint, char to_load, char *first_to_load, char **post_ids) {
  surl_response *resp;
  int n_status;
  char *raw;

  n_status = 0;
  snprintf(endpoint_buf, BUF_SIZE, "%s?limit=%d%s%s", endpoint, to_load,
            first_to_load ? "&max_id=" : "",
            first_to_load ? first_to_load : ""
          );
  resp = get_surl_for_endpoint("GET", endpoint_buf);
  
  if (resp == NULL || resp->code < 200 || resp->code >= 300)
    goto err_out;

  raw = malloc(512);
  if (surl_get_json(resp, raw, 512, 0, 0, ".[].id") == 0) {
    char **tmp;
    int i;
    n_status = strsplit(raw, '\n', &tmp);
    for (i = 0; i < n_status; i++) {
      post_ids[i] = tmp[i];
    }
    free(tmp);
  }
  free(raw);

err_out:
  surl_response_free(resp);
  return n_status;
}

/* FIXME get more using first_to_load and number of asc/desc... */
int api_get_status_and_replies(char to_load, char *root_id, char *root_leaf_id, char *first_to_load, char **post_ids) {
  surl_response *resp;
  int n_status;
  char n_before, n_after;
  char *raw;

  n_status = 0;
  snprintf(endpoint_buf, BUF_SIZE, "%s/%s/context", STATUS_ENDPOINT, root_leaf_id);
  resp = get_surl_for_endpoint("GET", endpoint_buf);
  
  if (resp == NULL || resp->code < 200 || resp->code >= 300)
    goto err_out;

  raw = malloc(512);
  n_before = to_load/3;
  n_after  = (2 * to_load) / 3;
  if (n_before + n_after == to_load) {
    n_before--;
  }
  //.descendants|.[[.[].id]|index("109748355755514564")+1:[.[].id]|index("109748355755514564")+1+to_load]|.[].id
  snprintf(selector, SELECTOR_SIZE, "(.ancestors|.[-%d:]|.[].id),\"-\",(.descendants|.[0:%d]|.[].id)", n_before, n_after);
  if (surl_get_json(resp, raw, 512, 0, 0, selector) == 0) {
    char **tmp;
    int i;
    n_status = strsplit(raw, '\n', &tmp);
    for (i = 0; i < n_status; i++) {
      if (tmp[i][0] != '-') {
        post_ids[i] = tmp[i];
      } else {
        post_ids[i] = strdup(root_id);
        free(tmp[i]);
      }
    }
    free(tmp);
  }
  free(raw);

err_out:
  surl_response_free(resp);
  return n_status;
}

status *api_get_status(char *status_id, char full) {
  surl_response *resp;
  status *s;

  s = NULL;

  snprintf(endpoint_buf, BUF_SIZE, "%s/%s", STATUS_ENDPOINT, status_id);
  resp = get_surl_for_endpoint("GET", endpoint_buf);
  
  if (resp == NULL || resp->code < 200 || resp->code >= 300)
    goto err_out;

  s = status_new_from_json(resp, status_id, full, 0);

err_out:
  surl_response_free(resp);
  return s;
}

/* Caution: does not go into s->reblog */
static char api_status_interact(status *s, char *action) {
  surl_response *resp;
  char r = -1;

  snprintf(endpoint_buf, BUF_SIZE, "%s/%s/%s", STATUS_ENDPOINT, s->id, action);
  resp = get_surl_for_endpoint("POST", endpoint_buf);

  surl_send_data_params(resp, 0, 1);
  surl_send_data(resp, "", 0);

  surl_read_response_header(resp);


  if (resp == NULL || resp->code < 200 || resp->code >= 300)
    goto err_out;

  r = 0;

err_out:
  surl_response_free(resp);
  return r;
}

void api_favourite_status(status *s) {
  char r;

  if (s->reblog) {
    s = s->reblog;
  }

  if ((s->favorited_or_reblogged & FAVOURITED) == 0) {
    r = api_status_interact(s, "favourite");
    if (r == 0) {
      s->favorited_or_reblogged |= FAVOURITED;
      s->n_favourites++;
    }
  } else {
    r = api_status_interact(s, "unfavourite");
    if (r == 0) {
      s->favorited_or_reblogged &= ~FAVOURITED;
      s->n_favourites--;
    }
  }
}

void api_reblog_status(status *s) {
  char r;

  if (s->reblog) {
    s = s->reblog;
  }

  if ((s->favorited_or_reblogged & REBLOGGED) == 0) {
    r = api_status_interact(s, "reblog");
    if (r == 0) {
      s->favorited_or_reblogged |= REBLOGGED;
      s->n_reblogs++;
    }
  } else {
    r = api_status_interact(s, "unreblog");
    if (r == 0) {
      s->favorited_or_reblogged &= ~REBLOGGED;
      s->n_reblogs--;
    }
  }
}

char api_delete_status(status *s) {
  surl_response *resp;
  char r = -1;

  if (s->reblog) {
    s = s->reblog;
  }

  snprintf(endpoint_buf, BUF_SIZE, "%s/%s", STATUS_ENDPOINT, s->id);
  resp = get_surl_for_endpoint("DELETE", endpoint_buf);

  if (resp == NULL || resp->code < 200 || resp->code >= 300)
    goto err_out;

  r = 0;

err_out:
  surl_response_free(resp);
  return r;
}

char api_relationship_get(account *a, char f) {
  surl_response *resp;
  char r = 0;
  char n_lines, **lines;
  resp = NULL;

  if ((a->relationship & RSHIP_SET) == 0) {
    snprintf(endpoint_buf, BUF_SIZE, "%s/relationships?id[]=%s", ACCOUNTS_ENDPOINT, a->id);
    resp = get_surl_for_endpoint("GET", endpoint_buf);

    if (resp == NULL || resp->code < 200 || resp->code >= 300)
      goto err_out;

    if (surl_get_json(resp, gen_buf, BUF_SIZE, 0, 1, ".[]|.following,.followed_by,.blocking,.blocked_by,.muting,.requested") == 0) {
      n_lines = strsplit_in_place(gen_buf,'\n',&lines);
      if (n_lines < 6) {
        free(lines);
        goto err_out;
      }
      a->relationship |= RSHIP_SET;
      if (lines[0][0] == 't') {
        a->relationship |= RSHIP_FOLLOWING;
      }
      if (lines[1][0] == 't') {
        a->relationship |= RSHIP_FOLLOWED_BY;
      }
      if (lines[2][0] == 't') {
        a->relationship |= RSHIP_BLOCKING;
      }
      if (lines[3][0] == 't') {
        a->relationship |= RSHIP_BLOCKED_BY;
      }
      if (lines[4][0] == 't') {
        a->relationship |= RSHIP_MUTING;
      }
      if (lines[5][0] == 't') {
        a->relationship |= RSHIP_FOLLOW_REQ;
      }
      free(lines);
    }
  }
  r = (a->relationship & f) != 0;

err_out:
  surl_response_free(resp);
  return r;
}

account *api_get_full_account(account *orig) {
  surl_response *resp;
  account *a;

  a = NULL;

  snprintf(endpoint_buf, BUF_SIZE, "%s/%s", ACCOUNTS_ENDPOINT, orig->id);
  resp = get_surl_for_endpoint("GET", endpoint_buf);
  
  if (resp == NULL || resp->code < 200 || resp->code >= 300)
    goto err_out;

  a = account_new_from_json(resp);

err_out:
  surl_response_free(resp);
  return a;
}
