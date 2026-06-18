import os
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision.transforms as T
import pandas as pd
import numpy as np
import cv2
from PIL import Image
from torch.utils.data import DataLoader, random_split

from model import SegposeNet
from dataset import SegposeDataset

# data loading
device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
df = pd.read_csv('data.csv')

#! Hyperparameter - Image size
IMAGE_SIZE = (256, 256)

image_transform = T.Compose([
    T.Resize(IMAGE_SIZE),
    T.ToTensor(),
    # Normalize input images using ImageNet mean and std required by torchvision pretrained models
    T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
])
mask_transform = T.Compose([
    T.Resize(IMAGE_SIZE, interpolation=T.InterpolationMode.NEAREST),
])

dataset = SegposeDataset(df, 'train/images', 'train/masks', image_transform, mask_transform)
from torch.utils.data import random_split

#! Hyperparameter - Train/Val split ratio
TRAIN_RATIO = 0.8

RANDOM_SEED = 42
torch.manual_seed(RANDOM_SEED)
train_dataset, val_dataset = random_split(dataset, [int(TRAIN_RATIO*len(dataset)), len(dataset)-int(TRAIN_RATIO*len(dataset))])

#! Hyperparameter - Batch size
BATCH_SIZE = 8
train_dataloader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True, num_workers=8)
val_dataloader = DataLoader(val_dataset, batch_size=BATCH_SIZE, shuffle=False, num_workers=8)

numObj = 4  # background, hair, skin, nose
model = SegposeNet(num_seg_classes=numObj, num_pose_classes=3)
model.to(device)
model.train()

# criterion = torch.nn.CrossEntropyLoss()
seg_criterion = torch.nn.CrossEntropyLoss()
pose_criterion = torch.nn.MSELoss()

#! Hyperparameter - Learning rate
LEARNING_RATE = 0.001
optimizer = torch.optim.Adam(model.parameters(), lr=LEARNING_RATE)

#! Hyperparameter - Number of epochs
NUM_EPOCHS = 10

# Training loop with multi-task loss balancing using EMA
seg_ema = None
pose_ema = None
alpha = 0.99
eps = 1e-8

for epoch in range(NUM_EPOCHS):
    model.train()
    train_seg, train_pose = 0.0, 0.0
    
    for images, masks, poses in train_dataloader:
        images = images.to(device)
        masks  = masks.to(device)
        poses  = poses.to(device)

        pred_masks, pred_poses = model(images)

        seg_loss  = seg_criterion(pred_masks, masks)
        pose_loss = pose_criterion(pred_poses, poses)

        # EMA update (train only)
        if seg_ema is None:
            seg_ema = seg_loss.detach()
            pose_ema = pose_loss.detach()
        else:
            seg_ema  = alpha * seg_ema  + (1 - alpha) * seg_loss.detach()
            pose_ema = alpha * pose_ema + (1 - alpha) * pose_loss.detach()

        # Multi-task loss balancing (normalized by running mean)
        loss = seg_loss / (seg_ema + eps) + pose_loss / (pose_ema + eps)

        optimizer.zero_grad()
        loss.backward()
        optimizer.step()

        train_seg   += seg_loss.item()
        train_pose  += pose_loss.item()

    model.eval()
    val_seg, val_pose = 0.0, 0.0
    with torch.no_grad():
        for images, masks, poses in val_dataloader:
            images = images.to(device)
            masks  = masks.to(device)
            poses  = poses.to(device)

            pred_masks, pred_poses = model(images)

            seg_loss  = seg_criterion(pred_masks, masks)
            pose_loss = pose_criterion(pred_poses, poses)

            # use train EMA as scale
            loss = seg_loss / (seg_ema + eps) + pose_loss / (pose_ema + eps)

            val_seg   += seg_loss.item()
            val_pose  += pose_loss.item()

    print(
        f"Epoch [{epoch+1}/{NUM_EPOCHS}] | "
        f"Train: "
        f"seg={train_seg/len(train_dataloader):.4f}, "
        f"pose={train_pose/len(train_dataloader):.4f} | "
        f"Val: "
        f"seg={val_seg/len(val_dataloader):.4f}, "
        f"pose={val_pose/len(val_dataloader):.4f}"
    )

torch.save(model.state_dict(), "Prob1.pth")


"""

# Inference

python inference.py --image test/images --weights Prob1.pth --device cuda --save output

"""
