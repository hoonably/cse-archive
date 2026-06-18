import cv2
import numpy as np
import os

# ---------------------------------------------------------------
# Test indices to visualize
# ---------------------------------------------------------------
selected_indices = [50, 51, 52, 53, 54, 55, 56, 57, 58, 59]

# ---------------------------------------------------------------
# Settings
# ---------------------------------------------------------------

# Stage 2: dictionary sizes (RBF kernel)
stage2_dict_sizes = [50, 100, 300, 500, 1000]
stage2_models = [(k, "RBF") for k in stage2_dict_sizes]

# Stage 3: histogram intersection kernel for K=300
stage3_models = [(300, "INTER")]

# All models
all_models = stage2_models + stage3_models

save_root = "results/examples"
os.makedirs(save_root, exist_ok=True)

# ---------------------------------------------------------------
# Load categories (train-based class order)
# ---------------------------------------------------------------

categories = sorted([
    d for d in os.listdir("dataset/train")
    if os.path.isdir(os.path.join("dataset/train", d))
])

detector = cv2.ORB_create()

# ---------------------------------------------------------------
# Prepare test paths & labels (shared)
# ---------------------------------------------------------------

test_paths = []
test_labels = []

test_base_path = "dataset/test"
for idx, category in enumerate(categories):
    dir_path = os.path.join(test_base_path, category)
    for i in range(5):  # image_0031~0035
        img_path = os.path.join(dir_path, "image_%04d.jpg" % (i + 31))
        test_paths.append(img_path)
        test_labels.append(idx)

test_labels = np.array(test_labels)
print(f"Total test images: {len(test_paths)}")

# ---------------------------------------------------------------
# Run all models and store predictions
# ---------------------------------------------------------------

# key: (dict_size, kernel_type) -> value: predictions array
all_predictions = {}

for dict_size, kernel_type in all_models:
    print("\n" + "=" * 60)
    print(f"Model: dict_size={dict_size}, kernel={kernel_type}")
    print("=" * 60)

    # Load dictionary
    dict_file = f"models/dictionary_{dict_size}.npy"
    if not os.path.exists(dict_file):
        print(f"[WARN] dictionary file not found: {dict_file}")
        continue

    dictionary = np.load(dict_file).astype(np.float32)

    # Prepare KNN for visual word mapping
    knn = cv2.ml.KNearest_create()
    knn.train(dictionary, cv2.ml.ROW_SAMPLE,
              np.float32(range(dict_size)))

    # Load SVM
    svm_model_file = f"models/svmmodel_{dict_size}_{kernel_type}.xml"
    if not os.path.exists(svm_model_file):
        print(f"[WARN] svm model file not found: {svm_model_file}")
        continue

    svm = cv2.ml.SVM_load(svm_model_file)

    # Compute BOW features for all test images
    test_desc = np.float32(np.zeros((len(test_paths), dict_size)))

    for i, path in enumerate(test_paths):
        img = cv2.imread(path)
        if img is None:
            print(f"[WARN] cannot read image: {path}")
            continue

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        kpt, desc = detector.detectAndCompute(gray, None)

        if desc is None:
            print(f"[WARN] no features detected in {path}")
            continue

        ret, result, neighbours, dist = knn.findNearest(
            np.float32(desc), k=1
        )
        hist, bins = np.histogram(
            np.int32(result),
            bins=range(dict_size + 1)
        )
        hist = np.float32(hist) / np.float32(np.sum(hist))
        test_desc[i, :] = hist

    # Predict
    ret, predictions = svm.predict(test_desc)
    predictions = predictions.flatten().astype(np.int32)

    # Accuracy info (optional)
    correct_mask = (predictions == test_labels)
    correct_cnt = int(correct_mask.sum())
    total_cnt = len(test_labels)
    acc = 100.0 * correct_cnt / total_cnt
    print(f"Accuracy: {acc:.2f}%  ({correct_cnt}/{total_cnt})")

    # Store
    all_predictions[(dict_size, kernel_type)] = predictions

print("\nAll models finished. Now generating summary images...")

# ---------------------------------------------------------------
# For each selected index, create one summary image:
# left: original image / right: white panel with text
# ---------------------------------------------------------------

# Fixed order for printing
model_tags = [
    (50, "RBF"),
    (100, "RBF"),
    (300, "RBF"),
    (500, "RBF"),
    (1000, "RBF"),
    (300, "INTER"),
]

for ex_i, idx in enumerate(selected_indices):
    if idx >= len(test_paths):
        continue

    img = cv2.imread(test_paths[idx])
    if img is None:
        print(f"[WARN] cannot read image for idx {idx}: {test_paths[idx]}")
        continue

    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # Resize image to fixed width for layout
    target_width = 400
    h, w, c = img_rgb.shape
    if w != target_width:
        scale = target_width / w
        new_h = int(h * scale)
        img_rgb = cv2.resize(img_rgb, (target_width, new_h),
                              interpolation=cv2.INTER_LINEAR)

    h, w, c = img_rgb.shape

    # Right panel size
    panel_width = 400
    panel_height = h
    panel = np.ones((panel_height, panel_width, 3), dtype=np.uint8) * 255

    # Text content
    true_label = categories[test_labels[idx]]

    y0 = 30
    dy = 35

    # True label
    text_true = f"True : {true_label}"
    cv2.putText(
        panel,
        text_true,
        (10, y0),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (0, 0, 0),
        2,
        cv2.LINE_AA
    )

    # Predictions per model
    y = y0 + dy
    for ds, ker in model_tags:
        key = (ds, ker)
        if key not in all_predictions:
            line = f"K{ds}_{ker} : (no model)"
        else:
            pred_idx = all_predictions[key][idx]
            pred_label = categories[pred_idx]
            line = f"K{ds}_{ker} : {pred_label}"

        # Predictions per model
        y = y0 + dy
        for ds, ker in model_tags:
            key = (ds, ker)
            if key not in all_predictions:
                pred_label = "(no model)"
            else:
                pred_idx = all_predictions[key][idx]
                pred_label = categories[pred_idx]

            line = f"K{ds}_{ker} : {pred_label}"

            # -----------------------------
            # 색상 결정 (True = 파란색, False = 빨간색)
            # -----------------------------
            if pred_label == true_label:
                color = (0, 0, 255)      # 빨간색 (BGR)
            else:
                color = (255, 0, 0)      # 파란색 (BGR)

            cv2.putText(
                panel,
                line,
                (10, y),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                color,
                2,
                cv2.LINE_AA
            )
            y += dy


    # Concatenate image + panel horizontally
    combined = np.hstack([img_rgb, panel])

    # Save
    save_path = os.path.join(save_root, f"summary_idx_{idx:03d}.jpg")
    cv2.imwrite(save_path, cv2.cvtColor(combined, cv2.COLOR_RGB2BGR))

    print(f"Saved summary for idx {idx} -> {save_path}")

print("\nDone.")
