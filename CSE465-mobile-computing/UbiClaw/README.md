# UbiClaw


<a href="https://hoonably.github.io/cse-archive/ubiclaw"><img src="https://img.shields.io/static/v1?label=Project&message=Page&color=blue"></a>
<a href="https://github.com/hoonably/cse-archive/tree/main/CSE465-mobile-computing/UbiClaw"><img src="https://img.shields.io/static/v1?label=Project&message=Code&color=24292f"></a>
<a href="https://github.com/user-attachments/assets/bdf7fbd3-572e-4c91-9000-89634bc16d86"><img src="https://img.shields.io/badge/Project-Video-2ea44f?logo=video&logoColor=white"></a>


A macOS benchmarking tool for measuring how background LLM inference affects foreground app responsiveness on Apple Silicon. Run controlled UI workloads alongside llama.cpp inference, then analyze the interference using Xcode Instruments signposts and CSV logs.

https://github.com/user-attachments/assets/bdf7fbd3-572e-4c91-9000-89634bc16d86

## Report

You can view the report in the [document viewer](https://hoonably.github.io/cse-archive/ubiclaw/) or open the local [report.pdf](report.pdf).

## Requirements

- macOS 15.0+ (Sequoia)
- Xcode 26+
- Apple Silicon Mac
- [llama.cpp](https://github.com/ggerganov/llama.cpp) built locally (for LLM inference)

## Setup

### 1. Build llama.cpp (static)

From the UbiClaw repo root, build the repo-local `llama.cpp` checkout:

```bash
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
cmake -B build-static -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_BLAS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-static --config Release -j$(sysctl -n hw.ncpu) -- llama ggml
cd ..
```

### 2. Prepare HexGL foreground workload (optional)

The HexGL Race workload uses a local checkout of [BKcore/HexGL](https://github.com/BKcore/HexGL). Like `llama.cpp`, the checkout is not committed to this repo. From the UbiClaw repo root:

```bash
git clone https://github.com/BKcore/HexGL.git HexGL
./Scripts/setup_hexgl.sh
```

The script checks out the pinned upstream commit and applies UbiClaw's local WebView/FPS compatibility patch. The app loads `HexGL/index.html` directly from the repo-local checkout.

### 3. Prepare a GGUF model

Download a GGUF model checkpoint and keep the file path available for the app's model path field. For example, you can use a Qwen Q4_K_M GGUF checkpoint:

```bash
mkdir -p Models
curl -L -o Models/Qwen_Qwen3.5-9B-Q4_K_M.gguf "https://huggingface.co/bartowski/Qwen_Qwen3.5-9B-GGUF/resolve/main/Qwen_Qwen3.5-9B-Q4_K_M.gguf?download=true"
```

## Output Logs

CSV logs are written to the repo-local `Logs/` directory by default. The directory keeps its own `.gitignore`, so generated `*.csv` files are not committed.

## Project Structure

```
UbiClaw/
  App/
    UbiClawApp.swift    — App entry point
    ContentView.swift             — Main UI: controls, workload display, LLM output
  Config/
    AppConfig.swift               — Configuration model + CLI argument parsing
  Instrumentation/
    Signposts.swift               — OSSignposter wrapper for Instruments profiling
  Logging/
    CSVLogger.swift               — Structured CSV event logger
  Scenario/
    ScenarioPhase.swift           — Phase definitions (idle, foreground, overlap, etc.)
    ScenarioRunner.swift          — Scenario orchestrator with timeline tracking
  Workloads/
    ScrollWorkloadView.swift      — Auto-scrolling 10K-row List
    AnimationWorkloadView.swift   — 500-particle Canvas animation
    Game3DWorkloadView.swift      — Real-time 3D scene rendered with Metal
    HexGLRaceWorkloadView.swift   — Embedded HexGL WebGL racing workload
    ImageFilterWorkloadView.swift — Repeated CIGaussianBlur on a 2048x2048 image
    MemoryStreamWorkloadView.swift      — CPU memory streaming via Accelerate/vDSP
    MetalMemoryStreamWorkloadView.swift — GPU memory streaming via Metal compute
    MemoryStreamKernels.metal     — Metal compute kernels for memory streaming
  LLM/
    LLMEngine.swift               — Protocol for inference engines
    InProcessLLMEngine.swift      — In-process llama.cpp via Obj-C++ bridge
    ExternalProcessLLMEngine.swift — External CLI process (e.g. llama-cli)
    LlamaBridge.h / .mm           — Obj-C++ bridge to llama.cpp C API
Scripts/
  setup_hexgl.sh                  — Clone pinned HexGL and apply UbiClaw local patches
```

## Scenario Types

| Scenario | Description |
|---|---|
| `foreground_only` | Foreground workload only, no LLM — measures baseline workload performance |
| `overlap` | Foreground workload + LLM inference simultaneously — measures interference |
| `llm_inference_only` | LLM inference only, no foreground workload — measures standalone LLM throughput |

### Scenario Phases

Each scenario runs through a subset of these phases:

Before the measured scenario timer starts, in-process runs preload the model, then wait for the configured start delay.

1. **Idle / Foreground lead-in** — Baseline period before LLM inference starts
2. **Overlap / LLM Inference** — LLM runs (with or without foreground workload); ends when inference completes
3. **Recovery** — Foreground workload continues after LLM finishes (overlap only)
