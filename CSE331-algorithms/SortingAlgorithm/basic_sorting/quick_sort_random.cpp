/*
RANDOMIZED-QUICKSORT(A, p, r)
1 if p < r
2     pivot_index = RANDOM(p, r)
3     exchange A[pivot_index] with A[r]
4     q = PARTITION(A, p, r)
5     RANDOMIZED-QUICKSORT(A, p, q - 1)
6     RANDOMIZED-QUICKSORT(A, q + 1, r)

PARTITION(A, p, r)
1 x = A[r]
2 i = p - 1
3 for j = p to r - 1
4     if A[j] ≤ x
5         i = i + 1
6         exchange A[i] with A[j]
7 exchange A[i + 1] with A[r]
8 return i + 1

Time Complexity:
  - Best Case:    O(n log n)
  - Average Case: O(n log n)
  - Worst Case:   O(n log n) with high probability

Space Complexity:
  - O(log n) auxiliary stack space (in-place recursion)
  - In-place, not stable
*/

#include <vector>
#include <algorithm>
#include <cstdlib>
#include <ctime>

template <typename T>
int partition_random(std::vector<T>& A, int p, int r) {
    int pivot_index = p + rand() % (r - p + 1);  // RANDOM(p, r)
    std::swap(A[pivot_index], A[r]);            // exchange A[pivot_index] with A[r]
    T x = A[r];                                // pivot value
    int i = p - 1;
    for (int j = p; j < r; ++j) {                // for j = p to r - 1
        if (A[j] <= x) {
            ++i;
            std::swap(A[i], A[j]);               // exchange A[i] with A[j]
        }
    }
    std::swap(A[i + 1], A[r]);                   // exchange A[i + 1] with A[r]
    return i + 1;
}

template <typename T>
void quick_sort_random_range(std::vector<T>& A, int p, int r) {
    if (p < r) {
        int q = partition_random(A, p, r);
        quick_sort_random_range(A, p, q - 1);
        quick_sort_random_range(A, q + 1, r);
    }
}

template <typename T>
void quick_sort_random(std::vector<T>& A) {
    std::srand(std::time(nullptr));  // initialize random seed
    quick_sort_random_range(A, 0, A.size() - 1);
}
