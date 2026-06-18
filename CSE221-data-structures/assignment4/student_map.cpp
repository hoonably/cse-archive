#include "student_map.h"
#include <stdexcept>
#include <iostream>
using namespace std;

/*
Implement a hash table to store student scores (value) by student ID (key). 
This unordered map allows quick retrieval and update operations by student ID.
• Data Structure: Hash Table
• Size of Hash Table: 1000
• Collision Handling Method: Separate Chaining
• You should properly implement an appropriate hash function.
*/

StudentMap::StudentMap() {
    hash_table = new Node*[TABLE_SIZE];
    for (int i = 0; i < TABLE_SIZE; i++) {
        // Node() : student_id(-1), score(-1), next(nullptr) {}
        hash_table[i] = new Node();
    }
}

int StudentMap::get_hash(int student_id) const {
    return student_id % TABLE_SIZE;
}

void StudentMap::add_student(int student_id, int score) {
    if (score<0 || score>100) throw std::runtime_error("Invalid score");
    /* Adds a student to the hash table. */
    int hash = get_hash(student_id);
    Node* now_node = hash_table[hash];
    while (now_node->next != nullptr) {
        now_node = now_node->next;
        if (now_node->student_id == student_id) {  // handle duplicate
            throw std::runtime_error("Already existing student ID");
        }
    }
    now_node->next = new Node(student_id, score);
}

void StudentMap::update_score(int student_id, int new_score) {
    if (new_score<0 || new_score>100) throw std::runtime_error("Invalid score");
    /* Updates the score of an existing student. */
    int hash = get_hash(student_id);
    Node* now_node = hash_table[hash];
    while (now_node->next != nullptr) {
        now_node = now_node->next;
        if (now_node->student_id == student_id) {  // found
            now_node->score = new_score;
            return;
        }
    }
    throw std::runtime_error("Student ID not found");  // now_node == nullptr
}

int StudentMap::get_score(int student_id) const {
    /* Retrieves the score of a specific student. 
    If there are multiple matches, returns the first student’s ID. */
    int hash = get_hash(student_id);
    Node* now_node = hash_table[hash];
    while (now_node->next != nullptr) {
        now_node = now_node->next;
        if (now_node->student_id == student_id) {  // found
            return now_node->score;
        }
    }
    throw std::runtime_error("Student ID not found");  // now_node == nullptr
}

void StudentMap::remove_student(int student_id) {
    /* Removes a student by ID from the hashtable. */
    int hash = get_hash(student_id);
    Node* now_node = hash_table[hash];
    Node* prev_node = nullptr;
    while (now_node->next != nullptr) {
        prev_node = now_node;
        now_node = now_node->next;
        if (now_node->student_id == student_id) {  // found
            prev_node->next = now_node->next;
            delete now_node;
            return;
        }
    }
    throw std::runtime_error("Student ID not found");  // now_node == nullptr
}

StudentMap::~StudentMap() {
    for (int i = 0; i < TABLE_SIZE; i++) {
        Node* now_node = hash_table[i];
        while (now_node != nullptr) {
            Node* del_node = now_node;
            now_node = now_node->next;
            delete del_node;
        }
    }
    delete[] hash_table;
}