#include "util.h"
#include <set>
#include <map>

//! This algorithm is O(n^2 * 2^n), so it can handle up to 20 cities.
// You should put this file in the dataset/ directory
vector<string> files = {
    "weird20.tsp",
};
bool use_2opt = false;  // 2-opt 최적화도 측정할지 (의미 없음)

#define START 1  // 시작 도시 (1번 도시로 고정)

void dfs_combinations(int depth, int start, int sz, int n, vector<int>& comb, vector<set<int>>& subsets) {
    if (depth == sz) {
        set<int> s(comb.begin(), comb.end());
        if (s.count(START)) subsets.push_back(s);  // START 포함 조합만 사용
        return;
    }
    for (int i = start; i <= n; ++i) {
        comb[depth] = i;
        dfs_combinations(depth + 1, i + 1, sz, n, comb, subsets);
    }
}

void generate_combinations(int sz, int n, vector<set<int>>& subsets) {
    vector<int> comb(sz);
    dfs_combinations(0, 1, sz, n, comb, subsets);
}

using State = pair<set<int>, int>;  // (지나온 도시 집합, 마지막 도시)

vector<int> HeldKarp_tour() {
    map<State, int> dp;       // 최소 비용 저장
    map<State, int> parent;   // 경로 추적용 부모 도시

    // 초기 상태: START → i
    for (int i = 1; i <= N; ++i) {
        if (i == START) continue;
        dp[{{START, i}, i}] = get_dist(START, i);
        parent[{{START, i}, i}] = START;
    }

    // DP: subset 크기 3 ~ n
    for (int sz = 3; sz <= N; ++sz) {
        vector<set<int>> subsets;
        generate_combinations(sz, N, subsets);

        for (auto& S : subsets) {
            for (int j : S) {
                if (j == START) continue;

                int best_cost = INF;
                int best_prev = -1;

                set<int> subset = S;
                subset.erase(j);

                for (int prev : subset) {
                    auto it = dp.find({subset, prev});
                    if (it == dp.end()) continue;

                    int cost = it->second + get_dist(prev, j);
                    if (cost < best_cost) {
                        best_cost = cost;
                        best_prev = prev;
                    }
                }

                if (best_cost < INF) {
                    dp[{S, j}] = best_cost;
                    parent[{S, j}] = best_prev;
                }
            }
        }
    }

    // 마지막 복귀 단계: 전체 집합에서 START로 복귀
    set<int> full;
    for (int i = 1; i <= N; ++i) full.insert(i);

    int best_cost = INF;
    int last_node = -1;
    for (int j = 1; j <= N; ++j) {
        if (j == START) continue;
        auto it = dp.find({full, j});
        if (it == dp.end()) continue;

        int cost = it->second + get_dist(j, START);
        if (cost < best_cost) {
            best_cost = cost;
            last_node = j;
        }
    }

    // 경로 복원
    vector<int> tour;
    set<int> S = full;
    int curr = last_node;
    while (curr != START) {
        tour.push_back(curr);
        int next = parent[{S, curr}];
        S.erase(curr);
        curr = next;
    }

    tour.push_back(START);              // 경로 시작점
    reverse(tour.begin(), tour.end());  // 정방향으로 정렬
    tour.push_back(START);              // START로 복귀

    return tour;
}

int main() {
    run("HeldKarp", HeldKarp_tour, files, use_2opt);
    return 0;
}
