import cv2
import numpy as np
import os
import csv
import matplotlib.pyplot as plt
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from torchvision import models, transforms
import random

# Set random seeds for reproducibility
SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)
torch.cuda.manual_seed(SEED)
torch.cuda.manual_seed_all(SEED)
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False

#! ==============================================================
#! Problem 4: Generate clock images dataset
#! ==============================================================

def draw_clock(hour, minute):
    """Draw a clock image with given hour and minute
    
    Args:
        hour: Hour value (0-11)
        minute: Minute value (0-59)
        
    Returns:
        img: 227x227x3 clock image
    """
    # Create image
    img = np.zeros((227, 227, 3), dtype=np.uint8)
    center = (113, 113)  # Center of 227x227 image
    radius = 112
    
    # Generate random colors (not black)
    while True:
        bg_color = tuple(np.random.randint(30, 256, 3).tolist())
        clock_color = tuple(np.random.randint(30, 256, 3).tolist())
        # Ensure colors are different enough
        if np.linalg.norm(np.array(bg_color) - np.array(clock_color)) > 100:
            break
    
    # Fill background
    img[:] = bg_color
    
    # Draw clock circle
    cv2.circle(img, center, radius, clock_color, -1)
    
    # Add random noise
    noise = np.random.normal(0, 15, img.shape).astype(np.int16)
    img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    
    # Draw numbers 1-12
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.7
    font_thickness = 2
    
    for num in range(1, 13):
        angle = np.pi / 2 - (num * np.pi / 6)  # 12 is at top
        x = int(center[0] + 85 * np.cos(angle))
        y = int(center[1] - 85 * np.sin(angle))
        
        # Adjust position for text centering
        text = str(num)
        text_size = cv2.getTextSize(text, font, font_scale, font_thickness)[0]
        text_x = x - text_size[0] // 2
        text_y = y + text_size[1] // 2
        
        cv2.putText(img, text, (text_x, text_y), font, font_scale, (0, 0, 0), font_thickness, cv2.LINE_AA)
    
    # Calculate angles for hands
    minute_angle = np.pi / 2 - (minute * np.pi / 30)  # 6 degrees per minute
    hour_angle = np.pi / 2 - ((hour % 12) * np.pi / 6 + minute * np.pi / 360)  # 30 degrees per hour + minute offset
    
    # Draw minute hand (90 pixels, thickness 3)
    minute_end_x = int(center[0] + 90 * np.cos(minute_angle))
    minute_end_y = int(center[1] - 90 * np.sin(minute_angle))
    cv2.line(img, center, (minute_end_x, minute_end_y), (0, 0, 0), 3)
    
    # Draw hour hand (45 pixels, thickness 5)
    hour_end_x = int(center[0] + 45 * np.cos(hour_angle))
    hour_end_y = int(center[1] - 45 * np.sin(hour_angle))
    cv2.line(img, center, (hour_end_x, hour_end_y), (0, 0, 0), 5)
    
    return img


def generate_dataset(num_images=10000):
    """Generate clock images dataset
    
    Args:
        num_images: Number of images to generate
    """
    print(f'Generating {num_images} clock images...\n')
    
    # Create directories
    os.makedirs('dataset/train', exist_ok=True)
    os.makedirs('dataset/test', exist_ok=True)
    
    # Generate balanced time combinations (all hours and minutes evenly distributed)
    all_times = []
    
    # Calculate how many images per hour (12 hours)
    images_per_hour = num_images // 12
    remaining = num_images % 12
    
    for hour in range(12):
        # Number of images for this hour
        num_for_this_hour = images_per_hour + (1 if hour < remaining else 0)
        
        # Evenly distribute minutes
        for i in range(num_for_this_hour):
            minute = (i * 60) // num_for_this_hour  # Distribute evenly across 60 minutes
            all_times.append((hour, minute))
    
    # Shuffle to randomize order
    np.random.shuffle(all_times)
    
    # Split into train (80%) and test (20%)
    num_train = int(num_images * 0.8)
    train_times = all_times[:num_train]
    test_times = all_times[num_train:]
    
    # Generate training images
    print('Generating training images...')
    for i, (hour, minute) in enumerate(train_times):
        img = draw_clock(hour, minute)
        filename = f'dataset/train/clock_{i:05d}_h{hour:02d}_m{minute:02d}.jpg'
        cv2.imwrite(filename, img)
        
        if (i + 1) % 1000 == 0:
            print(f'{i + 1}/{num_train} training images generated')
    
    print(f'Training images complete: {num_train} images\n')
    
    # Generate test images
    print('Generating test images...')
    for i, (hour, minute) in enumerate(test_times):
        img = draw_clock(hour, minute)
        filename = f'dataset/test/clock_{i:05d}_h{hour:02d}_m{minute:02d}.jpg'
        cv2.imwrite(filename, img)
        
        if (i + 1) % 500 == 0:
            print(f'{i + 1}/{len(test_times)} test images generated')
    
    print(f'Test images complete: {len(test_times)} images\n')
    
    print(f'Dataset generation complete!')
    print(f'Total: {num_images} images (Train: {num_train}, Test: {len(test_times)})')
    
    # Show example images
    show_examples(train_times[:6])


def show_examples(times, num_examples=6):
    """Display example clock images
    
    Args:
        times: List of (hour, minute) tuples
        num_examples: Number of examples to show
    """

    os.makedirs('results', exist_ok=True)

    fig, axes = plt.subplots(2, 3, figsize=(12, 8))
    axes = axes.flatten()
    
    for i in range(min(num_examples, len(times))):
        hour, minute = times[i]
        img = draw_clock(hour, minute)
        
        axes[i].imshow(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
        axes[i].set_title(f'Time: {hour:02d}:{minute:02d}')
        axes[i].axis('off')
    
    plt.tight_layout()
    plt.savefig('results/example_clocks.png', dpi=150)
    print(f'\nExample images saved to: results/example_clocks.png')
    plt.close()


#! ==============================================================
#! Problem 5: CNN Architecture for Clock Time Prediction
#! ==============================================================

# Dataset class
class ClockDataset(Dataset):
    """Dataset for loading clock images and extracting time labels from filename"""
    def __init__(self, image_dir, transform=None):
        self.image_dir = image_dir
        self.transform = transform
        self.image_files = [f for f in os.listdir(image_dir) if f.endswith('.jpg')]
        
    def __len__(self):
        return len(self.image_files)
    
    def __getitem__(self, idx):
        img_name = self.image_files[idx]
        img_path = os.path.join(self.image_dir, img_name)
        
        # Read image
        image = cv2.imread(img_path)
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        
        # Extract hour and minute from filename: clock_xxxxx_hXX_mXX.jpg
        parts = img_name.split('_')
        hour = int(parts[2][1:])  # hXX -> XX
        minute = int(parts[3][1:].split('.')[0])  # mXX.jpg -> XX
        
        # Normalize to [0, 1] range (as suggested in tips)
        hour_norm = hour / 12.0  # 0-11 -> 0-1
        minute_norm = minute / 60.0  # 0-59 -> 0-1
        
        if self.transform:
            image = self.transform(image)
        
        return image, torch.tensor([hour_norm, minute_norm], dtype=torch.float32)


# Modified ResNet for clock prediction using pretrained weights
class ClockResNet(nn.Module):
    def __init__(self, base_dim=64, pretrained=True):
        super(ClockResNet, self).__init__()
        
        if pretrained:
            # Load pretrained ResNet18 from torchvision
            resnet = models.resnet18(pretrained=True)
            self.layer_1 = nn.Sequential(resnet.conv1, resnet.bn1, resnet.relu, resnet.maxpool)
            self.layer_2 = resnet.layer1
            self.layer_3 = resnet.layer2
            self.layer_4 = resnet.layer3
            self.layer_5 = resnet.layer4
            self.avgpool = resnet.avgpool
            # Replace FC layer: ResNet18 has 512 features
            self.fc_layer = nn.Sequential(
                nn.Linear(512, 256),
                nn.ReLU(),
                nn.Dropout(0.3),
                nn.Linear(256, 2),
                nn.Sigmoid()  # Output in [0,1] range
            )
        else:
            # Use custom ResNet architecture
            self.act_fn = nn.ReLU()
            self.layer_1 = nn.Sequential(
                nn.Conv2d(3,base_dim,7,2,3),
                nn.ReLU(),
                nn.MaxPool2d(3,2,1),
            )
            self.layer_2 = nn.Sequential(
                BottleNeck(base_dim,base_dim,base_dim*4,self.act_fn),
                BottleNeck_no_down(base_dim*4,base_dim,base_dim*4,self.act_fn),
                BottleNeck_stride(base_dim*4,base_dim,base_dim*4,self.act_fn),
            )
            self.layer_3 = nn.Sequential(
                BottleNeck(base_dim*4,base_dim*2,base_dim*8,self.act_fn),
                BottleNeck_no_down(base_dim*8,base_dim*2,base_dim*8,self.act_fn),
                BottleNeck_no_down(base_dim*8,base_dim*2,base_dim*8,self.act_fn),
                BottleNeck_stride(base_dim*8,base_dim*2,base_dim*8,self.act_fn),
            )
            self.layer_4 = nn.Sequential(
                BottleNeck(base_dim*8,base_dim*4,base_dim*16,self.act_fn),
                BottleNeck_no_down(base_dim*16,base_dim*4,base_dim*16,self.act_fn),
                BottleNeck_no_down(base_dim*16,base_dim*4,base_dim*16,self.act_fn),
                BottleNeck_no_down(base_dim*16,base_dim*4,base_dim*16,self.act_fn),
                BottleNeck_no_down(base_dim*16,base_dim*4,base_dim*16,self.act_fn),
                BottleNeck_stride(base_dim*16,base_dim*4,base_dim*16,self.act_fn),
            )
            self.layer_5 = nn.Sequential(
                BottleNeck(base_dim*16,base_dim*8,base_dim*32,nn.ReLU()),
                BottleNeck_no_down(base_dim*32,base_dim*8,base_dim*32,self.act_fn),
                BottleNeck(base_dim*32,base_dim*8,base_dim*32,self.act_fn),
            )
            self.avgpool = nn.AvgPool2d(7,1)
            self.fc_layer = nn.Sequential(
                nn.Linear(base_dim*32, 2),
                nn.Sigmoid()
            )

    def forward(self, x):
        out = self.layer_1(x)
        out = self.layer_2(out)
        out = self.layer_3(out)
        out = self.layer_4(out)
        out = self.layer_5(out)
        out = self.avgpool(out)
        out = out.view(out.size(0), -1)  # Flatten
        out = self.fc_layer(out)
        return out


# Helper blocks (kept from original code)
def conv_block_1(in_dim,out_dim,act_fn):
    model = nn.Sequential(
        nn.Conv2d(in_dim,out_dim, kernel_size=1, stride=1),
        act_fn,
    )
    return model

def conv_block_1_stride_2(in_dim,out_dim,act_fn):
    model = nn.Sequential(
        nn.Conv2d(in_dim,out_dim, kernel_size=1, stride=2),
        act_fn,
    )
    return model

def conv_block_1_n(in_dim,out_dim):
    model = nn.Sequential(
        nn.Conv2d(in_dim,out_dim, kernel_size=1, stride=1),
    )
    return model

def conv_block_1_stride_2_n(in_dim,out_dim):
    model = nn.Sequential(
        nn.Conv2d(in_dim,out_dim, kernel_size=1, stride=2),
    )
    return model

def conv_block_3(in_dim,out_dim,act_fn):
    model = nn.Sequential(
        nn.Conv2d(in_dim,out_dim, kernel_size=3, stride=1, padding=1),
        act_fn,
    )
    return model

class BottleNeck(nn.Module):
    def __init__(self,in_dim,mid_dim,out_dim,act_fn):
        super(BottleNeck,self).__init__()
        self.layer = nn.Sequential(
            conv_block_1(in_dim,mid_dim,act_fn),
            conv_block_3(mid_dim,mid_dim,act_fn),
            conv_block_1_n(mid_dim,out_dim),
        )
        self.downsample = nn.Conv2d(in_dim,out_dim,1,1)

    def forward(self,x):
        downsample = self.downsample(x)
        out = self.layer(x)
        out = out + downsample
        return out
    
class BottleNeck_no_down(nn.Module):
    def __init__(self,in_dim,mid_dim,out_dim,act_fn):
        super(BottleNeck_no_down,self).__init__()
        self.layer = nn.Sequential(
            conv_block_1(in_dim,mid_dim,act_fn),
            conv_block_3(mid_dim,mid_dim,act_fn),
            conv_block_1_n(mid_dim,out_dim),
        )

    def forward(self,x):
        out = self.layer(x)
        out = out + x
        return out
    
class BottleNeck_stride(nn.Module):
    def __init__(self,in_dim,mid_dim,out_dim,act_fn):
        super(BottleNeck_stride,self).__init__()
        self.layer = nn.Sequential(
            conv_block_1_stride_2(in_dim,mid_dim,act_fn),
            conv_block_3(mid_dim,mid_dim,act_fn),
            conv_block_1_n(mid_dim,out_dim),
        )
        self.downsample = nn.Conv2d(in_dim,out_dim,1,2)
        
    def forward(self,x):
        downsample = self.downsample(x)
        out = self.layer(x)
        out = out + downsample
        return out


#! ==============================================================
#! Problem 6: Training CNN Network
#! ==============================================================

def train_model(model, train_loader, val_loader, num_epochs=30, lr=0.001, device='cuda'):
    """Train the clock prediction model and save weights
    
    Args:
        model: ClockResNet model
        train_loader: Training data loader
        val_loader: Validation data loader
        num_epochs: Number of training epochs
        lr: Learning rate
        device: 'cuda' or 'cpu'
    """
    model = model.to(device)
    criterion = nn.MSELoss()  # MSE loss for normalized regression
    optimizer = optim.Adam(model.parameters(), lr=lr)
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, 'min', patience=5, factor=0.5)
    
    best_val_loss = float('inf')
    os.makedirs('models', exist_ok=True)
    
    # Lists to store losses for plotting
    train_losses = []
    val_losses = []
    
    for epoch in range(num_epochs):
        # Training
        model.train()
        train_loss = 0.0
        for images, targets in train_loader:
            images, targets = images.to(device), targets.to(device)
            
            optimizer.zero_grad()
            outputs = model(images)
            loss = criterion(outputs, targets)
            loss.backward()
            optimizer.step()
            train_loss += loss.item()
        
        train_loss /= len(train_loader)
        
        # Validation
        model.eval()
        val_loss = 0.0
        with torch.no_grad():
            for images, targets in val_loader:
                images, targets = images.to(device), targets.to(device)
                outputs = model(images)
                loss = criterion(outputs, targets)
                val_loss += loss.item()
        
        val_loss /= len(val_loader)
        scheduler.step(val_loss)
        
        # Store losses for plotting
        train_losses.append(train_loss)
        val_losses.append(val_loss)
        
        print(f'Epoch {epoch+1}/{num_epochs} - Train Loss: {train_loss:.4f}, Val Loss: {val_loss:.4f}')
        
        # Save best model (.pth file for submission)
        if val_loss < best_val_loss:
            best_val_loss = val_loss
            torch.save(model.state_dict(), 'models/best_clock_model.pth')
            print(f'  -> Best model saved!')
    
    print(f'\nTraining complete! Best val loss: {best_val_loss:.4f}')
    print('Model saved to: models/best_clock_model.pth\n')
    
    # Plot training curves
    os.makedirs('results', exist_ok=True)
    plt.figure(figsize=(10, 6))
    epochs_range = range(1, num_epochs + 1)
    plt.plot(epochs_range, train_losses, 'b-', label='Train Loss', linewidth=2)
    plt.plot(epochs_range, val_losses, 'r-', label='Val Loss', linewidth=2)
    plt.xlabel('Epoch', fontsize=12)
    plt.ylabel('Loss', fontsize=12)
    plt.title('Training and Validation Loss Curve', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig('results/problem6_loss_curve.png', dpi=150)
    print('Loss curve saved to: results/problem6_loss_curve.png\n')
    plt.close()

#! ==============================================================
#! Problem 7: Testing CNN on Single Image
#! ==============================================================

def predict_single_image(model, image_path, device='cuda'):
    """Predict time from a single clock image
    
    Args:
        model: Trained ClockResNet model
        image_path: Path to clock image
        device: 'cuda' or 'cpu'
        
    Returns:
        hour: Predicted hour (0-11)
        minute: Predicted minute (0-59)
    """
    model.eval()
    
    # Prepare image
    image = cv2.imread(image_path)
    image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    
    transform = transforms.Compose([
        transforms.ToPILImage(),
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])
    
    image_tensor = transform(image).unsqueeze(0).to(device)
    
    # Predict
    with torch.no_grad():
        output = model(image_tensor)
        hour_norm, minute_norm = output[0]
        
        # Denormalize (un-normalization formula)
        hour = int(round(hour_norm.item() * 12)) % 12
        minute = int(round(minute_norm.item() * 60)) % 60
    
    return hour, minute


#! ==============================================================
#! Problem 8: Accuracy Analysis with 5-minute Error Margin
#! ==============================================================

def evaluate_model_with_margin(model, test_loader, minute_margin=5, device='cuda'):
    """Evaluate model accuracy with error margin
    
    Args:
        model: Trained model
        test_loader: Test data loader
        minute_margin: Allowed error in minutes (default: 5)
        device: 'cuda' or 'cpu'
    """
    model = model.to(device)
    model.eval()
    
    correct_exact = 0
    correct_with_margin = 0
    total = 0
    
    hour_errors = []
    minute_errors = []
    success_cases = []
    failure_cases = []
    
    print(f'Evaluating model with ±{minute_margin} minute error margin...')
    
    with torch.no_grad():
        for images, targets in test_loader:
            images, targets = images.to(device), targets.to(device)
            outputs = model(images)
            
            for i in range(len(images)):
                # Denormalize predictions and ground truth
                pred_hour = int(round(outputs[i][0].item() * 12)) % 12
                pred_minute = int(round(outputs[i][1].item() * 60)) % 60
                
                true_hour = int(round(targets[i][0].item() * 12)) % 12
                true_minute = int(round(targets[i][1].item() * 60)) % 60
                
                # Convert to total minutes for accurate comparison
                pred_total_min = pred_hour * 60 + pred_minute
                true_total_min = true_hour * 60 + true_minute
                
                # Calculate time difference (handle 12-hour wrap around)
                time_diff = abs(pred_total_min - true_total_min)
                time_diff = min(time_diff, 720 - time_diff)  # 720 min = 12 hours
                
                # Calculate individual errors for logging
                hour_err = abs(pred_hour - true_hour)
                minute_err = abs(pred_minute - true_minute)
                
                hour_errors.append(hour_err)
                minute_errors.append(minute_err)
                
                # Check exact match
                if time_diff == 0:
                    correct_exact += 1
                
                # Check with margin (±5 minutes total difference)
                if time_diff <= minute_margin:
                    correct_with_margin += 1
                    if len(success_cases) < 5:
                        success_cases.append((true_hour, true_minute, pred_hour, pred_minute, time_diff))
                elif len(failure_cases) < 5:
                    failure_cases.append((true_hour, true_minute, pred_hour, pred_minute, hour_err, minute_err))
                
                total += 1
    
    # Calculate accuracies
    exact_acc = 100.0 * correct_exact / total
    margin_acc = 100.0 * correct_with_margin / total
    avg_hour_err = np.mean(hour_errors)
    avg_minute_err = np.mean(minute_errors)
    
    # Calculate minute error distribution (0, 1, 2, 3, 4, 5+ minutes)
    error_bins = [0, 0, 0, 0, 0, 0]  # 0min, 1min, 2min, 3min, 4min, 5+min
    for images, targets in test_loader:
        images, targets = images.to(device), targets.to(device)
        outputs = model(images)
        
        for i in range(len(images)):
            pred_hour = int(round(outputs[i][0].item() * 12)) % 12
            pred_minute = int(round(outputs[i][1].item() * 60)) % 60
            true_hour = int(round(targets[i][0].item() * 12)) % 12
            true_minute = int(round(targets[i][1].item() * 60)) % 60
            
            # Calculate time difference
            pred_total_min = pred_hour * 60 + pred_minute
            true_total_min = true_hour * 60 + true_minute
            time_diff = abs(pred_total_min - true_total_min)
            time_diff = min(time_diff, 720 - time_diff)
            
            # Categorize into bins
            if time_diff <= 4:
                error_bins[time_diff] += 1
            else:
                error_bins[5] += 1
    
    # Convert to percentages
    error_percentages = [(count / total) * 100 for count in error_bins]
    
    # Print results
    print(f'Total samples tested: {total}')
    print(f'Exact match accuracy: {exact_acc:.2f}% ({correct_exact}/{total})')
    print(f'Accuracy with ±{minute_margin}min margin: {margin_acc:.2f}% ({correct_with_margin}/{total})')
    print(f'Average hour error: {avg_hour_err:.2f}')
    print(f'Average minute error: {avg_minute_err:.2f}')
    
    # Plot minute error distribution
    os.makedirs('results', exist_ok=True)
    plt.figure(figsize=(10, 6))
    labels = ['0 min', '1 min', '2 min', '3 min', '4 min', '5+ min']
    colors = ['#2ecc71', '#3498db', '#f39c12', '#e67e22', '#e74c3c', '#95a5a6']
    bars = plt.bar(labels, error_percentages, color=colors, edgecolor='black', linewidth=1.5)
    
    # Add percentage labels on bars
    for bar, pct in zip(bars, error_percentages):
        height = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2., height,
                f'{pct:.1f}%', ha='center', va='bottom', fontsize=11, fontweight='bold')
    
    plt.xlabel('Minute Error', fontsize=12)
    plt.ylabel('Percentage (%)', fontsize=12)
    plt.title('Minute Error Distribution', fontsize=14, fontweight='bold')
    plt.ylim(0, max(error_percentages) * 1.15)  # Add space for labels
    plt.grid(axis='y', alpha=0.3)
    plt.tight_layout()
    plt.savefig('results/problem8_minute_error_distribution.png', dpi=150)
    print('\nMinute error distribution saved to: results/problem8_minute_error_distribution.png')
    plt.close()
    
    # Save results
    os.makedirs('results', exist_ok=True)
    with open('results/problem8_analysis.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Metric', 'Value'])
        writer.writerow(['Total Samples', total])
        writer.writerow(['Exact Accuracy (%)', f'{exact_acc:.2f}'])
        writer.writerow([f'Accuracy ±{minute_margin}min (%)', f'{margin_acc:.2f}'])
        writer.writerow(['Avg Hour Error', f'{avg_hour_err:.2f}'])
        writer.writerow(['Avg Minute Error', f'{avg_minute_err:.2f}'])
    
    print('Results saved to: results/problem8_analysis.csv')
    
    return margin_acc

if __name__ == '__main__':
    # Problem 4: Generate dataset
    print('='*60)
    print('Problem 4: Generate dataset')
    print('='*60)
    generate_dataset(num_images=10000)
    
    # Set device
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f'Using device: {device}\n')
    
    # Data transforms (ImageNet normalization for pretrained model)
    transform = transforms.Compose([
        transforms.ToPILImage(),
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
    ])
    
    # Create datasets
    train_dataset = ClockDataset('dataset/train', transform=transform)
    test_dataset = ClockDataset('dataset/test', transform=transform)
    
    # Create data loaders
    batch_size = 32
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True, num_workers=4)
    test_loader = DataLoader(test_dataset, batch_size=batch_size, shuffle=False, num_workers=4)
    
    print(f'Train dataset: {len(train_dataset)} images')
    print(f'Test dataset: {len(test_dataset)} images')
    
    # Problem 5: Create CNN model (ResNet18 with pretrained weights)
    print('\n'+'='*60)
    print('PROBLEM 5: CNN Architecture')
    print('='*60)
    model = ClockResNet(pretrained=True)
    
    # Problem 6: Train the model
    print('\n'+'='*60)
    print('PROBLEM 6: Training CNN Network')
    print('='*60)
    train_model(model, train_loader, test_loader, num_epochs=30, lr=0.001, device=device)
    
    # Load best model
    print('Loading best model...')
    model.load_state_dict(torch.load('models/best_clock_model.pth'))
    print('Model loaded from: models/best_clock_model.pth\n')
    
    # Problem 7: Test single image prediction
    print('='*60)
    print('PROBLEM 7: Testing on Single Images')
    print('='*60)
    test_image_paths = [f'dataset/test/{f}' for f in os.listdir('dataset/test') if f.endswith('.jpg')][:5]
    
    for img_path in test_image_paths:
        hour, minute = predict_single_image(model, img_path, device=device)
        # Extract true values from filename
        filename = os.path.basename(img_path)
        true_h = int(filename.split('_')[2][1:])
        true_m = int(filename.split('_')[3][1:].split('.')[0])
        print(f'Image: {filename}')
        print(f'  True: {true_h:02d}:{true_m:02d} | Predicted: {hour:02d}:{minute:02d}')
    print()
    
    # Problem 8: Accuracy analysis with error margin
    print('='*60)
    print('PROBLEM 8: Accuracy Analysis')
    print('='*60)
    accuracy = evaluate_model_with_margin(model, test_loader, minute_margin=5, device=device)
    
    print(f'Final Accuracy (±5min margin): {accuracy:.2f}%')
    print('Model saved: models/best_clock_model.pth')
    print('Results saved: results/problem8_analysis.csv')
