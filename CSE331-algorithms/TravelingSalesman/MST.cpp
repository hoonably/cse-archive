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

// Prim 알고리즘을 이용해 MST 생성
vector<vector<int>> primMST() {
    vector<int> key(N + 1, INF);         // 최소 비용 저장
    vector<int> parent(N + 1, -1);       // MST에서의 부모 정점
    vector<bool> inMST(N + 1, false);    // MST 포함 여부

    key[1] = 0; // 1번 도시를 시작점으로 고정
    for (int count = 1; count <= N - 1; ++count) {
        int u = -1;
        // MST에 포함되지 않은 정점 중 최소 key 값을 가지는 정점 선택
        for (int v = 1; v <= N; ++v)
            if (!inMST[v] && (u == -1 || key[v] < key[u]))
                u = v;

        inMST[u] = true;
        // u와 연결된 정점들에 대해 key 갱신
        for (int v = 1; v <= N; ++v) {
            if (!inMST[v]) {
                int d = get_dist(u, v);
                if (d < key[v]) {
                    key[v] = d;
                    parent[v] = u;
                }
            }
        }
    }

    // MST를 인접 리스트 형식으로 저장
    vector<vector<int>> adj(N + 1);
    for (int v = 2; v <= N; ++v) {
        int u = parent[v];
        adj[u].push_back(v);
        adj[v].push_back(u);
    }
    return adj;
}

// DFS 순회를 통해 Euler tour 생성
void dfs(int u, const vector<vector<int>>& adj, vector<bool>& visited, vector<int>& tour) {
    visited[u] = true;
    tour.push_back(u);
    for (int v : adj[u])
        if (!visited[v])
            dfs(v, adj, visited, tour);
}

// MST 기반 2-근사 TSP 해 찾기
vector<int> MST_tour() {
    vector<vector<int>> adj = primMST();            // MST 구성
    vector<int> tour;
    vector<bool> visited(N + 1, false);
    dfs(1, adj, visited, tour);                     // DFS 기반 Euler tour 생성
    tour.push_back(tour.front());                   // 시작점으로 복귀
    return tour;
}

int main() {
    run("MST", MST_tour, files, use_2opt);
    return 0;
}
