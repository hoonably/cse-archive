/*
SELECTION-SORT(A)
1 for i = 1 to A.length - 1
2     min_index = i
3     for j = i + 1 to A.length
4         if A[j] < A[min_index]
5             min_index = j
6     exchange A[i] with A[min_index]

Time Complexity:
  - Best Case:    O(n^2)
  - Average Case: O(n^2)
  - Worst Case:   O(n^2)

Space Complexity:
  - O(1) auxiliary space (in-place)
  - Not stable
*/

#include <vector>
#include <algorithm>

template <typename T>
void selection_sort(std::vector<T>& A) {
    int n = A.size();
    for (int i = 0; i < n - 1; ++i) {
        int min_index = i;
        for (int j = i + 1; j < n; ++j) {
            if (A[j] < A[min_index])
                min_index = j;
        }
        std::swap(A[i], A[min_index]);
    }
}
