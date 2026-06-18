import random
import os

def generate_sorted(n, descending=False):
    data = list(range(n))
    if descending:
        data.reverse()
    return data

def generate_random(n):
    data = list(range(n))
    random.shuffle(data)
    return data

# Generates a partially sorted array with a given ratio of sorted elements
def generate_partially_sorted(n, sorted_ratio):
    sorted_part = list(range(int(n * sorted_ratio)))
    unsorted_part = list(range(int(n * sorted_ratio), n))
    random.shuffle(unsorted_part)
    return sorted_part + unsorted_part

def save_to_file(data, filename):
    with open(filename, 'w') as f:
        f.write(' '.join(map(str, data)) + '\n')

def generate_all(n, output_dir, prefix):
    os.makedirs(output_dir, exist_ok=True)

    # Generate different types of input files
    save_to_file(generate_sorted(n), f"{output_dir}/{prefix}_sorted_asc.txt")
    save_to_file(generate_sorted(n, descending=True), f"{output_dir}/{prefix}_sorted_desc.txt")
    save_to_file(generate_random(n), f"{output_dir}/{prefix}_random.txt")
    save_to_file(generate_partially_sorted(n, 0.5), f"{output_dir}/{prefix}_partial_50.txt")  # 50% sorted
    save_to_file(generate_partially_sorted(n, 0.8), f"{output_dir}/{prefix}_partial_80.txt")  # 80% sorted

if __name__ == "__main__":
    sizes = [1000, 10000, 100000, 1000000]  # 1K ~ 1M
    for n in sizes:
        generate_all(n, output_dir="input", prefix=f"n{n}")
