#ifndef __poll_h
#define __poll_h

typedef struct _poll poll;
typedef struct _poll_option poll_option;

#define MAX_POLL_OPTIONS 4

struct _poll_option {
  char *title;
  size_t votes_count;
};

struct _poll {
  char *id;
  char multiple;
  size_t votes_count;
  char options_count;
  char own_votes[MAX_POLL_OPTIONS];
  poll_option options[MAX_POLL_OPTIONS];
};

#define poll_new() (poll *)malloc0(sizeof(poll))
void poll_free(poll *p);

void poll_fill(poll *p, const char from_reblog);

void poll_update_vote(poll *p);
#endif
