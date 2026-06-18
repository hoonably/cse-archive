/* Write your code here */

#include "stack.h"
#include "container_exception.h"
using namespace std;

// 1. Constructor: Takes an integer parameter for the initial stack capacity.
Stack::Stack(int size) {
    capacity = size;
    top_index = -1;
    data = new string[capacity];
}

// 2. Destructor: Frees the allocated memory.
Stack::~Stack() {
    delete[] data;
}

// 3. size(): Returns the number of elements currently in the stack. O(1)
int Stack::size() const {
    return top_index + 1;
}


// 4. empty(): Checks if the stack is empty. O(1)
bool Stack::empty() const {
    return top_index < 0;
}

// 5. top(): Returns the top element of the stack.O(1)
const string& Stack::top() const {
    if (empty()) {
        throw ContainerEmpty("Container is empty");
    }
    return data[top_index];
}

// 6. push(const std::string& e): Adds an element to the top of the stack. O(1)
void Stack::push(const string& e) {
    if (size() == capacity) {
        throw ContainerOverflow("Container is full");
    }
    top_index++;
    data[top_index] = e;
}

// 7. pop(): Removes the top element of the stack. O(1)
void Stack::pop() {
    if (empty()) {
        throw ContainerEmpty("Container is empty");
    }
    top_index--;
}
