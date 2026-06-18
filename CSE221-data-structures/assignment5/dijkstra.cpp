/* add whatever you want*/
#include "dijkstra.h"
using namespace std;
#define INF INT_MAX

Dijkstra::Dijkstra(Graph* graph) {
    this->graph = graph;
}

void Dijkstra::get_fastest_path(const std::string& source, const std::string& destination) {
    int vertices_size = graph->vertices.size();
    int source_index = graph->get_vertex_index(source);
    int destination_index = graph->get_vertex_index(destination);

    Heap priority_queue(vertices_size);  // new heap-based priority queue
    my_vector<int> dist(vertices_size, INF);  // distance array
    my_vector<int> prev(vertices_size, -1);  // previous vertex array
    dist[source_index] = 0;  // set the distance of the source to 0

    for(int i = 0; i < vertices_size; i++){
        priority_queue.insert(dist[i], graph->vertices[i]->place);  // Q.insert(v.getDistance(), v)
    }

    while(!priority_queue.empty()){
        std::string u = priority_queue.get_min().value;  // l.getValue() : take out the closest node
        int u_index = graph->get_vertex_index(u);
        priority_queue.remove_min();  // Q.removeMin()
            
        my_vector edges_from_u = graph->vertices[u_index]->edges;
        for(int i = 0; i < edges_from_u.size(); i++){
             // z <- e.opposite(u)
            std::string z = edges_from_u[i]->s->place;
            if (z == u) z = edges_from_u[i]->e->place;
            int z_index = graph->get_vertex_index(z);

            // std::cout << u << " <-> " << z << " = " << edges_from_u[i]->distance << "\n";

            if (dist[u_index]==INF) continue;  // if u.getDistance() == INF, continue
            int r = dist[u_index] + edges_from_u[i]->distance;  // r <- u.getDistance() + e.weight()

            if(r < dist[z_index]){  // if r < z.getDistance()
                dist[z_index] = r;  // z.setDistance(r)
                prev[z_index] = u_index;  // z.setPrev(u)
                int z_entry = priority_queue.get_entry(z);
                priority_queue.replace_key(z_entry, r);  // Q.replaceKey(z.getEntry(), r)
            }
        }
    }

    // No path
    if (dist[destination_index] == INF) {
        std::cout << "No path\n";
        return;
    }

    // Shortest path backtracking
    my_vector<std::string> path;
    int current = destination_index;
    while(current != -1){
        path.push_back(graph->vertices[current]->place);
        current = prev[current];
    }
    for(int i = path.size()-1; i >= 0; i--){
        std::cout << path[i] << " ";
    }
    std::cout << "\n";
}

void Dijkstra::get_fastest_distance(const std::string& source, const std::string& destination) {
    int vertices_size = graph->vertices.size();
    int source_index = graph->get_vertex_index(source);
    int destination_index = graph->get_vertex_index(destination);

    Heap priority_queue(vertices_size);  // new heap-based priority queue
    my_vector<int> dist(vertices_size, INF);  // distance array
    dist[source_index] = 0;  // set the distance of the source to 0

    for(int i = 0; i < vertices_size; i++){
        priority_queue.insert(dist[i], graph->vertices[i]->place);  // Q.insert(v.getDistance(), v)
    }

    while(!priority_queue.empty()){
        std::string u = priority_queue.get_min().value;  // l.getValue() : take out the closest node
        int u_index = graph->get_vertex_index(u);
        priority_queue.remove_min();  // Q.removeMin()
            
        my_vector edges_from_u = graph->vertices[u_index]->edges;
        for(int i = 0; i < edges_from_u.size(); i++){
             // z <- e.opposite(u)
            std::string z = edges_from_u[i]->s->place;
            if (z == u) z = edges_from_u[i]->e->place;
            int z_index = graph->get_vertex_index(z);

            // std::cout << u << " <-> " << z << " = " << edges_from_u[i]->distance << "\n";

            if (dist[u_index]==INF) continue;  // if u.getDistance() == INF, continue
            int r = dist[u_index] + edges_from_u[i]->distance;  // r <- u.getDistance() + e.weight()

            if(r < dist[z_index]){  // if r < z.getDistance()
                dist[z_index] = r;  // z.setDistance(r)
                int z_entry = priority_queue.get_entry(z);
                priority_queue.replace_key(z_entry, r);  // Q.replaceKey(z.getEntry(), r)
            }
        }
    }

    if (dist[destination_index] == INF) std::cout << "No path\n";
    else std::cout << dist[destination_index] << "\n";


    // For debugging
    // for(int i = 0; i < vertices_size; i++){
    //     std::cout << graph->vertices[i]->place << " " << dist[i] << "\n";
    // }std::cout << "\n";
}