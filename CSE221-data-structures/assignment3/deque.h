/* You cannot modify this file */
#ifndef DEQUE_H
#define DEQUE_H

#include "doubly_linked_list.h"

class Deque {
private:
    DoublyLinkedList list;
public:
    bool empty() const;
    int size() const;
    const std::string& front() const;
    const std::string& back() const;
    void push_front(const std::string& e);
    void push_back(const std::string& e);
    void pop_front();
    void pop_back();
    void reverse();
};

#endif // DEQUE_H