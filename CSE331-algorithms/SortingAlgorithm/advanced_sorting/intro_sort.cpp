/*
INTROSORT(A, p, r, depth_limit)
1 if (r - p + 1) ≤ threshold
2     use Insertion Sort on A[p..r]
3 else if depth_limit == 0
4     use Heap Sort on A[p..r]
5 else
6     q = PARTITION(A, p, r)
7     INTROSORT(A, p, q - 1, depth_limit - 1)
8     INTROSORT(A, q + 1, r, depth_limit - 1)

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
  - Worst Case:   O(n log n)

Space Complexity:
  - O(log n) auxiliary stack space
  - In-place, not stable
*/

#include <vector>
#include <algorithm>
#include <cmath>

const int INSERTION_THRESHOLD = 16;

template <typename T>
int partition(std::vector<T>& A, int p, int r) {
    T x = A[r]; // pivot
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
void insertion_sort(std::vector<T>& A, int p, int r) {
    for (int i = p + 1; i <= r; ++i) {
        T key = A[i];
        int j = i - 1;
        while (j >= p && A[j] > key) {
            A[j + 1] = A[j];
            --j;
        }
        A[j + 1] = key;
    }
}

template <typename T>
void heap_sort(std::vector<T>& A, int p, int r) {
    std::make_heap(A.begin() + p, A.begin() + r + 1);
    std::sort_heap(A.begin() + p, A.begin() + r + 1);
}

template <typename T>
void intro_sort_range(std::vector<T>& A, int p, int r, int depth_limit) {
    while (r - p > INSERTION_THRESHOLD) {
        if (depth_limit == 0) {
            heap_sort(A, p, r);
            return;
        }
        --depth_limit;
        int q = partition(A, p, r);
        intro_sort_range(A, q + 1, r, depth_limit);
        r = q - 1;
    }
    insertion_sort(A, p, r);
}

template <typename T>
void intro_sort(std::vector<T>& A) {
    int n = A.size();
    int max_depth = 2 * static_cast<int>(std::log2(n));
    intro_sort_range(A, 0, n - 1, max_depth);
}
