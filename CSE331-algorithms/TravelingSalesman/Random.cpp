//! For datasets over 10K cities, use "util2.h" instead
#include "util.h"
// #include "util2.h"

#include <random>

// You should put this file in the dataset/ directory
vector<string> files = {
    "weird20.tsp",
    "a280.tsp", 
    "xql662.tsp", 
    "kz9976.tsp", 
    // "mona_lisa100K.tsp"
};
bool use_2opt = true;  // 2-opt 최적화도 측정할지

vector<int> random_tour() {
    vector<int> tour(N);
    for (int i = 0; i < N; ++i) {
        tour[i] = i + 1;
    }

    // 셔플 수행
    random_device rd;
    mt19937 gen(rd());
    shuffle(tour.begin(), tour.end(), gen);

    tour.push_back(tour.front());  // 시작점으로 복귀
    return tour;
}


int main() {
    run("Random", random_tour, files, use_2opt);
    return 0;
}
