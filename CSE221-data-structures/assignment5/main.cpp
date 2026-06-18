#include <iostream>
#include <exception>
#include "graph.h"
#include "heap.h"
#include "dijkstra.h"

using namespace std;

void test_graph(){
    std::cout << "Testing Graph Implementation:\n";
    Graph graph;
    graph.insert_vertex("MomsTouch");
    graph.insert_vertex("KimbapHeaven");
    graph.insert_vertex("Dorm");
    graph.insert_edge("MomsTouch", "KimbapHeaven", 5);
    graph.insert_edge("KimbapHeaven", "Dorm", 3);
    graph.insert_edge("MomsTouch", "Dorm", 10);
    graph.print_graph();

    // erase vertex test
    // graph.erase_vertex("KimbapHeaven");
    // std::cout << "\nGraph after erasing KimbapHeaven:\n";
    // graph.print_graph();

    std::cout << "\nIs MomsTouch adjacent to KimbapHeaven? " << (graph.is_adjacent_to("MomsTouch", "KimbapHeaven") ? "Yes" : "No") << "\n";
    std::cout << "\nIs MomsTouch adjacent to KimbapHeaven? " << (graph.is_adjacent_to("KimbapHeaven", "MomsTouch") ? "Yes" : "No") << "\n";

    graph.erase_edge("KimbapHeaven", "MomsTouch");  // 순서 반대
    // graph.erase_edge("MomsTouch", "KimbapHeaven");
    std::cout << "\nGraph after erasing edge between MomsTouch and KimbapHeaven:\n";
    graph.print_graph();

    graph.erase_edge("KimbapHeaven", "Dorm");
    
    std::cout << "\nGraph after erasing edge between KimbapHeaven and Dorm:\n";
    graph.print_graph();

    graph.erase_edge("Dorm", "MomsTouch");
    std::cout << "\nGraph after erasing edge between KimbapHeaven and Dorm:\n";
    graph.print_graph();

    std::cout << "\nIs MomsTouch adjacent to KimbapHeaven? " << (graph.is_adjacent_to("MomsTouch", "KimbapHeaven") ? "Yes" : "No") << "\n";
}

void test_heap(){
    std::cout << "\nTesting Heap Implementation:\n";
    Heap heap(15); // Heap with capacity 15
    heap.insert(10, "Value10");
    heap.insert(20, "Value20");
    heap.insert(5, "Value5");
    heap.insert(4, "Value4");
    heap.insert(15, "Value15");   // 5th element
    heap.insert(3, "Value3");
    heap.insert(2, "Value2");
    heap.insert(1, "Value1");
    heap.insert(6, "Value6");
    heap.insert(7, "Value7");  // 10th element
    heap.insert(8, "Value8");
    heap.insert(9, "Value9");
    heap.insert(11, "Value11");
    heap.insert(12, "Value12");
    heap.insert(12, "Value12");  // 15th element
    // heap.insert(13, "Value13"); // Heap is full


    heap.print_heap();

    // replace key test
    heap.replace_key(15, 3); // Replace key at index 15 with 3
    std::cout << "\nHeap after replacing key at index 15 with 3:  !!!!!!!!!!!!!!\n";
    heap.print_heap();

    heap.replace_key(12, 3); // Replace key at index 12 with 3
    std::cout << "\nHeap after replacing key at index 12 with 2:  !!!!!!!!!!!!!!\n";
    heap.print_heap();

    heap.remove_min();
    std::cout << "\nHeap after removing min:\n";
    heap.print_heap();


    // remove all test
    heap.insert(0, "Value0");
    std::cout << "\nHeap after inserting 0:\n";
    heap.print_heap();

    for(int i=1; i<=15; i++){
        heap.remove_min();
        std::cout << "\nHeap after removing min:\n"; heap.print_heap();
    }
}

void test_dijkstra(){
    std::cout << "\nTesting Dijkstra's algorithm:\n";
    Graph graph2;
    graph2.insert_edge("MomsTouch", "KimbapHeaven", 2);
    graph2.insert_edge("MomsTouch", "Dorm", 5);
    graph2.insert_edge("KimbapHeaven", "Dorm", 1);
    graph2.insert_edge("KimbapHeaven", "GamakLake", 2);
    graph2.insert_edge("Dorm", "GamakLake", 3);
    graph2.insert_edge("Dorm", "Library", 1);
    graph2.insert_edge("GamakLake", "Library", 2);

    Dijkstra dijkstra(&graph2);
    // While you are at MomsTouch, you discover that the cat is in the library!
    std::cout << "Fastest path from MomsTouch to Library:\n";
    dijkstra.get_fastest_path("MomsTouch", "Library");
    std::cout << "Fastest distance from MomsTouch to Library:\n";
    dijkstra.get_fastest_distance("MomsTouch", "Library");

    // While you are at MomsTouch, you discover that the cat is in the GamakLake!
    std::cout << "Fastest path from MomsTouch to GamakLake:\n";
    dijkstra.get_fastest_path("MomsTouch", "GamakLake");
    std::cout << "Fastest distance from MomsTouch to GamakLake:\n";
    dijkstra.get_fastest_distance("MomsTouch", "GamakLake");

    // 그래프 edge 삭제 후 비교
    std::cout << "\nErasing edge between MomsTouch and KimbapHeaven\n";
    graph2.erase_edge("MomsTouch", "KimbapHeaven");
    std::cout << "Fastest path from MomsTouch to GamakLake:\n";
    dijkstra.get_fastest_path("MomsTouch", "GamakLake");
    std::cout << "Fastest distance from MomsTouch to GamakLake:\n";
    dijkstra.get_fastest_distance("MomsTouch", "GamakLake");

    std::cout << "\nErasing edge between Dorm and GamakLake\n";
    graph2.erase_edge("Dorm", "GamakLake");
    std::cout << "Fastest path from MomsTouch to GamakLake:\n";
    dijkstra.get_fastest_path("MomsTouch", "GamakLake");
    std::cout << "Fastest distance from MomsTouch to GamakLake:\n";
    dijkstra.get_fastest_distance("MomsTouch", "GamakLake");
}

void test_dijkstra2(){
    std::cout << "\nTesting Dijkstra's algorithm:\n";
    Graph graph2;
    graph2.insert_edge("A", "B", 4);
    graph2.insert_edge("A", "C", 7);
    graph2.insert_edge("B", "C", 5);
    graph2.insert_edge("B", "D", 17);
    graph2.insert_edge("C", "D", 20);
    graph2.insert_edge("C", "E", 12);
    graph2.insert_edge("D", "E", 14);
    graph2.insert_edge("D", "F", 18);

    Dijkstra dijkstra(&graph2);


    std::cout << "Fastest path from A to F:\n";
    dijkstra.get_fastest_path("A", "F");
    std::cout << "Fastest distance from A to F:\n";
    dijkstra.get_fastest_distance("A", "F");
    std::cout << "Fastest path from F to A:\n";
    dijkstra.get_fastest_path("F", "A");
    std::cout << "Fastest distance from F to A:\n";
    dijkstra.get_fastest_distance("F", "A");

    std::cout << "\nErasing edge between A and B\n";
    graph2.erase_edge("A", "B");
    std::cout << "Fastest path from A to F:\n";
    dijkstra.get_fastest_path("A", "F");
    std::cout << "Fastest distance from A to F:\n";
    dijkstra.get_fastest_distance("A", "F");

    std::cout << "Fastest path from F to A:\n";
    dijkstra.get_fastest_path("F", "A");
    std::cout << "Fastest distance from F to A:\n";
    dijkstra.get_fastest_distance("F", "A");

    std::cout << "\nErasing edge between D and F\n";
    graph2.erase_edge("D", "F");
    std::cout << "Fastest path from A to F:\n";
    dijkstra.get_fastest_path("A", "F");
    std::cout << "Fastest distance from A to F:\n";
    dijkstra.get_fastest_distance("A", "F");  // No path

    std::cout << "Fastest path from F to A:\n";
    dijkstra.get_fastest_path("F", "A");
    std::cout << "Fastest distance from F to A:\n";
    dijkstra.get_fastest_distance("F", "A");  // No path

}

int main() {

    test_graph();
    // test_heap();
    // test_dijkstra();
    // test_dijkstra2();

    return 0;
}