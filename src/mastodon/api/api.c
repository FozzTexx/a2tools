#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "surl.h"
#include "simple_serial.h"
#include "strsplit.h"
#include "api.h"
#include "common.h"

#ifdef __CC65__
#pragma code-name (push, "LOWCODE")
#endif

int api_get_account_posts(account *a, char to_load, char *load_before, char *load_after, char **post_ids) {
  snprintf(gen_buf, BUF_SIZE, "%s/%s/statuses", ACCOUNTS_ENDPOINT, a->id);

  return api_get_posts(gen_buf, to_load, load_before, load_after, NULL, ".[].id", post_ids);
}

int api_search(char to_load, char *search, char search_type, char *load_before, char *load_after, char **post_ids) {
  char *w;
  snprintf(gen_buf, 255, "&type=%s&q=",
           search_type == 'm' ? "statuses":"accounts");

  /* very basic urlencoder, encodes everything */
  w = gen_buf + 17; /* 17 = strlen(gen_buf) */;
  while (*search) {
    snprintf(w, 4, "%%%02x", *search);
    w+= 3;
    ++search;
  }

  if (search_type == 'm')
    return api_get_posts(SEARCH_ENDPOINT, to_load, load_before, load_after, gen_buf, ".statuses[].id", post_ids);
  else
    return api_get_posts(SEARCH_ENDPOINT, to_load, load_before, load_after, gen_buf, ".accounts[].id", post_ids);
}

int api_get_posts(char *endpoint, char to_load, char *load_before, char *load_after, char *filter, char *sel, char **post_ids) {
  surl_response *resp;
  int n_status;

  n_status = 0;
  snprintf(endpoint_buf, ENDPOINT_BUF_SIZE, "%s?limit=%d%s%s%s%s%s", endpoint, to_load,
            load_after ? "&max_id=" : "",
            load_after ? load_after : "",
            load_before ? "&min_id=" : "",
            load_before ? load_before : "",
            filter ? filter : ""
          );
  resp = get_surl_for_endpoint(SURL_METHOD_GET, endpoint_buf);
  
  if (!surl_response_ok(resp))
    goto err_out;

  if (surl_get_json(gen_buf, BUF_SIZE, SURL_HTMLSTRIP_NONE, NULL, sel) >= 0) {
    char **tmp;
    int i;
    n_status = strsplit(gen_buf, '\n', &tmp);
    for (i = 0; i < n_status; i++) {
      post_ids[i] = tmp[i];
    }
    free(tmp);
  }

err_out:
  surl_response_free(resp);
  return n_status;
}

int api_get_status_and_replies(char to_load, char *root_id, char *root_leaf_id, char *load_before, char *load_after, char **post_ids) {
  surl_response *resp;
  int n_status;
  char n_before, n_after;

  n_status = 0;
  snprintf(endpoint_buf, ENDPOINT_BUF_SIZE, "%s/%s/context", STATUS_ENDPOINT, root_leaf_id);
  resp = get_surl_for_endpoint(SURL_METHOD_GET, endpoint_buf);
  
  if (!surl_response_ok(resp))
    goto err_out;

  /* we will return a list of #to_load IDs. if no load_before/load_after
   * boundaries are specified, we'll return 1/3rd before the root_leaf_id
   * and 2/3rds after.
   * We insert root_id (not root_leaf_id!) in the list so that caller knows
   * where to init display at. Not root_leaf_id because we want to keep the
   * "xyz boosted" header.
   * If load_before or load_after is specified, we concat the ancestors
   * array, root_id as array, descendants array, and then we return the 
   * #to_load results (at max) before or after the boundary.
   */
  if (load_after == NULL && load_before == NULL) {
    n_before = to_load/3;
    n_after  = (2 * to_load) / 3;
    if (n_before + n_after == to_load) {
      /* remove one descendant to make room for the "-" root marker */
      n_before--;
    }
    /* select n_before ascendants and n_after ascendants */
    snprintf(selector, SELECTOR_SIZE, "(.ancestors|.[-%d:]|.[].id),\"%s\","
                                      "(.descendants|.[0:%d]|.[].id)",
                                      n_before, root_id, n_after);
  } else if (load_after != NULL){
    /* flatten ancestors[],root,descendants[] :
     * [((.ancestors|map(.id)),["root_leaf_id"],(.descendants|map(.id)))|.[]]
     * get strings: |.[]
     * with indexes first to end:
     *              |.[ first : ]
     * where start is: .|index("root_id")+1
     * and then get n_after of it:
     * | .[ : %d]
     * and flatten:
     * | .[]
     * so the full selector is :
     * [ ((.ancestors|map(.id)),
         ["root_leaf_id"],
         (.descendants|map(.id)))
         |.[]
       ] | .[
             .|index("boundary")+1 :
            ]
          | .[ : n_after ] | .[]
     */
    n_after = to_load;
    snprintf(selector, SELECTOR_SIZE, "[ ((.ancestors|map(.id)),"
                                        "[\"%s\"],"
                                        "(.descendants|map(.id)))"
                                        "|.[]"
                                      "] | .["
                                            ".|index(\"%s\")+1:"
                                           "]"
                                         "| .[ : %d] | .[]",
                                        root_id,
                                        load_after,
                                        n_after);
  } else if (load_before != NULL){
    /* flatten ancestors[],root,descendants[] :
     * [((.ancestors|map(.id)),["root_leaf_id"],(.descendants|map(.id)))|.[]]
     * get strings: |.[]
     * with indexes start to last :
     *              |.[ : last ]
     * where last is: .|index("root_id")
     * and then get n_before of it:
     * | .[ -%d : ]
     * and flatten:
     * | .[]
     * so the full selector is :
     * [ ((.ancestors|map(.id)),
         ["root_leaf_id"],
         (.descendants|map(.id)))
         |.[]
       ] | .[
             .|index("boundary") :
            ]
          | .[ -n_before : ] | .[]
     */
    n_before = to_load;
    snprintf(selector, SELECTOR_SIZE, "[ ((.ancestors|map(.id)),"
                                        "[\"%s\"],"
                                        "(.descendants|map(.id)))"
                                        "|.[]"
                                      "] | .["
                                            ": .|index(\"%s\")"
                                           "]"
                                         "| .[-%d : ] | .[]",
                                        root_id,
                                        load_before,
                                        n_before);
  }
  if (surl_get_json(gen_buf, BUF_SIZE, SURL_HTMLSTRIP_NONE, NULL, selector) >= 0) {
    char **tmp;
    int i;
    n_status = strsplit(gen_buf, '\n', &tmp);
    for (i = 0; i < n_status; i++) {
      post_ids[i] = tmp[i];
    }
    free(tmp);
  }

err_out:
  surl_response_free(resp);
  return n_status;
}

char api_interact(char *id, char type, char *action) {
  surl_response *resp;
  char r = -1;

  snprintf(endpoint_buf, ENDPOINT_BUF_SIZE, "%s/%s/%s",
           type == 's' ? STATUS_ENDPOINT : ACCOUNTS_ENDPOINT, id, action);
  resp = get_surl_for_endpoint(SURL_METHOD_POST, endpoint_buf);

  if (resp) {
    surl_send_data_params(0, SURL_DATA_X_WWW_FORM_URLENCODED_RAW);
    /* No need to send data */

    surl_read_response_header(resp);

    if (surl_response_ok(resp))
      r = 0;
  }

  surl_response_free(resp);
  return r;
}

void api_favourite_status(status *s) {
  if (s->reblog) {
    s = s->reblog;
  }

  if ((s->favorited_or_reblogged & FAVOURITED) == 0) {
    if (api_interact(s->id, 's', "favourite") == 0) {
      s->favorited_or_reblogged |= FAVOURITED;
      s->n_favourites++;
    }
  } else {
    if (api_interact(s->id, 's', "unfavourite") == 0) {
      s->favorited_or_reblogged &= ~FAVOURITED;
      s->n_favourites--;
    }
  }
}

void api_reblog_status(status *s) {
  if (s->reblog) {
    s = s->reblog;
  }

  if ((s->favorited_or_reblogged & REBLOGGED) == 0) {
    if (api_interact(s->id, 's', "reblog") == 0) {
      s->favorited_or_reblogged |= REBLOGGED;
      s->n_reblogs++;
    }
  } else {
    if (api_interact(s->id, 's', "unreblog") == 0) {
      s->favorited_or_reblogged &= ~REBLOGGED;
      s->n_reblogs--;
    }
  }
}

char api_delete_status(status *s) {
  surl_response *resp;
  char r = -1;

  if (s->reblog) {
    return r;
  }

  snprintf(endpoint_buf, ENDPOINT_BUF_SIZE, "%s/%s", STATUS_ENDPOINT, s->id);
  resp = get_surl_for_endpoint(SURL_METHOD_DELETE, endpoint_buf);

  if (resp && surl_response_ok(resp)) {
    r = 0;
  }

  surl_response_free(resp);
  return r;
}

char api_relationship_get(account *a, char f) {
  surl_response *resp;
  char r = 0;
  char n_lines, **lines;
  resp = NULL;

  if ((a->relationship & RSHIP_SET) == 0) {
    snprintf(endpoint_buf, ENDPOINT_BUF_SIZE, "%s/relationships?id[]=%s", ACCOUNTS_ENDPOINT, a->id);
    resp = get_surl_for_endpoint(SURL_METHOD_GET, endpoint_buf);

    if (!surl_response_ok(resp))
      goto err_out;

    if (surl_get_json(gen_buf, BUF_SIZE, SURL_HTMLSTRIP_NONE, NULL, 
                      ".[]|.following,.followed_by,"
                      ".blocking,.blocked_by,.muting,.requested") >= 0) {
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

void account_toggle_rship(account *a, char action) {
  if (a) {
    /* at this point we're sure to have the relationship bitfield set
     * so avoid the wrapper */
    switch(action) {
      case RSHIP_FOLLOWING:
        api_interact(a->id, 'a',
          api_relationship_get(a, RSHIP_FOLLOWING|RSHIP_FOLLOW_REQ) ? "unfollow":"follow");
        return;
      case RSHIP_BLOCKING:
        api_interact(a->id, 'a',
          api_relationship_get(a, RSHIP_BLOCKING) ? "unblock":"block");
        return;
      case RSHIP_MUTING:
        api_interact(a->id, 'a',
          api_relationship_get(a, RSHIP_MUTING) ? "unmute":"mute");
        return;
    }
  }
}

account *api_get_full_account(char *id) {
  surl_response *resp;
  account *a;

  a = NULL;

  snprintf(endpoint_buf, ENDPOINT_BUF_SIZE, "%s/%s", ACCOUNTS_ENDPOINT, id);
  resp = get_surl_for_endpoint(SURL_METHOD_GET, endpoint_buf);
  
  if (resp && surl_response_ok(resp)) {
    a = account_new_from_json();
  }

  surl_response_free(resp);
  return a;
}
