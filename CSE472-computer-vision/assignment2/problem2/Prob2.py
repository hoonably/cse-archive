from model import *
import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np
import torchvision
import tqdm
from torch.utils.data import Dataset
from torch.utils.data import DataLoader
import cv2
import glob
import pandas
# from google.colab.patches import cv2_imshow
from PIL import Image
import torchvision.transforms as transforms
from torchvision.utils import save_image
from torch.autograd import Variable

device = 'cuda:0'

def weights_init_normal(m):
    classname = m.__class__.__name__
    if classname.find("Conv") != -1:
        nn.init.normal_(m.weight.data, 0.0, 0.02)
    elif classname.find("BatchNorm2d") != -1:
        nn.init.normal_(m.weight.data, 1.0, 0.02)
        nn.init.constant_(m.bias.data, 0.0)

class FaceDataset(Dataset):
    def __init__(self, root, transforms_=None, img_size=128, mask_size=64, method="train"):
        self.transform = transforms.Compose(transforms_)
        self.img_size = img_size
        self.mask_size = mask_size
        self.mode = method
        self.root = root
        self.files = sorted(glob.glob("%s/*.jpg" % root))
        self.files = self.files[:-4000] if self.mode == "train" else self.files[-4000:]

    def apply_random_mask(self, img):
        """Randomly masks image"""
        y1, x1 = np.random.randint(0, self.img_size - self.mask_size, 2)
        y2, x2 = y1 + self.mask_size, x1 + self.mask_size
        masked_part = img[:, y1:y2, x1:x2]
        masked_img = img.clone()
        masked_img[:, y1:y2, x1:x2] = 1
        return masked_img, masked_part

    def apply_center_mask(self, img):
        """Mask center part of image"""
        # Get upper-left pixel coordinate
        i = (self.img_size - self.mask_size) // 2
        masked_img = img.clone()
        masked_img[:, i : i + self.mask_size, i : i + self.mask_size] = 1
        return masked_img, i

    def __getitem__(self, index):
        img = Image.open(self.files[index % len(self.files)])
        img = self.transform(img)
        if self.mode == "train":
            # For training data perform random mask
            masked_img, aux = self.apply_random_mask(img)
        else:
            # For test data mask the center of the image
            masked_img, aux = self.apply_center_mask(img)
        return img, masked_img, aux

    def __len__(self):
        return len(self.files)

#! Trainer Implementation ==============================================================================
import torch.optim as optim
class Trainer(object):
    def __init__(self, epochs, batch_size, lr):
        self.epochs = epochs
        self.batch_size = batch_size
        self.lr = lr

        # Initialize Generator
        self.generator = Generator()
        self.generator.apply(weights_init_normal)
        self.generator = self.generator.to(device)
        
        # Loss function
        self.criterion = nn.MSELoss()
        
        # Optimizer
        self.optimizer = optim.Adam(self.generator.parameters(), lr=self.lr, betas=(0.5, 0.999))

        # Transforms
        transforms_ = [
            transforms.Resize((128, 128), Image.BICUBIC),
            transforms.ToTensor(),
            transforms.Normalize((0.5, 0.5, 0.5), (0.5, 0.5, 0.5))
        ]
        
        # Training dataset
        dataset = FaceDataset(
            root='./train',
            method='train',
            transforms_=transforms_
        )
        
        self.train_dataloader = DataLoader(
            dataset,
            batch_size=self.batch_size,
            shuffle=True,
            num_workers=8
        )
        
    def train(self):

        print("Starting Training")

        for epoch in range(self.epochs):
            epoch_loss = 0.0
            self.generator.train()
            
            for i, (imgs, masked_imgs, masked_parts) in enumerate(self.train_dataloader):
                # Move to device
                imgs = imgs.to(device)
                masked_imgs = masked_imgs.to(device)
                masked_parts = masked_parts.to(device)
                
                # Zero gradients
                self.optimizer.zero_grad()
                
                # Generate inpainted images
                gen_imgs = self.generator(masked_imgs)
                
                # Calculate L2 loss
                loss = self.criterion(gen_imgs, masked_parts)
                
                # Backward and optimize
                loss.backward()
                self.optimizer.step()
                
                epoch_loss += loss.item()
                
            avg_loss = epoch_loss / len(self.train_dataloader)
            print(f'Epoch [{epoch+1}/{self.epochs}] - Loss: {avg_loss:.4f}')
        
        # Save trained model
        torch.save(self.generator.state_dict(), 'Prob2.pth')
        print('Training completed. Model saved to Prob2.pth')

#! ==============================================================================================================

class Tester(object):
    def __init__(self, batch_size):
        self._build_model()
        transforms_ = [transforms.Resize((128, 128), Image.BICUBIC), transforms.ToTensor(), transforms.Normalize((0.5, 0.5, 0.5), (0.5, 0.5, 0.5))]
        dataset = FaceDataset(root='./test', method='test', transforms_=transforms_)
        self.root = dataset.root        
        self.test_dataloader = DataLoader(dataset, batch_size=6, shuffle=False)

        print("Testing...")

    def _build_model(self):
        gnet = Generator()
        self.gnet = gnet.to(device)
        self.gnet.load_state_dict(torch.load('Prob2.pth')) # Change this path
        self.gnet.eval()
        print('Finish build model.')

    def test(self):
        Tensor = torch.cuda.FloatTensor
        samples, masked_samples, i = next(iter(self.test_dataloader))
        samples = Variable(samples.type(Tensor))
        masked_samples = Variable(masked_samples.type(Tensor))
        i = i[0].item()  # Upper-left coordinate of mask

        # Generate inpainted image
        gen_mask = self.gnet(masked_samples)
        filled_samples = masked_samples.clone()
        filled_samples[:, :, i : i + 64, i : i + 64] = gen_mask

        # Save sample
        sample = torch.cat((masked_samples.data, filled_samples.data, samples.data), -2)
        save_image(sample, "result.png", nrow=6, normalize=True)   # Change this path

def main():

    epochs = 200
    batchSize = 32
    learningRate = 0.0002

    trainer = Trainer(epochs, batchSize, learningRate)
    trainer.train()

    tester = Tester(batchSize)
    tester.test()

# TODO : 만들어진 체크포인트로 돌리면서 시각화 및 분석

if __name__ == '__main__':
    main()
