//! For datasets over 10K cities, use "util2.h" instead
#include "util.h"
// #include "util2.h"

// You should put this file in the dataset/ directory
vector<string> files = {
    "weird20.tsp",
    "a280.tsp", 
    "xql662.tsp", 
    "kz9976.tsp", 
    // "mona_lisa100K.tsp"
};
bool use_2opt = true;  // 2-opt 최적화도 측정할지

vector<int> Greedy_tour() {
    vector<int> tour;
    vector<bool> visited(N + 1, false);  // 도시 방문 여부를 저장 (도시 번호는 1부터 시작)

    tour.reserve(N + 1);  // 약간의 성능 최적화를 위해 미리 공간 확보

    int cur = 1;  // 시작 도시는 1번으로 고정
    tour.push_back(cur);
    visited[cur] = true;

    // 남은 n-1개의 도시를 순회
    for (int step = 1; step < N; ++step) {
        int next = -1;
        int bestCost = INF;

        // 현재 도시에서 방문하지 않은 도시 중 가장 가까운 도시를 선택
        for (int j = 1; j <= N; ++j) {
            if (!visited[j]) {
                int d = get_dist(cur, j);
                if (d < bestCost) {
                    bestCost = d;
                    next = j;
                }
            }
        }

        // 가장 가까운 도시로 이동
        visited[next] = true;
        tour.push_back(next);
        cur = next;
    }

    // 시작 도시로 돌아오는 edge 추가
    tour.push_back(tour.front());

    return tour;
}



int main() {
    run("Greedy", Greedy_tour, files, use_2opt);
    return 0;
}
