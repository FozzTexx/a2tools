#ifndef __bfs_h
#define __bfs_h

typedef struct _bfs bfs;

/* Must be freed by caller using bfs_free */
bfs *bfs_new(void);
void bfs_free(bfs *);

void bfs_add_nodes(bfs *b, int num_nodes);
void bfs_add_paths(bfs *b, short source, short *dest_nodes, int num_dests);

void bfs_enable_path_trace(bfs *b, int enable);

/* Not to be freed */
const short *bfs_compute_shortest_distances(bfs *b, short start_node);
short bfs_get_shortest_distance_to(bfs *b, short start_node, short end_node);
const short *bfs_get_shortest_path(bfs *b, short start_node, short end_node, int *path_len);

/* helper for grid. Use instead of bfs_add_nodes */
void bfs_set_grid(bfs *b, int max_x, int max_y);
int bfs_grid_to_node(bfs *b, int x, int y);
void bfs_node_to_grid(bfs *b, int node, int *x, int *y);
void bfs_grid_add_paths(bfs *b, int x, int y, short *dest_nodes, int num_dests);
const short *bfs_grid_compute_shortest_distances(bfs *b, int x, int y);
short bfs_grid_get_shortest_distance_to(bfs *b, int start_x, int start_y, int end_x, int end_y);
const short *bfs_grid_get_shortest_path(bfs *b, int start_x, int start_y, int end_x, int end_y, int *path_len);

#endif
