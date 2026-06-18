#ifndef DIJKSTRA_H
#define DIJKSTRA_H

#include "graph.h"
#include "heap.h"
#include <string>

// Do not change the class name
class Dijkstra {
public:
    // Do not change the declaration of the function below
    Dijkstra(Graph* graph);
    
    // Do not change the declaration of the function below 
    // This prints each place in the fastest path sequentially, including the source and destination, separated by a single space (" "). If there are multiple shortest paths, you may print any one of them.
    void get_fastest_path(const std::string& source, const std::string& destination);
    
    // Do not change the declaration of the function below
    // This prints the sum of the distances of the fastest path.
    void get_fastest_distance(const std::string& source, const std::string& destination);

    /* add whatever you want*/
    Graph* graph;
};

/* add whatever you want*/

#endif // DIJKSTRA_H