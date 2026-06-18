/* add whatever you want*/
#include "graph.h"

/*
Implement a graph to represent the campus, where places are vertices and distances are weights in edges.
Use an adjacency list we learned in the class to efficiently represent the graph.
*/

Graph::Graph(){
    vertices = my_vector<Vertex*>();
    edges = my_vector<Edge*>();
}

Graph::~Graph() {}

Vertex* Graph::get_vertex(const std::string& place) const{
    for(int i = 0; i < vertices.size(); i++){
        if(vertices[i]->place == place){
            return vertices[i];
        }
    }
    return nullptr;
}

void Graph::insert_vertex(const std::string& place){
    vertices.push_back(new Vertex(place));
}

void Graph::insert_edge(const std::string& v, const std::string& w, int distance){
    // Undirected Graph : Insert edge (v, w) and (w, v)
    Vertex* vertex_v = get_vertex(v);
    Vertex* vertex_w = get_vertex(w);
    
    // if vertex v or w doesn't exist, create vertex
    if (vertex_v == nullptr){
        insert_vertex(v);
        vertex_v = get_vertex(v);
    }
    if (vertex_w == nullptr){
        insert_vertex(w);
        vertex_w = get_vertex(w);
    }
    
    Edge* new_edge_vw = new Edge(vertex_v, vertex_w, distance);
    vertex_v->edges.push_back(new_edge_vw);
    vertex_w->edges.push_back(new_edge_vw);
    edges.push_back(new_edge_vw);
}

void Graph::erase_vertex(const std::string& place){
    // erase vertex and edges connected to the vertex
    Vertex* v = get_vertex(place);
    if (v == nullptr){
        // don't have vertex
        return;
    }

    my_vector<Edge*> &v_edges = v->edges;
    for(int i = 0; i < v_edges.size(); i++){
        // erase edges connected to the vertex
        erase_edge(v_edges[i]->s->place, v_edges[i]->e->place);
    }
    // erase vertex
    for(int i = 0; i < vertices.size(); i++){
        if(vertices[i] == v){
            // change last vertex to the position of the vertex to be deleted
            vertices[i] = vertices[vertices.size()-1];
            vertices.pop_back();
            break;
        }
    }
    delete v;
}

void Graph::erase_edge(const std::string& v, const std::string& w){
    // erase edge (v, w) and (w, v)
    Vertex* vertex_v = get_vertex(v);
    Vertex* vertex_w = get_vertex(w);

    if (vertex_v == nullptr || vertex_w == nullptr){
        // don't have vertex v or w
        return;
    }

    my_vector<Edge*> &v_edges = vertex_v->edges;
    for(int i = 0; i < v_edges.size(); i++){
        if(v_edges[i]->s == vertex_w || v_edges[i]->e == vertex_w){
            // change last edge to the position of the edge to be deleted
            v_edges[i] = v_edges[v_edges.size()-1];
            v_edges.pop_back();
            break;
        }
    }
    my_vector<Edge*> &w_edges = vertex_w->edges;
    for(int i = 0; i < w_edges.size(); i++){
        if(w_edges[i]->s == vertex_v || w_edges[i]->e == vertex_v){
            // change last edge to the position of the edge to be deleted
            w_edges[i] = w_edges[w_edges.size()-1];
            w_edges.pop_back();
            break;
        }
    }
    for(int i = 0; i < edges.size(); i++){
        if((edges[i]->s == vertex_v && edges[i]->e == vertex_w) || (edges[i]->s == vertex_w && edges[i]->e == vertex_v)){
            // change last edge to the position of the edge to be deleted
            edges[i] = edges[edges.size()-1];
            edges.pop_back();
            break;
        }
    }
}

bool Graph::is_adjacent_to(const std::string& v, const std::string& w) const{
    Vertex* vertex_v = get_vertex(v);
    Vertex* vertex_w = get_vertex(w);
    if (vertex_v == nullptr || vertex_w == nullptr){
        // don't have vertex v or w
        return false;
    }
    for(int i = 0; i < edges.size(); i++){
        if(edges[i]->s == vertex_v && edges[i]->e == vertex_w || edges[i]->s == vertex_w && edges[i]->e == vertex_v){
            return true;
        }
    }
    return false;
}

// This prints the structure of the graph. The format is as follows: for each line, print each edge in the format "node1 node2 weight of the edge," with each element separated by a single space.
void Graph::print_graph() const{
    for(int i = 0; i < edges.size(); i++){
        std::cout << edges[i]->s->place << " " << edges[i]->e->place << " " << edges[i]->distance << std::endl;
    }
}

int Graph::get_vertex_index(const std::string& place) const{
    for(int i = 0; i < vertices.size(); i++){
        if(vertices[i]->place == place){
            return i;
        }
    }
    return -1;  // not found
}