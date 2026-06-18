/*
BUBBLESORT(A)
1 for i = 1 to A.length - 1
2     for j = A.length downto i + 1
3         if A[j] < A[j - 1]
4             exchange A[j] with A[j - 1]

Time Complexity:
  - Best Case:    O(n)       (already sorted, no swaps needed)
  - Average Case: O(n^2)
  - Worst Case:   O(n^2)

Space Complexity:
  - O(1) auxiliary space (in-place)
*/

#include <vector>

template <typename T>
void bubble_sort(std::vector<T>& A) {
    int n = A.size();
    for (int i = 0; i < n - 1; ++i) {
        for (int j = n - 1; j > i; --j) {
            if (A[j] < A[j - 1]) {
                std::swap(A[j], A[j - 1]);
            }
        }
    }
}
