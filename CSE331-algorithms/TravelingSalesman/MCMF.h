// Minimum Cost Maximum Flow (MCMF) implementation
// This implementation uses SPFA for finding the shortest path and DFS for augmenting flow.
struct MCMF {
    using CostType = int;
    using FlowType = int;
    const CostType EPS = 0;

    struct Edge {
        int to, rev;
        FlowType cap;
        CostType cost;
    };

    int vertexSZ, SZ, bias, SRC, SINK;
    vector<vector<Edge>> graph;
    vector<bool> inQ;
    vector<CostType> costs;
    vector<bool> chk;
    vector<int> work;

    void init(int n) {
        vertexSZ = 2 * (n + 1);
        SZ = vertexSZ + 10;
        bias = n + 1;
        SRC = vertexSZ - 2;  // 2n
        SINK = vertexSZ - 1;  // 2n + 1

        graph.assign(SZ, {});
        inQ.assign(SZ, false);
        costs.assign(SZ, 0);
        chk.assign(SZ, false);
        work.assign(SZ, 0);
    }

    void addEdge(int from, int to, FlowType cap, CostType cost) {
        graph[from].push_back({to, (int)graph[to].size(), cap, cost});
        graph[to].push_back({from, (int)graph[from].size() - 1, 0, -cost});
    }

    bool spfa(int S, int T) {
        fill(costs.begin(), costs.end(), INF);
        fill(inQ.begin(), inQ.end(), false);
        queue<int> q;
        q.push(S);
        inQ[S] = true;
        costs[S] = 0;

        while (!q.empty()) {
            int now = q.front(); q.pop(); inQ[now] = false;
            for (const Edge& e : graph[now]) {
                if (e.cap > 0 && costs[e.to] > costs[now] + e.cost + EPS) {
                    costs[e.to] = costs[now] + e.cost;
                    if (!inQ[e.to]) inQ[e.to] = true, q.push(e.to);
                }
            }
        }
        return costs[T] < INF;
    }

    FlowType dfs(int now, int T, FlowType flow) {
        chk[now] = true;
        if (now == T) return flow;
        for (; work[now] < (int)graph[now].size(); ++work[now]) {
            Edge &e = graph[now][work[now]];
            if (!chk[e.to] && costs[e.to] == costs[now] + e.cost && e.cap > 0) {
                FlowType ret = dfs(e.to, T, min(flow, e.cap));
                if (ret > 0) {
                    e.cap -= ret;
                    graph[e.to][e.rev].cap += ret;
                    return ret;
                }
            }
        }
        return 0;
    }

    pair<CostType, FlowType> run(int S = -1, int T = -1) {
        if (S == -1) S = SRC;
        if (T == -1) T = SINK;
        CostType cost = 0;
        FlowType flow = 0;
        while (spfa(S, T)) {
            fill(chk.begin(), chk.end(), false);
            fill(work.begin(), work.end(), 0);
            while (FlowType f = dfs(S, T, INF)) {
                cost += costs[T] * f;
                flow += f;
                fill(chk.begin(), chk.end(), false);
            }
        }
        return {cost, flow};
    }
};