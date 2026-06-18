#include "doubly_linked_list.h"
#include "stack.h"
#include "deque.h"
#include "container_exception.h"
#include <iostream>

int main() {
    try {
        // DoublyLinkedList Tests
        DoublyLinkedList dll;
        dll.add_front("First");
        dll.add_back("Second");
        std::cout << "Front: " << dll.front() << "\n"; // Output: First
        std::cout << "Back: " << dll.back() << "\n";  // Output: Second
        std::cout << "Size: " << dll.size() << "\n";
        dll.remove_front();
        dll.remove_back();

        // Stack Tests
        Stack stack(5);
        stack.push("One");
        stack.push("Two");
        std::cout << "Top: " << stack.top() << "\n"; // Output: Two
        stack.pop();
        std::cout << "Top: " << stack.top() << "\n"; // Output: One

        // Deque Tests
        Deque deque;
        deque.push_front("One");
        deque.push_back("Two");
        std::cout << "Front: " << deque.front() << "\n"; // Output: One
        std::cout << "Back: " << deque.back() << "\n";  // Output: Two

        // Deque Reverse
        deque.reverse();
        std::cout << "Front after reverse: " << deque.front() << "\n"; // Output: Two
        deque.pop_front();
        deque.pop_front();
        deque.pop_front(); // This throws an error

    } catch (const ContainerException& e) { // Exception Handling
        std::cerr << e.what() << std::endl;
    }
}