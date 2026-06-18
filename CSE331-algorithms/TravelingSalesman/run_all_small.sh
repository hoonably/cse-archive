#!/bin/bash

CXX=clang++
CXXFLAGS="-std=c++17 -O2"
OUTPUT_NAME=temp_exec

CPP_FILES=(
  "Greedy.cpp"
  "MST.cpp"
  "Flow.cpp"
  "Flow_kNN.cpp"
  "HeldKarp.cpp"
)

for file in "${CPP_FILES[@]}"; do
  $CXX $CXXFLAGS "$file" -o $OUTPUT_NAME -lm
  if [ $? -ne 0 ]; then
    echo "❌ Compilation failed for original $file"
  else
    ./$OUTPUT_NAME "dataset/$dataset"
    rm -f $OUTPUT_NAME
  fi
done

# Python 후처리 스크립트 실행
echo "======== Running _result.py ========"
python3 _make_summary.py

echo "======== Running _visualize_tsp_paths.py ========"
python3 _visualize_tsp_paths.py
