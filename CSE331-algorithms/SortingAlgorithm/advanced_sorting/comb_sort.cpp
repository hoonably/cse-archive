/*
COMB-SORT(A)
1 gap = A.length
2 shrink = 1.3
3 sorted = false
4 while not sorted:
5     gap = floor(gap / shrink)
6     if gap ≤ 1:
7         gap = 1
8         sorted = true
9     for i = 0 to A.length - gap - 1:
10        if A[i] > A[i + gap]
11            exchange A[i] with A[i + gap]
12            sorted = false

Time Complexity:
  - Best Case:    O(n)         (already sorted)
  - Average Case: O(n log n)
  - Worst Case:   O(n^2)

Space Complexity:
  - O(1) auxiliary space (in-place)
  - Not stable
*/

#include <vector>
#include <algorithm>
#include <cmath>

template <typename T>
void comb_sort(std::vector<T>& A) {
    int n = A.size();
    double shrink = 1.3;
    int gap = n;
    bool sorted = false;

    while (!sorted) {
        gap = static_cast<int>(std::floor(gap / shrink));
        if (gap <= 1) {
            gap = 1;
            sorted = true;
        }

        for (int i = 0; i + gap < n; ++i) {
            if (A[i] > A[i + gap]) {
                std::swap(A[i], A[i + gap]);
                sorted = false;
            }
        }
    }
}
