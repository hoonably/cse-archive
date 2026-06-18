#ifndef HEAP_H
#define HEAP_H

#include <iostream>
#include <string>

// Do not change the class name
class Heap {
public:
    struct Node {
        bool operator<(const Node& other) const {
            return key < other.key;
        }
        void swap(Node &other) {
            int temp_key = key;
            std::string temp_value = value;
            key = other.key;
            value = other.value;
            other.key = temp_key;
            other.value = temp_value;
        }
        int key;
        std::string value;
        Node() : key(0), value("") {}
        Node(int key, const std::string& value) : key(key), value(value) {}
    };

    // Do not change the declaration of the function below
    Heap(int capacity);

    // Do not change the declaration of the function below
    ~Heap();

    // Do not change the declaration of the function below
    bool empty() const;

    // Do not change the declaration of the function below
    void insert(int key, const std::string& value);

    // Do not change the declaration of the function below
    void remove_min();

    // Do not change the declaration of the function below
    // This assumes that it's a vector-based heap implementation. Here, "index" means the rank in the vector-based heap implementation, and it starts from 1 (root).
    void replace_key(int index, int new_key);

    // Do not change the declaration of the function below
    // This prints the keys in the heap. For each line, print the keys at the same depth, from left to right, separated by a single space (" "). It starts with the root node and proceeds to the deepest nodes, increasing the depth by one for each line.
    void print_heap() const;

    /* add whatever you want*/
    int capacity;
    Node *heap;
    int last_rank;  // 1(root) <= last_rank < capacity

    Node get_min();
    int get_entry(const std::string& value);
};

/* add whatever you want*/


#endif // HEAP_H