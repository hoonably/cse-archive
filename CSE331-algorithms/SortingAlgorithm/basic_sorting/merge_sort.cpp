/*
MERGE-SORT(A, p, r)
1 if p < r
2     q = floor((p + r) / 2)
3     MERGE-SORT(A, p, q)
4     MERGE-SORT(A, q + 1, r)
5     MERGE(A, p, q, r)

MERGE(A, p, q, r)
1 n1 = q - p + 1
2 n2 = r - q
3 let L[1..n1 + 1] and R[1..n2 + 1] be new arrays
4 for i = 1 to n1
5     L[i] = A[p + i - 1]
6 for j = 1 to n2
7     R[j] = A[q + j]
8 L[n1 + 1] = ∞
9 R[n2 + 1] = ∞
10 i = 1
11 j = 1
12 for k = p to r
13     if L[i] ≤ R[j]
14         A[k] = L[i]
15         i = i + 1
16     else A[k] = R[j]
17         j = j + 1

Time Complexity:
  - Best Case:    O(n log n)
  - Average Case: O(n log n)
  - Worst Case:   O(n log n)

Space Complexity:
  - O(n) extra space (not in-place)
*/

#include <vector>
#include <limits>

template <typename T>
void merge(std::vector<T>& A, int p, int q, int r) {
    T SENTINEL = std::numeric_limits<T>::max();
    int n1 = q - p + 1;
    int n2 = r - q;
    std::vector<T> L(n1 + 1);
    std::vector<T> R(n2 + 1);

    for (int i = 0; i < n1; ++i)
        L[i] = A[p + i];
    for (int j = 0; j < n2; ++j)
        R[j] = A[q + 1 + j];

    L[n1] = SENTINEL;
    R[n2] = SENTINEL;

    int i = 0, j = 0;
    for (int k = p; k <= r; ++k) {
        if (L[i] <= R[j])
            A[k] = L[i++];
        else
            A[k] = R[j++];
    }
}

template <typename T>
void merge_sort_range(std::vector<T>& A, int p, int r) {
    if (p < r) {
        int q = (p + r) / 2;
        merge_sort_range(A, p, q);
        merge_sort_range(A, q + 1, r);
        merge(A, p, q, r);
    }
}

// If you want to sort the entire array, you can call this function
template <typename T>
void merge_sort(std::vector<T>& A) {
    merge_sort_range(A, 0, A.size() - 1);
}