/* You cannot modify this file */
#ifndef DOUBLY_LINKED_LIST_H
#define DOUBLY_LINKED_LIST_H

#include <string>

class Node {
    std::string ele;
    Node* prev;
    Node* next;
    friend class DoublyLinkedList;
};

class DoublyLinkedList {
private:
    
    Node* header;
    Node* trailer;

public:
    DoublyLinkedList();
    ~DoublyLinkedList();
    bool empty() const;
    const std::string& front() const;
    const std::string& back() const;
    void add_front(const std::string& e);
    void add_back(const std::string& e);
    void remove_front();
    void remove_back();
    int size() const;
};

#endif // DOUBLY_LINKED_LIST_H