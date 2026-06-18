/* You cannot modify this file */
#ifndef STACK_H
#define STACK_H

#include <string>

class Stack {
private:
    int capacity; // total capcity of the stack
    int top_index; // index of the top element
    std::string* data; // data of the stack, an array of std:string.

public:
    Stack(int size = 100);
    ~Stack();
    bool empty() const;
    const std::string& top() const;
    void push(const std::string& e);
    void pop();
    int size() const;
};

#endif // STACK_H