#ifndef STUDENT_DATABASE_H
#define STUDENT_DATABASE_H

#include "student_map.h"
#include "student_ordered_map.h"

class StudentDatabase {// do not change this line

public:
    void add_student(int student_id, int score); // do not change this line

    void update_score(int student_id, int new_score); // do not change this line

    int get_score(int student_id) const; // do not change this line

    int get_student(int score) const; // do not change this line

    void remove_student(int student_id); // do not change this line

    // this returns a 2D integer array = an array of k [student_id, score] pairs.
    int** get_top_k_students(int k); // do not change this line

    int get_rank(int score) const; // do not change this line

    /* add whatever you want*/
private:
    StudentMap student_map;
    StudentOrderedMap student_ordered_map;
};

#endif