#ifndef STUDENT_MAP_H
#define STUDENT_MAP_H

class StudentMap { // do not change this line
public:
    struct Node // do not change this line
    {
        int student_id; // do not change this line
        int score; // do not change this line

        /* add whatever you want */
        Node* next;  // For using separate chaining
        Node() : student_id(-1), score(-1), next(nullptr) {}  // For initializing hash_table
        Node(int _student_id, int _score)  : student_id(_student_id), score(_score), next(nullptr) {}
    };

    static const int TABLE_SIZE = 1000; // do not change this line

    StudentMap();

    void add_student(int student_id, int score); // do not change this line

    void update_score(int student_id, int new_score); // do not change this line

    int get_score(int student_id) const;  // do not change this line

    void remove_student(int student_id);  // do not change this line
    
    ~StudentMap();

    /* add whatever you want */
private:
    Node** hash_table;
    int get_hash(int student_id) const;
};

#endif