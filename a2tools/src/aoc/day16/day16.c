#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#ifdef __CC65__
#include <apple2.h>
#endif
#include "bfs.h"
#include "extended_string.h"
#include "slist.h"

#define BUFSIZE 255
static void read_file(FILE *fp);

#define DATASET "IN16"

int main(int argc, char **argv) {
  FILE *fp;

#ifdef PRODOS_T_TXT
  _filetype = PRODOS_T_TXT;
#endif
  if (argc > 1)
    fp = fopen(argv[1],"r");
  else
    fp = fopen(DATASET, "r");
  if (fp == NULL) {
    printf("Error %d\n", errno);
    exit(1);
  }

  read_file(fp);

  exit (0);
}

static char **valve_name = NULL;
static short *valve_flow;
static short num_valves;

static int get_valve_by_name(const char *name) {
  int i;
  for (i = 0; i < num_valves; i++) {
    if (!strcmp(name, valve_name[i]))
      return i;
  }
  return -1;
}

static int find_optimal_flow(short start_valve, short time, short **bfs_dists, short *targets, int num_targets, int depth) {
  int optimal_flow = 0, i;
  char *prefix = malloc(depth+2);
  int time_rem;
  int start_valve_in_targets = -1;
  short cur_valve;
  for (i = 0; i < depth; i++) {
    prefix[i] = ' ';
  }
  prefix[i] = '\0';
  
  for (i = 0; i < num_targets; i++) {
    if(targets[i] == start_valve) {
      start_valve_in_targets = i;
    }
  }

  targets[start_valve_in_targets] = -1;

  for (i = 0; i < num_targets; i++) {
    if (targets[i] < 0) {
      continue;
    }
    cur_valve = targets[i];
    /* time to travel + time to open */
    time_rem = time - bfs_dists[start_valve][cur_valve] - 1;
    if (time_rem > 0) {
      int path_flow = valve_flow[cur_valve] * time_rem;
//      printf("%sopen valve %s (%d * %d = %d) + \n", prefix, valve_name[i], valve_flow[i], time_rem, valve_flow[i] * time_rem);
      path_flow += find_optimal_flow(cur_valve, time_rem, bfs_dists, targets, num_targets, depth + 1);
//      printf("%stotal = %d\n", prefix, path_flow);
      if (path_flow > optimal_flow) {
        optimal_flow = path_flow;
      }
    }
  }
  targets[start_valve_in_targets] = start_valve;

//  printf("%soptimum found = %d\n", prefix, optimal_flow);
  free(prefix);
  return optimal_flow;
}

static void read_file(FILE *fp) {
  char *buf = malloc(BUFSIZE);
  char **valve_destinations_str = NULL;
  short count = 0;
  short *targets = NULL;
  int num_targets = 0;
  short start_valve;
  bfs *b = NULL;
  short **bfs_dists = NULL;

  while (fgets(buf, BUFSIZE-1, fp) != NULL) {
    char *name = strchr(buf, ' ') + 1;
    char *flow_rate = strchr(buf, '=') + 1;
    char *paths_str = strstr(buf, "to valve") + strlen("to valve");
    char **paths = NULL;
    int i, num_paths;
    char *targets;
    int num_targets = 0;

    *strchr(name, ' ') ='\0';
    *strchr(flow_rate, ';') = '\0';
    paths_str = strchr(paths_str, ' ') +1;

    valve_name             = realloc(valve_name, (count + 1) * sizeof(char *));
    valve_destinations_str = realloc(valve_destinations_str, (count + 1) * sizeof(char *));
    valve_flow             = realloc(valve_flow, (count + 1) * sizeof(short));

    valve_name[count] = strdup(name);
    valve_destinations_str[count] = strdup(paths_str);
    valve_flow[count] = atoi(flow_rate);

    count++;
  }
  free(buf);
  fclose(fp);

  num_valves = count;

  b = bfs_new();
  bfs_add_nodes(b, num_valves);

  for (count = 0; count < num_valves; count++) {
    int num_dest, i;
    char **dests;
    short *valve_dests;

    num_dest = strsplit(valve_destinations_str[count], ' ', &dests);
    valve_dests = malloc(num_dest*sizeof(short));

    for (i = 0; i < num_dest; i++) {
      if (strchr(dests[i],','))
        *strchr(dests[i],',') = '\0';
      if (strchr(dests[i],'\n'))
        *strchr(dests[i],'\n') = '\0';

      valve_dests[i] = get_valve_by_name(dests[i]);
      free(dests[i]);
    }
    bfs_add_paths(b, count, valve_dests, num_dest);

    free(valve_destinations_str[count]);
    free(valve_dests);
    free(dests);
  }
  free(valve_destinations_str);

  bfs_dists = malloc(num_valves * sizeof(short *));

  /* Do the thing */
  start_valve = get_valve_by_name("AA");
  bfs_dists[start_valve] = bfs_compute_shortest_paths(b, start_valve);
  for (count = 0; count < num_valves; count++) {
    if (valve_flow[count] > 0 || count == start_valve) {
      targets = realloc(targets, (num_targets + 1) * sizeof(short));
      targets[num_targets] = count;
      num_targets++;
    }
    if (count != start_valve) {
      bfs_dists[count] = bfs_compute_shortest_paths(b, count);
    }
  }
  int num_c = 0;
  for (count = 0; count < num_valves; count++) {
    int i;
    for (i = 0; i < num_valves; i++) {
      if (bfs_dists[count][i] < 0) {
        printf("Graph not fully connected ! (%s => %s missing)\n", valve_name[count], valve_name[i]);
      }
      else if (count != i && bfs_dists[count][i] == 0) {
        printf("Graph not fully connected ! (%s => %s is 0)\n", valve_name[count], valve_name[i]);
      } else {
        num_c++;
      }
    }
  }
  printf("Graph fully connected with %d (num_valves %d) connections\n", num_c, num_valves);
  printf("best flow in part 1: %d\n", find_optimal_flow(start_valve, 30, bfs_dists, targets, num_targets, 0));
  
  /* free; keep Valgrind happy */
  for (count = 0; count < num_valves; count++) {
    free(valve_name[count]);
    free(bfs_dists[count]);
  }
  free(bfs_dists);
  free(valve_name);
  free(valve_flow);
  free(targets);
  bfs_free(b);
}
