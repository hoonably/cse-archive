/*
COCKTAIL-SHAKER-SORT(A)
1 Initialize left = 0, right = A.length - 1
2 repeat
3     swapped = false
4     Forward pass: compare A[i] and A[i+1] from left to right - 1
5     If any swap occurs, mark swapped = true
6     Decrease right
7     Backward pass: compare A[i] and A[i-1] from right downto left + 1
8     If any swap occurs, mark swapped = true
9     Increase left
10 Until no swaps occur

Time Complexity:
  - Best Case:    O(n)
  - Average Case: O(n^2)
  - Worst Case:   O(n^2)

Space Complexity:
  - O(1) auxiliary space (in-place)
  - Stable
*/

#include <vector>
#include <algorithm>

template <typename T>
void cocktail_shaker_sort(std::vector<T>& A) {
    int n = A.size();
    bool swapped = true;
    int left = 0, right = n - 1;

    while (swapped) {
        swapped = false;

        // Forward pass
        for (int i = left; i < right; ++i) {
            if (A[i] > A[i + 1]) {
                std::swap(A[i], A[i + 1]);
                swapped = true;
            }
        }
        --right;

        // Backward pass
        for (int i = right; i > left; --i) {
            if (A[i] < A[i - 1]) {
                std::swap(A[i], A[i - 1]);
                swapped = true;
            }
        }
        ++left;
    }
}
