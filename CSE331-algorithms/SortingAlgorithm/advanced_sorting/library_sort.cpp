/*
Faujdar Style Library Sort

LIBRARY-SORT(A, ε)
1   Let n = length(A)
2   Allocate array S[ (1 + ε) * n ] and set all entries to GAP (sentinel)
3   Mark all positions in S as empty
4   Insert A[0] at center of S
5   Initialize inserted = 1, round = 0

6   For i = 1 to n - 1:
7       If inserted == 2^round:
8           Rebalance S (spread existing elements evenly with gaps)
9           round ← round + 1

10      Binary search on occupied cells in S to find logical position for A[i]
11      Let pos = suggested insert position
12      While S[pos] is occupied:
13          pos ← pos + 1   // shift right until a gap is found

14      Shift elements right if needed to create gap at pos
15      Insert A[i] at S[pos]
16      Mark S[pos] as occupied
17      inserted ← inserted + 1

18  Extract sorted result from S (skip GAPs)

Time Complexity:
  - Average Case: O(n log n)
  - Worst Case:   O(n^2) (if shifting dominates)
Space Complexity:
  - O((1 + ε)n)
*/


#include <vector>
#include <cmath>
#include <limits>
#include <algorithm>

// Modified binary search with gap-aware logic
template <typename T>
int gap_binary_search(const std::vector<T>& S, const std::vector<bool>& occupied, int low, int high, T key) {
    T SENTINEL = std::numeric_limits<T>::max();
    while (low <= high) {
        int mid = (low + high) / 2;

        if (!occupied[mid]) {
            // GAP handling: Finding the closest valid values from left to right
            int m1 = mid, m2 = mid;
            while (m1 >= low && !occupied[m1]) m1--;
            while (m2 <= high && !occupied[m2]) m2++;

            T left = (m1 >= low) ? S[m1] : SENTINEL;
            T right = (m2 <= high) ? S[m2] : SENTINEL;

            if (key < left) {
                high = m1 - 1;
            } else if (key > right) {
                low = m2 + 1;
            } else {
                low = m1 + 1;
                high = m2 - 1;
            }
        } else {
            if (S[mid] < key) {
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }
    }
    return low;
}

// rebalance: Redistribute GAPs to make room for insertion
template <typename T>
void rebalance(std::vector<T>& S, std::vector<bool>& occupied, int size, double epsilon) {
    T SENTINEL = std::numeric_limits<T>::max();
    int new_size = static_cast<int>((1.0 + epsilon) * size) + 1;
    std::vector<T> new_S(new_size, SENTINEL);
    std::vector<bool> new_occ(new_size, false);

    int gap = new_size / size;
    int idx = gap / 2;

    for (int i = 0; i < S.size(); ++i) {
        if (occupied[i]) {
            new_S[idx] = S[i];
            new_occ[idx] = true;
            idx += gap;
        }
    }

    S = std::move(new_S);
    occupied = std::move(new_occ);
}

template <typename T>
void library_sort(std::vector<T>& A, double epsilon = 1.0) {
    T SENTINEL = std::numeric_limits<T>::max();
    int n = A.size();
    int cap = static_cast<int>((1.0 + epsilon) * n) + 1;

    std::vector<T> S(cap, SENTINEL);
    std::vector<bool> occupied(cap, false);

    int inserted = 0;
    int round = 0;

    for (int i = 0; i < n; ++i) {
        if (inserted > 0 && (inserted & (inserted - 1)) == 0) {  // rebalance every 2^i
            rebalance(S, occupied, inserted, epsilon);
            cap = S.size();  // Update
        }

        int pos = gap_binary_search(S, occupied, 0, cap - 1, A[i]);

        // Shift to the right to get a GAP
        int insert_pos = pos;
        while (insert_pos < cap && occupied[insert_pos]) insert_pos++;
        if (insert_pos >= cap) {
            rebalance(S, occupied, inserted, epsilon);
            cap = S.size();
            i--;  // Retry current A[i]
            continue;
        }

        for (int j = insert_pos; j > pos; --j) {
            S[j] = S[j - 1];
            occupied[j] = occupied[j - 1];
        }

        S[pos] = A[i];
        occupied[pos] = true;
        inserted++;
    }

    // Copy the sorted results
    A.clear();
    for (int i = 0; i < cap; ++i) {
        if (occupied[i]) A.push_back(S[i]);
    }
}
