import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision


import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision


class SegposeNet(nn.Module):
    def __init__(self, num_seg_classes, num_pose_classes):
        super(SegposeNet, self).__init__()
        resnet = torchvision.models.resnet34(weights=torchvision.models.ResNet34_Weights.DEFAULT)

        # Backbone (Encoder with intermediate outputs for skip connections)
        self.encoder1 = nn.Sequential(*list(resnet.children())[:4])   # [B, 64, H/4, W/4]
        self.encoder2 = resnet.layer1                                 # [B, 64, H/8, W/8]
        self.encoder3 = resnet.layer2                                 # [B, 128, H/16, W/16]
        self.encoder4 = resnet.layer3                                 # [B, 256, H/32, W/32]
        self.encoder5 = resnet.layer4                                 # [B, 512, H/32, W/32]

        # Decoder (U-Net style with skip connections)
        self.up4 = self._up_block(512, 256)       # x5 → x4 (H/16)
        self.up3 = self._up_block(256 + 256, 128) # d4 + x4 → x3 (H/8)
        self.up2 = self._up_block(128 + 128, 64)  # d3 + x3 → x2 (H/4)
        self.up1 = self._up_block(64 + 64, 64)    # d2 + x2 → x1 (H/2)

        # Final Segmentation Head
        self.seg_head = nn.Sequential(
            nn.Conv2d(64 + 64, 64, kernel_size=3, padding=1),  # After final concat with x1
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            nn.Conv2d(64, num_seg_classes, kernel_size=1),    # Final Output Channels = num_seg_classes
            nn.Upsample(scale_factor=4, mode='bilinear', align_corners=False)  # Restore original image size
        )

        # Pose Estimation Head (Yaw, Pitch, Roll Regression)
        self.pose_head = nn.Sequential(
            nn.AdaptiveAvgPool2d(1),  # [B, 512, 1, 1]
            nn.Flatten(),             # [B, 512]
            nn.Linear(512, 256),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(256, num_pose_classes)  # Output: [B, 3] for yaw, pitch, roll
        )

    def _up_block(self, in_channels, out_channels):
        return nn.Sequential(
            nn.ConvTranspose2d(in_channels, out_channels, kernel_size=2, stride=2),
            nn.BatchNorm2d(out_channels),
            nn.ReLU(inplace=True),
            nn.Conv2d(out_channels, out_channels, kernel_size=3, padding=1),
            nn.BatchNorm2d(out_channels),
            nn.ReLU(inplace=True)
        )

    def forward(self, x):
        # Encoder
        x1 = self.encoder1(x)  # [B, 64, H/4, W/4]
        x2 = self.encoder2(x1) # [B, 64, H/8, W/8]
        x3 = self.encoder3(x2) # [B, 128, H/16, W/16]
        x4 = self.encoder4(x3) # [B, 256, H/32, W/32]
        x5 = self.encoder5(x4) # [B, 512, H/32, W/32]

        # Decoder with Skip Connections
        d4 = self.up4(x5)               # [B, 256, H/16, W/16]
        d4 = torch.cat([d4, x4], dim=1)  # [B, 256+256, H/16, W/16]

        d3 = self.up3(d4)                # [B, 128, H/8, W/8]
        d3 = torch.cat([d3, x3], dim=1)  # [B, 128+128, H/8, W/8]

        d2 = self.up2(d3)                # [B, 64, H/4, W/4]
        d2 = torch.cat([d2, x2], dim=1)  # [B, 64+64, H/4, W/4]

        d1 = self.up1(d2)                # [B, 64, H/2, W/2]
        x1_up = F.interpolate(x1, size=d1.shape[2:], mode='bilinear', align_corners=False)  # [B, 64, H/2, W/2]
        d1 = torch.cat([d1, x1_up], dim=1)  # [B, 64+64, H/2, W/2]

        # Segmentation Output
        seg_out = self.seg_head(d1)      # [B, num_seg_classes, H, W]
        seg_out = F.interpolate(seg_out, size=x.shape[2:], mode='bilinear', align_corners=False)  # Match input image size

        # Pose Regression Output
        pose_out = self.pose_head(x5)    # [B, 3] for yaw, pitch, roll

        return seg_out, pose_out

