#ifndef GRAPH_H
#define GRAPH_H

#include <iostream>
#include <string>
#include "my_vector.h"

/*
Implement a graph to represent the campus, where places are vertices and distances are weights in edges. 
Use an adjacency list we learned in the class to efficiently represent the graph.
*/

struct Vertex;
struct Edge;

struct Vertex {
    std::string place;  // element
    my_vector<Edge*> edges;  // edges connected to this vertex

    Vertex() : place(""), edges(my_vector<Edge*>()) {}
    Vertex(const std::string& _place) : place(_place), edges(my_vector<Edge*>()) {}
};

struct Edge {
    int distance;  // element
    Vertex* s;  // origin vertex object
    Vertex* e;  // destination vertex object

    Edge() : s(nullptr), e(nullptr), distance(0) {}
    Edge(Vertex* _s, Vertex* _e, int _distance) : s(_s), e(_e), distance(_distance) {}
};

// Do not change the class name
class Graph {
public:

    // Do not change the declaration of the function below
    Graph();

    // Do not change the declaration of the function below
    ~Graph();

    // Do not change the declaration of the function below
    void insert_vertex(const std::string& place);

    // Do not change the declaration of the function below
    void insert_edge(const std::string& v, const std::string& w, int distance);

    // Do not change the declaration of the function below
    void erase_vertex(const std::string& place);

    // Do not change the declaration of the function below
    void erase_edge(const std::string& v, const std::string& w);

    // Do not change the declaration of the function below
    bool is_adjacent_to(const std::string& v, const std::string& w) const;

    // Do not change the declaration of the function below
    // This prints the structure of the graph. The format is as follows: for each line, print each edge in the format "node1 node2 weight of the edge," with each element separated by a single space.
    void print_graph() const;

    /* add whatever you want*/
    my_vector<Vertex*> vertices;
    my_vector<Edge*> edges;

    Vertex* get_vertex(const std::string& place) const;
    int get_vertex_index(const std::string& place) const;
};

/* add whatever you want*/

#endif // GRAPH_H