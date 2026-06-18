#include "student_database.h"
#include <stdexcept>

void StudentDatabase::add_student(int student_id, int score) {
    /*  Adds a student to both StudentMap and StudentOrderedMap. */
    student_map.add_student(student_id, score);
    student_ordered_map.add_student(student_id, score);
}

void StudentDatabase::update_score(int student_id, int new_score) {
    /* Updates a student’s score in both data structures. */
    student_map.update_score(student_id, new_score);
    student_ordered_map.update_score(student_id, new_score);
}

int StudentDatabase::get_score(int student_id) const {
    /* Retrieves a student’s score from StudentMap. */
    return student_map.get_score(student_id);
}

int StudentDatabase::get_student(int score) const {
    /* Retrieves the student ID associated with the given score from StudentOrderedMap */
    return student_ordered_map.get_student(score);
}

void StudentDatabase::remove_student(int student_id) {
    /* Removes a student from both StudentMap and StudentOrderedMap */
    student_map.remove_student(student_id);
    student_ordered_map.remove_student(student_id);
}

// this returns a 2D integer array = an array of k [student_id, score] pairs.
int** StudentDatabase::get_top_k_students(int k) {
    /* Return the top k students by score in descending order. 
    Implement this method by traversing StudentOrderedMap. 
    If there are multiple students with the same score, lower student IDs get priority. 
    Fill the remaining with {-1, -1}, if there are fewer than k students. */
    int** top_k_students = new int*[k];
    for (int i = 0; i < k; ++i) {
        top_k_students[i] = new int[2]{-1, -1};
    }
    StudentOrderedMap::Node* cur = student_ordered_map.trailer;
    for (int i = 0; i < k; ++i) {
        cur = cur->prev;  // high score to low score
        if (cur == student_ordered_map.header) break;  // If there are fewer than k students
        top_k_students[i] = new int[2]{cur->student_id, cur->score};
    }
    return top_k_students;
}

int StudentDatabase::get_rank(int score) const {
    /* Return the rank of a specific score, where rank 1 is the highest score. 
    Implement this method by traversing StudentOrderedMap. 
    If there are multiple students with the same score, apply this rule:

    All identical scores receive the same rank, and the next rank number continues sequentially.
    For example, if the scores are [100, 90, 90, 80], their ranks would be [1, 2, 2, 3]. */
    int rank = 1;
    StudentOrderedMap::Node* cur = student_ordered_map.trailer;
    int cur_score = cur->score;
    while (true) {
        cur = cur->prev;

        // find
        if (cur->score == score) break;

        // Throw a runtime_error if there’s no score matched in get_rank.
        if (cur->score < score) throw std::runtime_error("Score not found");

        // If there are multiple students with the same score => same rank
        if (cur->score == cur_score) continue;

        cur_score = cur->score;
        rank++;  // If cur->score < score, rank++
    }
    return rank;
}