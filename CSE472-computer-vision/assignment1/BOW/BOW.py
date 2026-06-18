import cv2
import numpy as np
import os
import csv
import matplotlib.pyplot as plt

np.random.seed(42)

#! ==============================================================
#! Problem 1: Implement BOW model training and evaluation
#! ==============================================================

def train_and_evaluate(dictionary_size, kernel_type='RBF'):
    """Train BOW model and evaluate with given dictionary size and kernel type
    
    Args:
        dictionary_size: Number of visual words in codebook
        kernel_type: 'RBF' (default) or 'INTER' (histogram intersection)
    """
    
    # Feature extraction
    categories = sorted([d for d in os.listdir('dataset/train') if os.path.isdir(os.path.join('dataset/train', d))])
    base_path = 'dataset/train'
    detector = cv2.ORB_create()

    train_paths = []
    train_labels = []
    train_features = np.array([])
    img_len = 30  # 30 images per category
    count = 0

    for idx, category in enumerate(categories):
        dir_path = base_path + '/' + category

        for i in range(img_len):
            img_path = dir_path + '/' + 'image_%04d.jpg' % (i+1)
            train_paths.append(img_path)
            train_labels.append(idx)
            img = cv2.imread(img_path)
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            kpt, desc= detector.detectAndCompute(gray, None)
            if train_features.size == 0:
                train_features = np.float32(desc)
            else:
                train_features = np.append(train_features, np.float32(desc), axis = 0)
                
            count+=1
            print('%d/%d - %s - %d feature points are detected\n' % (count,img_len*len(categories), img_path, desc.shape[0]))



    # Generate visual codebook
    dict_file=f'models/dictionary_{dictionary_size}.npy'
    os.makedirs('models', exist_ok=True)

    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 100, 0.1)
    # This will cluster extracted features into K visual words. (This step will take few minutes)
    ret,label, dictionary=cv2.kmeans(train_features,dictionary_size,None,criteria,10,cv2.KMEANS_RANDOM_CENTERS)

    np.save(dict_file, dictionary)



    # Make image histograms
    knn = cv2.ml.KNearest_create()
    knn.train(dictionary, cv2.ml.ROW_SAMPLE, np.float32(range(dictionary_size)))
    # Use 1 nearest neighbor classifier.
    hists = np.float32(np.zeros((len(train_paths), dictionary_size)))

    for i, path in enumerate(train_paths):

        # Extract feature descriptor.
        img = cv2.imread(path)
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        kpt, desc = detector.detectAndCompute(gray, None)

        # Find nearest codeword and map into histogram.
        ret, result, neighbours, dist = knn.findNearest(np.float32(desc), k=1)
        hist, bins = np.histogram(np.int32(result), bins=range(dictionary_size + 1))
        hist = np.float32(hist) / np.float32(np.sum(hist))
        hists[i, :] = hist  # Accumulate all histograms in 'hists'.
        print('%d/%d - Representing %s' % (i+1, len(train_paths), path))



    # Train SVM
    svm_model_file = f'models/svmmodel_{dictionary_size}_{kernel_type}.xml'
    svm = cv2.ml.SVM_create()
    if kernel_type == 'INTER':
        svm.setKernel(cv2.ml.SVM_INTER)
    svm.train(hists, cv2.ml.ROW_SAMPLE, np.array(train_labels))
    svm.save(svm_model_file)



    # Testing
    # Test all test images
    test_base_path = 'dataset/test'
    test_paths = []
    test_labels = []

    for idx, category in enumerate(categories):
        dir_path = test_base_path + '/' + category
        for i in range(5):  # image_0031.jpg ~ image_0035.jpg
            img_path = dir_path + '/' + 'image_%04d.jpg' % (i+31)
            test_paths.append(img_path)
            test_labels.append(idx)

    test_desc = np.float32(np.zeros((len(test_paths), dictionary_size)))

    for i, path in enumerate(test_paths):
        # Make BOW representation for each.
        img = cv2.imread(path)
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        kpt, desc = detector.detectAndCompute(gray, None)
        ret, result, neighbours, dist = knn.findNearest(np.float32(desc), k=1)
        hist, bins = np.histogram(np.int32(result), bins=range(dictionary_size + 1))
        test_desc[i, :] = np.float32(hist) / np.float32(np.sum(hist))

    # Do SVM classification.
    ret, predictions = svm.predict(test_desc)



    # Calculate accuracy
    predictions = predictions.flatten().astype(np.int32)
    test_labels = np.array(test_labels)
    correct = np.sum(predictions == test_labels)
    total = len(test_labels)
    accuracy = 100.0 * correct / total

    print(f'\n[Dictionary Size: {dictionary_size}, Kernel: {kernel_type}] Accuracy: {accuracy:.2f}% ({correct}/{total})\n')
    
    return accuracy

#! ==============================================================
#! Problem 2: Experiment with different dictionary sizes
#! ==============================================================

dictionary_sizes = [50, 100, 300, 500, 1000]
accuracies = []

for size in dictionary_sizes:
    print(f'\n{"="*60}')
    print(f'Training with dictionary size: {size}')
    print(f'{"="*60}\n')
    acc = train_and_evaluate(size)
    accuracies.append(acc)

# Print results summary
print(f'\n{"="*60}')
print('RESULTS SUMMARY')
print(f'{"="*60}')
for size, acc in zip(dictionary_sizes, accuracies):
    print(f'Dictionary Size: {size:4d} -> Accuracy: {acc:.2f}%')
print(f'{"="*60}\n')

# Save results to CSV
os.makedirs('results', exist_ok=True)
csv_file = f'results/problem2_results.csv'
with open(csv_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Dictionary Size', 'Accuracy (%)'])
    for size, acc in zip(dictionary_sizes, accuracies):
        writer.writerow([size, f'{acc:.2f}'])
print(f'Problem 2 results saved to: {csv_file}\n')

# Plot dictionary size vs accuracy
plt.figure()
plt.plot(dictionary_sizes, accuracies, marker='o')
plt.xlabel('Dictionary Size')
plt.ylabel('Accuracy (%)')
plt.title('Effect of Dictionary Size on Classification Accuracy')
plt.grid(True)
plt.tight_layout()
plt.savefig('results/problem2_dictsize_vs_accuracy.png', dpi=300)
plt.close()


#! ==============================================================
#! Problem 3: Use histogram intersection kernel
#! ==============================================================

print('\n\n' + '='*60)
print('Problem 3: Testing Histogram Intersection Kernel')
print('='*60)

# Use dictionary_size=300 (best from Problem 2) with histogram intersection kernel
best_size = 300
print(f'\nUsing dictionary size: {best_size}')
print('Comparing RBF kernel vs Histogram Intersection kernel\n')

# Test with RBF kernel (default)
print('\n--- RBF Kernel ---')
acc_rbf = train_and_evaluate(best_size, kernel_type='RBF')

# Test with Histogram Intersection kernel
print('\n--- Histogram Intersection Kernel ---')
acc_inter = train_and_evaluate(best_size, kernel_type='INTER')

# Print comparison
print(f'\n{"="*60}')
print('Problem 3 RESULTS')
print(f'{"="*60}')
print(f'RBF Kernel:                      {acc_rbf:.2f}%')
print(f'Histogram Intersection Kernel:   {acc_inter:.2f}%')
print(f'Difference:                      {acc_inter - acc_rbf:+.2f}%')
print(f'{"="*60}\n')

# Save results to CSV
csv_file = f'results/problem3_results.csv' 
with open(csv_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Kernel Type', 'Accuracy (%)', 'Difference (%)'])
    writer.writerow(['RBF', f'{acc_rbf:.2f}', '-'])
    writer.writerow(['Histogram Intersection', f'{acc_inter:.2f}', f'{acc_inter - acc_rbf:+.2f}'])
print(f'Problem 3 results saved to: {csv_file}\n')

# Plot kernel comparison
kernels = ['RBF', 'Histogram Intersection']
kernel_accuracies = [acc_rbf, acc_inter]

plt.figure()
plt.bar(kernels, kernel_accuracies)
plt.ylabel('Accuracy (%)')
plt.title(f'Kernel Comparison at Dictionary Size {best_size}')
plt.tight_layout()
plt.savefig('results/problem3_kernel_comparison.png', dpi=300)
plt.close()