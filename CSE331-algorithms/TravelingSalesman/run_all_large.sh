#!/bin/bash

CXX=clang++
CXXFLAGS="-std=c++17 -O2"
OUTPUT_NAME=temp_exec

# Only able to O(N) space complexity
CPP_FILES=(
  "Greedy.cpp"
  "MST.cpp"
  # "Flow.cpp"
  # "Flow_kNN.cpp"
)

for file in "${CPP_FILES[@]}"; do
  # change to util2
  TEMP_FILE="temp_$file"
  sed 's/#include "util\.h"/#include "util2.h"/' "$file" > "$TEMP_FILE"

  $CXX $CXXFLAGS "$TEMP_FILE" -o $OUTPUT_NAME -lm
  if [ $? -ne 0 ]; then
    echo "❌ Compilation failed for modified $file"
  else
    ./$OUTPUT_NAME "dataset/$dataset"
    rm -f $OUTPUT_NAME
  fi

  rm -f "$TEMP_FILE"
done

# Python 후처리 스크립트 실행
echo "======== Running _result.py ========"
python3 _make_summary.py

echo "======== Running _visualize_tsp_paths.py ========"
python3 _visualize_tsp_paths.py
