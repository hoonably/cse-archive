/*
HEAPSORT(A)
1 BUILD-MAX-HEAP(A)
2 for i = A.length downto 2
3     exchange A[1] with A[i]
4     A.heap-size = A.heap-size - 1
5     MAX-HEAPIFY(A, 1)

MAX-HEAPIFY(A, i)
1 l = LEFT(i)
2 r = RIGHT(i)
3 if l ≤ A.heap-size and A[l] > A[i]
4     largest = l
5 else largest = i
6 if r ≤ A.heap-size and A[r] > A[largest]
7     largest = r
8 if largest ≠ i
9     exchange A[i] with A[largest]
10    MAX-HEAPIFY(A, largest)

BUILD-MAX-HEAP(A)
1 A.heap-size = A.length
2 for i = A.length/2 downto 1
3     MAX-HEAPIFY(A, i)

Time Complexity:
  - Best Case:    O(n log n)
  - Average Case: O(n log n)
  - Worst Case:   O(n log n)

Space Complexity:
  - O(1) auxiliary space (in-place)
*/

#include <vector>
#include <algorithm>

int LEFT(int i) { return 2 * i + 1; }

int RIGHT(int i) { return 2 * i + 2; }

template <typename T>
void max_heapify(std::vector<T>& A, int heap_size, int i) {
    int l = LEFT(i);
    int r = RIGHT(i);
    int largest = i;

    if (l < heap_size && A[l] > A[largest])
        largest = l;
    if (r < heap_size && A[r] > A[largest])
        largest = r;

    if (largest != i) {
        std::swap(A[i], A[largest]);
        max_heapify(A, heap_size, largest);
    }
}

template <typename T>
void build_max_heap(std::vector<T>& A) {
    int heap_size = A.size();
    for (int i = heap_size / 2 - 1; i >= 0; --i)
        max_heapify<T>(A, heap_size, i);
}

template <typename T>
void heap_sort(std::vector<T>& A) {
    int heap_size = A.size();
    build_max_heap(A);
    for (int i = heap_size - 1; i > 0; --i) {
        std::swap(A[0], A[i]);
        --heap_size;
        max_heapify(A, heap_size, 0);
    }
}
