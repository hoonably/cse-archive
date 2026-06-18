/*
TIMSORT.A(A)
1 Partition the array into runs of size RUN
2 Apply insertion sort to each run
3 Iteratively merge runs in bottom-up fashion

Time Complexity:
  - Best Case:    O(n)
  - Average Case: O(n log n)
  - Worst Case:   O(n log n)

Space Complexity:
  - O(n) auxiliary space (due to merging)
*/

#include <vector>
#include <algorithm>

const int RUN = 32;

template <typename T>
void insertion_sort(std::vector<T>& A, int left, int right) {
    for (int i = left + 1; i <= right; ++i) {
        T key = A[i];
        int j = i - 1;
        while (j >= left && A[j] > key) {
            A[j + 1] = A[j];
            --j;
        }
        A[j + 1] = key;
    }
}

template <typename T>
void merge(std::vector<T>& A, int left, int mid, int right) {
    std::vector<T> L(A.begin() + left, A.begin() + mid + 1);
    std::vector<T> R(A.begin() + mid + 1, A.begin() + right + 1);

    int i = 0, j = 0, k = left;
    while (i < (int)L.size() && j < (int)R.size()) {
        if (L[i] <= R[j])
            A[k++] = L[i++];
        else
            A[k++] = R[j++];
    }
    while (i < (int)L.size())
        A[k++] = L[i++];
    while (j < (int)R.size())
        A[k++] = R[j++];
}

template <typename T>
void tim_sort(std::vector<T>& A) {
    int n = A.size();

    // Step 1: Sort small runs with Insertion Sort
    for (int i = 0; i < n; i += RUN) {
        insertion_sort(A, i, std::min(i + RUN - 1, n - 1));
    }

    // Step 2: Merge runs iteratively
    for (int size = RUN; size < n; size *= 2) {
        for (int left = 0; left < n; left += 2 * size) {
            int mid = std::min(left + size - 1, n - 1);
            int right = std::min(left + 2 * size - 1, n - 1);

            if (mid < right)
                merge(A, left, mid, right);
        }
    }
}
