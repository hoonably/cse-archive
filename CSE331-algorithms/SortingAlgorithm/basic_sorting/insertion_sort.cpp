/*
INSERTION-SORT.A(A)
1 for j = 2 to A.length
2     key = A[j]
3     // Insert A[j] into the sorted sequence A[1 .. j-1]
4     i = j - 1
5     while i > 0 and A[i] > key
6         A[i + 1] = A[i]
7         i = i - 1
8     A[i + 1] = key

Time Complexity:
  - Best Case:    O(n)       (already sorted)
  - Average Case: O(n^2)
  - Worst Case:   O(n^2)

Space Complexity:
  - O(1) auxiliary space (in-place)
*/

#include <vector>

template <typename T>
void insertion_sort(std::vector<T>& A) {
    int n = A.size();
    for (int j = 1; j < n; ++j) {
        T key = A[j];
        int i = j - 1;
        while (i >= 0 && A[i] > key) {
            A[i + 1] = A[i];
            --i;
        }
        A[i + 1] = key;
    }
}
