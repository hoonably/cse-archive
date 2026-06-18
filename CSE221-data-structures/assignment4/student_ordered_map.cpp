#include "student_ordered_map.h"

#include <cstdlib>  // for use std::rand()
#include <stdexcept>

#define PLUS_INF 101
#define MINUS_INF -1

bool StudentOrderedMap::Node::operator<(const Node& other) const {
    // Sort student_id by greater if score is equal
    if(score==other.score) return student_id < other.student_id;
    return score > other.score;
}

StudentOrderedMap::StudentOrderedMap() {
    height = 0;
    header = new Node(-1, MINUS_INF);
    trailer = new Node(-1, PLUS_INF);

    header->next = trailer;
    trailer->prev = header;
}

void StudentOrderedMap::add_student(int student_id, int score){

    if (score<0 || score>100) throw std::runtime_error("Invalid score");

    // Check if there is already added O(n)
    Node* cur_node = header;
    while(cur_node != nullptr){
        if(cur_node->student_id == student_id){
            throw std::runtime_error("Already existing student ID");
        }
        cur_node = cur_node->next;
    }

    /* Adds a student in sorted order by score. */
    int i = flipping_coins();

    // Increase the height until height = i+1
    if (i >= height) make_height(i+1);

    // Start search at level i
    cur_node = get_k_level_header(i);
    Node* last_new_node = nullptr;

    while(true){
        // Proceed to right (if the scores are the same, the smaller class number goes last)
        if(cur_node->next->score < score ||
            (cur_node->next->score == score && student_id < cur_node->next->student_id)){
            cur_node = cur_node->next;
        }
        else {
            // Insert
            Node* new_node = new Node(student_id, score);
            new_node->prev = cur_node;
            new_node->next = cur_node->next;
            cur_node->next->prev = new_node;
            cur_node->next = new_node;

            new_node->above = last_new_node;
            if (last_new_node!=nullptr) last_new_node->below = new_node;
            last_new_node = new_node;
            
            if(cur_node->below == nullptr) break;  // If it's the bottom level, break
            else cur_node = cur_node->below;  // Go down
        }
    }
}

void StudentOrderedMap::update_score(int student_id, int new_score) {
    /* Updates the score and maintains the sorted order. */
    remove_student(student_id);
    add_student(student_id, new_score);
}

int StudentOrderedMap::get_student(int score) const {
    /* Retrieves the student ID associated with the given score. 
    If there are multiple matches, it returns the lowest student ID.*/

    if (score<0 || score>100) throw std::runtime_error("Invalid score");
    
    // start search at level h
    Node *cur_node = get_k_level_header(height);
    while(true){
        // x >= y: scan forward
        // If they are the same score, they are in descending order of class year. 
        // Proceed until a different score is found
        if(score >= cur_node->next->score){
            cur_node = cur_node->next;
        }

        // Match current score, score < cur_node->next->score
        else if(score == cur_node->score) {
            return cur_node->student_id;
        }

        // x < y: drop down
        else {
            // not found
            if(cur_node->below == nullptr) {
                throw std::runtime_error("Score not found");
            }
            cur_node = cur_node->below;
        }
    }
    return -1;
}

/*
Removes a student and score by student ID.
Originally, it would be O(logn) to find score from the top to bottom,
but this is O(n) because we find student_id at the bottom level
*/
void StudentOrderedMap::remove_student(int student_id) {
    Node* cur_node = header;
    while(cur_node != nullptr){
        if(cur_node->student_id == student_id){
            while(cur_node != nullptr){
                Node* next_node = cur_node->above;
                cur_node->prev->next = cur_node->next;
                cur_node->next->prev = cur_node->prev;
                delete cur_node;
                cur_node = next_node;
            }
            // remove all but one list containing only the two special keys
            for(int h=height; h>=1; h--){
                Node* head = get_k_level_header(h);
                Node* tail = head->next;
                if (head->below->next == tail->below){  // h-1 level only the two special keys
                    head->below->above = head->above;
                    tail->below->above = tail->above;
                    delete head;  // delete h level head
                    delete tail;  // delete h level tail
                    height--;
                }
                else break;
            }
            return;  // Deletion complete
        }
        cur_node = cur_node->next;
    }
    throw std::runtime_error("Student ID not found");
}

StudentOrderedMap::~StudentOrderedMap() {
    for(int h=height; h>=0; h--){
        Node* cur = get_k_level_header(h);
        while(cur != nullptr){
            Node* next = cur->next;
            delete cur;
            cur = next;
        }
    }
}

int StudentOrderedMap::flipping_coins(){  // flipping coins
    int i = 0;
    while(rand()%2) i++;  // +1 on odd numbers, end on even numbers
    // cout << "random i: " << i << '\n';
    return i;
}

StudentOrderedMap::Node* StudentOrderedMap::get_k_level_header(int k) const{
    if (k > height) throw std::runtime_error("Invalid height");
    Node* cur_header = header;
    for(int i = 0; i < k; i++){
        cur_header = cur_header->above;
    }
    return cur_header;
}


void StudentOrderedMap::make_height(int new_height){
    Node* cur_header = header;
    Node* cur_trailer = trailer;

    // Go up to the height level
    for(int i=0; i<height; i++){
        cur_header = cur_header->above;
        cur_trailer = cur_trailer->above;
    }
    // Increase height to new_h
    while (height < new_height) {
        Node* new_header = new Node(-1, MINUS_INF);
        Node* new_trailer = new Node(-1, PLUS_INF);

        new_header->below = cur_header;
        new_trailer->below = cur_trailer;

        new_header->next = new_trailer;
        new_trailer->prev = new_header;

        cur_header->above = new_header;
        cur_trailer->above = new_trailer;

        cur_header = new_header;
        cur_trailer = new_trailer;
        height++;
    }
}

// for debugging
#include <iostream>
void StudentOrderedMap::print_all(){
    if (height == 0){
        std::cout << "Empty ordered map\n\n";
        return;
    }
    for(int h=height; h>=0; h--){
        Node* cur = get_k_level_header(h)->next;
        std::cout << "Level " << h << ": ";
        while(cur->next != nullptr){
            std::cout << cur->score << " ";
            cur = cur->next;
        }
        std::cout << '\n';
    }
    std::cout << '\n';
}