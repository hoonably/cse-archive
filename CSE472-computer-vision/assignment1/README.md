## Report

You can view the BoW-CNN report in the [document viewer](https://hoonably.github.io/cse-archive/bow-cnn/).

## Setup

### Create Conda Environment

```bash
conda create -n cv python=3.10
conda activate cv
```

### Install Dependencies

**CPU Only:**

```bash
pip install opencv-python numpy matplotlib tqdm
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
```

**Mac (Apple Silicon):**

```bash
pip install torch torchvision
pip install opencv-python numpy matplotlib tqdm
```

**GPU (CUDA 11.8):**

```bash
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118
pip install opencv-python numpy matplotlib tqdm
```

**GPU (CUDA 12.1):**

```bash
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
pip install opencv-python numpy matplotlib tqdm
```

## Usage

Navigate to the assignment directory and run:

```bash
cd BOW
tar -zxvf dataset.tar.gz
python BOW.py
```

```bash
cd CNN
python CNN.py
```
