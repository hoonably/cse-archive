import os
import math
import argparse
import numpy as np
import pandas as pd
import cv2
from PIL import Image
import torch
import torchvision.transforms as T
from torchvision.utils import save_image

from model import SegposeNet

parser = argparse.ArgumentParser()
parser.add_argument('--image', help='input test image directory')
parser.add_argument('--weights', help='input model path (.pth)')
parser.add_argument('--device', help='input cuda device num or cpu (cuda, cuda:0, cpu ...)', default='cuda:0')
parser.add_argument('--save', help='input save directory', default='./output/')

args = parser.parse_args()


COLOR_MAP = {
    0: [0, 0, 0],        
    1: [255, 0, 0],      
    2: [0, 255, 0],      
    3: [0, 0, 255],      
}


def colorize_mask(pred_mask, color_map):
    color_mask = torch.zeros(3, 256, 256, dtype=torch.uint8)
    for label, color, in color_map.items():
        for c in range(3):
            color_mask[c][pred_mask == label] = color[c]
    return color_mask / 255


def visualize_pose(image, yaw, pitch, roll):
    yaw, pitch, roll = map(float, [yaw, pitch, roll])
    start_x, start_y = 10, 30
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 1
    color = (255, 255, 255)
    thickness = 2
    line_height = 50
    
    cv2.putText(image, f"Yaw: {yaw:.1f}", 
                (start_x, start_y + 0*line_height), 
                font, font_scale, color, thickness, cv2.LINE_AA)
    
    cv2.putText(image, f"Pitch: {pitch:.1f}", 
                (start_x, start_y + 1*line_height), 
                font, font_scale, color, thickness, cv2.LINE_AA)
    
    cv2.putText(image, f"Roll: {roll:.1f}", 
                (start_x, start_y + 2*line_height), 
                font, font_scale, color, thickness, cv2.LINE_AA)
    
    return image


def inference(args):
    test_images = sorted(os.listdir(args.image))
    
    transform = T.Compose([
        T.Resize((256, 256)),
        T.ToTensor(),
        T.Normalize(mean=(0.485, 0.456, 0.406), std=(0.229, 0.224, 0.225))
    ])
    

    model = SegposeNet(num_seg_classes=4, num_pose_classes=3).to(args.device)
    model.load_state_dict(torch.load(args.weights, weights_only=False))
    model.eval()

    os.makedirs(args.save, exist_ok=True)
    
    df_pred = pd.DataFrame(columns=['id', 'Yaw', 'Pitch', 'Roll'])
    for i, image_file in enumerate(test_images):
        with torch.no_grad():
            id = image_file.split('_')[0]

            image_path = os.path.join(args.image, image_file)
            image = Image.open(image_path).convert('RGB')
            orig_w, orig_h = image.size  
            
            img_input = transform(image).unsqueeze(0).to(args.device)
            pred_mask, pred_pose = model(img_input)
            pred_mask = torch.argmax(pred_mask, dim=1).detach().cpu().squeeze().numpy()

        # Save Segmentation Visualization
        color_mask = colorize_mask(torch.tensor(pred_mask), COLOR_MAP)
        color_mask_resized = T.Resize((orig_h, orig_w), interpolation=T.InterpolationMode.NEAREST)(color_mask).permute(1, 2, 0) * 255
        color_mask_resized = color_mask_resized.numpy().astype(np.uint8)
        color_mask_resized = np.ascontiguousarray(color_mask_resized)
        seg_save_path = os.path.join(args.save, f"{os.path.splitext(image_file)[0]}_out.jpg")
    
        # Pose Estimation
        yaw, pitch, roll = pred_pose.detach().cpu().squeeze().numpy() * 90.0 # denormalize
        df_pred.loc[i] = [id, yaw, pitch, roll]
        visualized_image = visualize_pose(color_mask_resized, yaw, pitch, roll)
        
        cv2.imwrite(seg_save_path, visualized_image)
            
    df_pred.to_csv('pred.csv', index=False)

                        
if __name__ == '__main__':
    print("Inference started.")
    inference(args)
    