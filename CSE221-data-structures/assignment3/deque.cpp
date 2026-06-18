/* Write your code here */

#include "deque.h"
#include "stack.h"
#include "container_exception.h"
using namespace std;

// 1. size(): Returns the number of elements in the deque. O(n)
// At this Assignment, I used DoublyLinkedList's size() function.
// So, the time complexity is O(n).
// Because there is no size variable in DoublyLinkedList.
int Deque::size() const {
    return list.size();
}

// 2. empty(): Checks if the deque is empty. O(1)
bool Deque::empty() const {
    return list.empty();
}

// 3. push_front(const std::string& e): Adds an element to the front of the deque. O(1)
void Deque::push_front(const string& e) {
    list.add_front(e);
}

// 4. push_back(const std::string& e): Adds an element to the back of the deque. O(1)
void Deque::push_back(const string& e) {
    list.add_back(e);
}

// 5. pop_front(): Removes the front element from the deque. O(1)
void Deque::pop_front() {
    list.remove_front();
}

// 6. pop_back(): Removes the back element from the deque. O(1)
void Deque::pop_back() {
    list.remove_back();
}

// 7. front(): Returns the front element. O(1)
const string& Deque::front() const {
    return list.front();
}

// 8. back(): Returns the back element. O(1)
const string& Deque::back() const {
    return list.back();
}

// 9. Deque reverse() Implementation (Based on Stack) O(n)
void Deque::reverse() {
    Stack stack(size());
    while(!list.empty()) {
        stack.push(list.front());
        list.remove_front();
    }
    while(!stack.empty()) {
        list.add_back(stack.top());
        stack.pop();
    }
}