import os
import numpy as np
from PIL import Image

import torch
from torch.utils.data import Dataset


class SegposeDataset(Dataset):
    def __init__(self, df, image_dir, mask_dir, image_transform, mask_transform):
        self.df = df
        self.image_dir = image_dir
        self.mask_dir = mask_dir
        self.image_transform = image_transform
        self.mask_transform = mask_transform

        self.label2index = {'hair': 1, 'skin': 2, 'nose': 3}
        self.df['id'] = [str(x).zfill(5) for x in range(1, 4991)] 
        
    def __len__(self):
        return len(self.df)
        
    def __getitem__(self, idx):
        row = self.df.loc[idx]
        
        # image
        image_name = row['id'] + '.jpg'
        image_path = os.path.join(self.image_dir, image_name)
        image = Image.open(image_path).convert('RGB')
        
        # mask
        mask = np.zeros((512, 512), dtype=np.uint8)
        base_name = os.path.splitext(image_name)[0]
        for label in ['hair', 'skin', 'nose']:
            mask_path = os.path.join(self.mask_dir, f'{base_name}_{label}.png')
            
            if os.path.exists(mask_path):
                part_mask = Image.open(mask_path).convert('L') # 0, 255
                part_mask = np.array(part_mask)
                mask[part_mask == 255] = self.label2index[label]
            else:
                AssertionError(f'{label} mask is empty. path: {mask_path}')

        # transform
        image = self.image_transform(image)
        mask = self.mask_transform(Image.fromarray(mask))
        mask = torch.from_numpy(np.array(mask))
        mask = torch.squeeze(mask, dim=0).long()

        # pose
        label = row[['Yaw', 'Pitch', 'Roll']].to_numpy().astype(float)
        label /= 90. # normalize
        label = torch.from_numpy(label).float()
        
        return image, mask, label

