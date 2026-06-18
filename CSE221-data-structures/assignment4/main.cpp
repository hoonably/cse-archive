#include "student_database.h"
#include <iostream>
#include <exception>

// Function to print the top k students by score
void print_top_k_students(int** top_students, int k) {
    std::cout << "Top " << k << " students by score:" << std::endl;
    for (int i = 0; i < k; i++) {
        if (top_students[i][0] != -1) {
            std::cout << "Student ID: " << top_students[i][0] << ", Score: " << top_students[i][1] << std::endl;
        } else {
            std::cout << "No student data available for rank " << i + 1 << "." << std::endl;
        }
    }
}

// Test function for StudentMap
void test_student_map() {
    StudentMap map;
    int id1 = 20241234;
    int id2 = 20244321;

    map.add_student(id1, 95);
    map.add_student(id2, 88);

    std::cout << "Testing StudentMap:" << std::endl;
    try {
        std::cout << "Score of " << id1 << ": " << map.get_score(id1) << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
    }

    map.update_score(id1, 98);
    try {
        std::cout << "Updated Score of " << id1 << ": " << map.get_score(id1) << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
    }

    map.remove_student(id2);
    try {
        map.get_score(id2);
    } catch (const std::exception& e) {
        std::cerr << "Expected exception: " << e.what() << std::endl;
    }
}

// Test function for StudentOrderedMap

void test_student_ordered_map() {
    StudentOrderedMap ordered_map;
    int id1 = 20241234;
    int id2 = 20244321;
    int id3 = 20245678;
    int id4 = 20246666;

    ordered_map.add_student(id1, 95);
    ordered_map.add_student(id2, 88);
    ordered_map.add_student(id3, 97);
    ordered_map.add_student(id4, 88);

    std::cout << "\nTesting StudentOrderedMap:" << std::endl;
    try {
        std::cout << "Student with score 88: ID " << ordered_map.get_student(88) << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
    }
    
    ordered_map.update_score(id1, 99);
    try {
        std::cout << "Updated ID " << id1 << " to score 99" << std::endl;
        std::cout << "Student with score 99: ID " << ordered_map.get_student(99) << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
    }

    ordered_map.remove_student(id2);
    try {
        int student_id = ordered_map.get_student(88);
        std::cout << "Student with score 88 after removal: ID " << student_id << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Expected exception: " << e.what() << std::endl;
    }
}
void test_student_database() {
    StudentDatabase db;

    int id1 = 20241234; // Student with initial score 95, updated to 99
    int id2 = 20244321; // Student with score 88
    int id3 = 20245678; // Student with score 97
    int id4 = 20249999; // Student with score 90
    int id5 = 20241111; // Student with score 90
    int id6 = 20242222; // Student with score 90

    // Adding students
    db.add_student(id1, 95);
    db.add_student(id2, 88);
    db.add_student(id3, 97);
    db.add_student(id4, 90);
    db.add_student(id5, 90); // Duplicate score with id4
    db.add_student(id6, 90); // Duplicate score with id4 and id5

    std::cout << "\nTesting StudentDatabase:\n" << std::endl;

    // Test get_score
    try {
        std::cout << "Score of " << id1 << ": " << db.get_score(id1) << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
    }

    // Test update_score
    db.update_score(id1, 99);
    try {
        std::cout << "Updated Score of " << id1 << ": " << db.get_score(id1) << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
    }

    // Test get_top_k_students with k = 5
    int k = 5;
    int** top_students = db.get_top_k_students(k);
    print_top_k_students(top_students, k);

    // Free the allocated memory
    for (int i = 0; i < k; ++i) {
        delete[] top_students[i];
    }
    delete[] top_students;

    // Test get_rank for score 90
    try {
        int score_rank = db.get_rank(90);
        std::cout << "\nRank of score 90: " << score_rank << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
    }

    // Test get_rank for score 88
    try {
        int score_rank = db.get_rank(88);
        std::cout << "Rank of score 88: " << score_rank << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
    }

    // Test get_rank for score not in the database
    try {
        int score_rank = db.get_rank(85);
        std::cout << "Rank of score 85: " << score_rank << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Expected exception: " << e.what() << std::endl;
    }

    // Remove a student and test get_top_k_students again
    db.remove_student(id3); // Remove student with score 97
    k = 5;
    top_students = db.get_top_k_students(k);
    std::cout << "\nAfter removing student ID " << id3 << ":" << std::endl;
    print_top_k_students(top_students, k);

    // Free the allocated memory
    for (int i = 0; i < k; ++i) {
        delete[] top_students[i];
    }
    delete[] top_students;

    // Test get_rank after removal
    try {
        int score_rank = db.get_rank(97);
        std::cout << "Rank of score 97: " << score_rank << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Expected exception: " << e.what() << std::endl;
    }

    // Test get_rank for updated score
    try {
        int score_rank = db.get_rank(99);
        std::cout << "Rank of score 99: " << score_rank << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
    }
}

int main() {
    std::cout << "Starting tests..." << std::endl;

    // test_student_map();
    test_student_ordered_map();
    // test_student_database();

    std::cout << "Tests completed." << std::endl;

    return 0;
}