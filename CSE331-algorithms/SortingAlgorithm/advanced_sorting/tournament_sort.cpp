/*
TOURNAMENT-SORT(A)
1 Construct a complete binary tree T with n leaves from A
2 Each internal node stores the winner (min) of its two children
3 for i = 0 to n - 1:
4     winner = T[1]  // root
5     output winner to sorted array
6     Replace winner’s original position with INF
7     Update tree upward from that leaf

Time Complexity:
  - Best Case:    O(n log n)
  - Average Case: O(n log n)
  - Worst Case:   O(n log n)

Space Complexity:
  - O(n) auxiliary space (tree of size ~2n)
  - Not in-place, can be stable
*/

#include <vector>
#include <limits>
#include <algorithm>
#include <limits>

template <typename T>
void tournament_sort(std::vector<T>& A) {
    T SENTINEL = std::numeric_limits<T>::max();
    int n = A.size();
    int leaf_start = 1;
    while (leaf_start < n) leaf_start *= 2;
    int size = 2 * leaf_start;

    std::vector<T> tree(size, SENTINEL);

    // Step 1: Fill leaves
    for (int i = 0; i < n; ++i) {
        tree[leaf_start + i] = A[i];
    }

    // Step 2: Build tree bottom-up
    for (int i = leaf_start - 1; i > 0; --i) {
        // ⚠️ Some standard libraries do not guarantee std::min(a, b) is stable.
        // For stability: when a == b, prefer the left child (a) explicitly.
        tree[i] = std::min(tree[2 * i], tree[2 * i + 1]);
    }

    // Step 3: Extract min n times
    std::vector<T> result;
    for (int _ = 0; _ < n; ++_) {
        T winner = tree[1];
        result.push_back(winner);

        // Find winner’s position (leaf)
        int pos = 1;
        while (pos < leaf_start) {
            if (tree[2 * pos] == winner)
                pos = 2 * pos;
            else
                pos = 2 * pos + 1;
        }

        // Remove winner
        tree[pos] = SENTINEL;

        // Update to root
        while (pos > 1) {
            pos /= 2;
            // ⚠️ Some standard libraries do not guarantee std::min(a, b) is stable.
            // For stability: when a == b, prefer the left child (a) explicitly.
            tree[pos] = std::min(tree[2 * pos], tree[2 * pos + 1]);
        }
    }

    A = result;
}

