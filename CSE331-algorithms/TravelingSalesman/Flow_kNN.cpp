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

#include "MCMF.h"

#define K 20  // K-Nearest Neighbors 수

// Get K-Nearest Neighbors for each city
vector<vector<int>> get_kNN(int k) {
    vector<vector<int>> kNN(N + 1);
    for (int i = 1; i <= N; ++i) {
        vector<pair<int, int>> distances; // {distance, city}
        for (int j = 1; j <= N; ++j) {
            if (i != j) {
                distances.push_back({get_dist(i,j), j});
            }
        }
        sort(distances.begin(), distances.end());
        for (int j = 0; j < min(k, N-1); ++j) {
            kNN[i].push_back(distances[j].second);
        }
    }
    return kNN;
}

// MCMF tour construction using kNN
vector<int> Flow_kNN_tour() {

    vector<vector<int>> kNN = get_kNN(min(K,N-1));

    MCMF mcmf;
    mcmf.init(N);
    for (int i = 1; i <= N; ++i) {
        mcmf.addEdge(mcmf.SRC, i, 1, 0);
        mcmf.addEdge(i + mcmf.bias, mcmf.SINK, 1, 0);
        for (int j : kNN[i]) {
            mcmf.addEdge(i, j + mcmf.bias, 1, get_dist(i,j));
        }
    }
    mcmf.run();

    // 결과로 얻은 flow에서 실제 연결 정보 추출
    vector<vector<int>> adj(N + 1);  // adj[u] = [v]
    for (int u = 1; u <= N; ++u) {
        for (const auto& e : mcmf.graph[u]) {
            if (e.cap == 0 && mcmf.bias + 1 <= e.to && e.to <= mcmf.bias + N) {
                int v = e.to - mcmf.bias;
                adj[u].push_back(v);
            }
        }
    }

    // flow 기반 edge로부터 subtour들 구성
    vector<vector<int>> subtours;
    vector<bool> visited(N + 1, false);
    for (int i = 1; i <= N; ++i) {
        if (!visited[i]) {
            vector<int> path;
            int cur = i;
            while (!visited[cur] && !adj[cur].empty()) {
                visited[cur] = true;
                path.push_back(cur);
                cur = adj[cur][0];
            }
            if (!path.empty()) subtours.push_back(path);
        }
    }

    // 여러 개의 subtour를 단일 경로로 병합
    while (subtours.size() > 1) {
        int best_i = -1, best_j = -1, best_cost = INF;
        for (int i = 0; i < subtours.size(); ++i) {
            for (int j = 0; j < subtours.size(); ++j) {
                if (i == j) continue;
                int tail = subtours[i].back();
                int head = subtours[j].front();
                int cost = get_dist(tail, head);
                if (cost < best_cost) {
                    best_cost = cost;
                    best_i = i;
                    best_j = j;
                }
            }
        }
        // 가장 가까운 subtour 두 개를 병합
        vector<int>& from = subtours[best_i];
        vector<int>& to = subtours[best_j];
        from.insert(from.end(), to.begin(), to.end());
        subtours.erase(subtours.begin() + best_j);
    }

    // 최종 투어 반환 (시작점으로 복귀)
    vector<int>& tour = subtours[0];
    tour.push_back(tour.front());
    return tour;
}


int main() {
    run("Flow_kNN", Flow_kNN_tour, files, use_2opt);
    return 0;
}
