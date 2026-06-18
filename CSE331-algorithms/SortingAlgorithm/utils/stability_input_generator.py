import random
import os

def generate_stability_input(n):
    data = []
    num_classes = 50  # For same number is repeated
    for i in range(n):
        value = random.randint(0, num_classes - 1)
        data.append((value, i))  # (value, original index)
    return data

def save_stability_input(data, filename):
    with open(filename, 'w') as f:
        for value, idx in data:
            f.write(f"{value} {idx}\n")

if __name__ == "__main__":
    output_dir = "../input"
    os.makedirs(output_dir, exist_ok=True)

    data = generate_stability_input(1000)
    save_stability_input(data, "../test_stability/input/stability_1000.txt")
