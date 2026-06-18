/*
QUICKSORT(A, p, r)
1 if p < r
2     q = PARTITION(A, p, r)
3     QUICKSORT(A, p, q - 1)
4     QUICKSORT(A, q + 1, r)

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
  - Best Case:    O(n log n)     (balanced partition)
  - Average Case: O(n log n)
  - Worst Case:   O(n^2)         (already sorted or all equal)

Space Complexity:
  - O(log n) auxiliary stack space (in-place recursion)
  - In-place, not stable
*/

#include <vector>
#include <algorithm>

template <typename T>
int partition(std::vector<T>& A, int p, int r) {
    T x = A[r];       // pivot
    int i = p - 1;
    for (int j = p; j < r; ++j) {
        if (A[j] <= x) {
            ++i;
            std::swap(A[i], A[j]);
        }
    }
    std::swap(A[i + 1], A[r]);
    return i + 1;
}

template <typename T>
void quick_sort_range(std::vector<T>& A, int p, int r) {
    if (p < r) {
        int q = partition(A, p, r);
        quick_sort_range(A, p, q - 1);
        quick_sort_range(A, q + 1, r);
    }
}

template <typename T>
void quick_sort(std::vector<T>& A) {
    quick_sort_range(A, 0, A.size() - 1);
}
