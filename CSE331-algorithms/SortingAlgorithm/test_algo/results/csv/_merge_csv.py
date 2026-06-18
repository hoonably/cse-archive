# merge_all_csv_files.py

import csv
import os

OUTPUT_FILE = "__combined_results.csv"

def merge_all_csv_files():
    header_written = False
    with open(OUTPUT_FILE, "w", newline="") as outfile:
        writer = csv.writer(outfile)

        for filename in sorted(os.listdir()):
            if not filename.endswith(".csv") or filename == OUTPUT_FILE:
                continue  # except combined_results.csv는

            with open(filename, newline='') as infile:
                reader = csv.reader(infile)
                header = next(reader)

                if not header_written:
                    writer.writerow(header)
                    header_written = True

                for row in reader:
                    writer.writerow(row)

    print(f"✅ Merged into: {OUTPUT_FILE}")

if __name__ == "__main__":
    merge_all_csv_files()
