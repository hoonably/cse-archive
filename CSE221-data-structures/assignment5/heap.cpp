/* add whatever you want*/
#include "heap.h"


Heap::Heap(int capacity){
    this->capacity = capacity;
    heap = new Node[capacity+1];
    last_rank = 0;
}


Heap::~Heap(){
    delete[] heap;
}


bool Heap::empty() const{
    return last_rank == 0;
}


void Heap::insert(int key, const std::string& value){
    if (last_rank++ >= capacity) {
        throw std::runtime_error("Heap is full.");
    }
    heap[last_rank] = Node(key, value);
    int rank = last_rank;
    while(rank > 1 && heap[rank] < heap[rank/2]){
        heap[rank].swap(heap[rank/2]);
        rank /= 2;
    }
}


void Heap::remove_min(){
    if (last_rank == 0) {
        throw std::runtime_error("Heap is empty.");
    }
    heap[1].swap(heap[last_rank]);
    last_rank--;
    int current = 1;
    while (current <= last_rank) {
        int left = current * 2;
        int right = current * 2 + 1;
        int min_index = current;
        // Find the minimum of the current node and its children
        if (left <= last_rank && heap[left] < heap[min_index]) min_index = left;
        if (right <= last_rank && heap[right] < heap[min_index]) min_index = right;
        // If the current node is the minimum, stop
        if (min_index == current) break;
        heap[current].swap(heap[min_index]);
        current = min_index;
    }
}


// This assumes that it's a vector-based heap implementation. Here, "index" means the rank in the vector-based heap implementation, and it starts from 1 (root).
void Heap::replace_key(int index, int new_key){
    if (index > last_rank) {
        throw std::runtime_error("Index out of range.");
    }
    heap[index].key = new_key;
    while(index > 1 && heap[index] < heap[index/2]){
        heap[index].swap(heap[index/2]);
        index /= 2;
    }
    // 이거 downheap도 해줘야하는데 구현 안한듯?
    
}


// This prints the keys in the heap. 
void Heap::print_heap() const{
    if (empty()) return;
    int depth = 1;
    int rank = 1;
    while(true) {
        std::cout << heap[rank].key << " ";
        // For each line, print the keys at the same depth, 
        // from left to right, separated by a single space (" "). 
        // It starts with the root node and proceeds to the deepest nodes, increasing the depth by one for each line.
        if (rank>=last_rank) break;

        if (rank == (1 << depth) - 1) {
            depth++;
            std::cout << "\n";
        }
        rank++;
    }
    std::cout << "\n";
}

Heap::Node Heap::get_min() {
    return heap[1];
}

int Heap::get_entry(const std::string& value) {
    for (int idx = 1; idx <= last_rank; idx++) {
        if (heap[idx].value == value) return idx;
    }
    return -1;
}