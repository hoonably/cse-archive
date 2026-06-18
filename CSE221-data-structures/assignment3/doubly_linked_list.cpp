/* Write your code here */

#include "doubly_linked_list.h"
#include "container_exception.h"
using namespace std;

// Constructor: Initializes an empty list with header and trailer. “header” and “trailer” are
// pointing each other at initialization.
DoublyLinkedList::DoublyLinkedList() {
    header = new Node;
    trailer = new Node;
    header->next = trailer;
    trailer->prev = header;
}


// Destructor: Frees all allocated memory.
DoublyLinkedList::~DoublyLinkedList() {
    while (!empty()) remove_front();
    delete header;
    delete trailer;
}

// 3. size(): Returns the number of elements in the list. O(n)
int DoublyLinkedList::size() const{
    int cnt = 0;
    Node* now = header->next;
    while (now != trailer) {
        cnt++;
        now = now->next;
    }
    return cnt;
}

// 4. empty(): Checks if the list is empty. O(1)
bool DoublyLinkedList::empty() const{
    return header->next == trailer;
}

// 5. front(): Returns the front element. O(1)
const std::string& DoublyLinkedList::front() const{
    if (empty()) {
        throw ContainerEmpty("Container is empty");
    }
    return header->next->ele;
}

// 6. back(): Returns the back element. O(1)
const std::string& DoublyLinkedList::back() const{
    if (empty()) {
        throw ContainerEmpty("Container is empty");
    }
    return trailer->prev->ele;
}

// 7. add_front(const std::string& e): Adds an element to the front of the list. O(1)
void DoublyLinkedList::add_front(const std::string& e){
    Node* new_node = new Node;
    new_node->ele = e;
    new_node->next = header->next;  // 기존의 첫 노드가 new_node의 next가 됨
    new_node->prev = header;

    header->next->prev = new_node;  // 기존의 첫 노드의 prev가 new_node가 됨
    header->next = new_node;
}

// 8. add_back(const std::string& e): Adds an element to the back of the list. O(1)
void DoublyLinkedList::add_back(const std::string& e){
    Node* new_node = new Node;
    new_node->ele = e;
    new_node->next = trailer;
    new_node->prev = trailer->prev;  // 기존의 마지막 노드가 new_node의 prev가 됨

    trailer->prev->next = new_node;  // 기존의 마지막 노드의 next가 new_node가 됨
    trailer->prev = new_node;
}

// 9. remove_front(): Removes the front element. O(1)
void DoublyLinkedList::remove_front(){
    if (empty()) {
        throw ContainerEmpty("Container is empty");
    }
    Node* remove_node = header->next;
    header->next = remove_node->next;
    remove_node->next->prev = header;
    delete remove_node;
}

// 10. remove_back(): Removes the back element. O(1)
void DoublyLinkedList::remove_back(){
    if (empty()) {
        throw ContainerEmpty("Container is empty");
    }
    Node* remove_node = trailer->prev;
    trailer->prev = remove_node->prev;
    remove_node->prev->next = trailer;
    delete remove_node;
}
