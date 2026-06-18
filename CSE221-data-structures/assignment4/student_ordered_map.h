#ifndef STUDENT_ORDERED_MAP_H
#define STUDENT_ORDERED_MAP_H

class StudentOrderedMap { // do not change this line
public:
    struct Node { // do not change this line
        int student_id; // do not change this line
        int score; // do not change this line

        /* add whatever you want */
        Node* prev;
        Node* next;
        Node* below;
        Node* above;

        bool operator < (const Node& other) const;

        Node() : prev(nullptr), next(nullptr), below(nullptr), above(nullptr) {}
        Node(int _student_id, int _score) : student_id(_student_id), score(_score),
            prev(nullptr), next(nullptr), below(nullptr), above(nullptr) {}
    };

    StudentOrderedMap();
    
    void add_student(int student_id, int score);

    void update_score(int student_id, int new_score);

    int get_student(int score) const;

    void remove_student(int student_id);

    ~StudentOrderedMap();

    /* add whatever you want*/
    void print_all();  // for debugging
private:
    int height;
    Node* header;  // S0 header
    Node* trailer;  // S0 trailer
    friend class StudentDatabase;

    int flipping_coins();
    Node* get_k_level_header(int k) const;
    void make_height(int new_height);
};

#endif