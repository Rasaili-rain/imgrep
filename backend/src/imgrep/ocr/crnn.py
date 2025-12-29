import torch
import torch.nn as nn
import torchvision.models as models
import torch.nn.functional as F

class CRNN(nn.Module):
    def __init__(self, img_height=32, num_classes=63, rnn_hidden=256):
        super(CRNN, self).__init__()

        # CNN: feature extractor (simplified)
        self.cnn = nn.Sequential(
            nn.Conv2d(1, 64, kernel_size=3, stride=1, padding=1),  # B x 64 x H x W
            nn.ReLU(),
            nn.MaxPool2d(2, 2),  # B x 64 x H/2 x W/2

            nn.Conv2d(64, 128, 3, 1, 1),  # B x 128 x H/2 x W/2
            nn.ReLU(),
            nn.MaxPool2d(2, 2),  # B x 128 x H/4 x W/4

            nn.Conv2d(128, 256, 3, 1, 1),
            nn.BatchNorm2d(256),
            nn.ReLU(),
            nn.Conv2d(256, 256, 3, 1, 1),
            nn.ReLU(),
            nn.MaxPool2d((2, 1)),  # only downsample height: B x 256 x H/8 x W/4

            nn.Conv2d(256, 512, 3, 1, 1),
            nn.BatchNorm2d(512),
            nn.ReLU(),
            nn.MaxPool2d((2, 1)),  # B x 512 x H/16 x W/4
        )

        # Calculate number of features going into RNN
        cnn_out_channels = 512
        cnn_out_height = img_height // 16

        self.rnn = nn.LSTM(
            input_size=cnn_out_channels * cnn_out_height,  # width-wise sequence input
            hidden_size=rnn_hidden,
            num_layers=2,
            bidirectional=True,
            batch_first=True
        )

        self.fc = nn.Linear(rnn_hidden * 2, num_classes)

    def forward(self, x):
        # x: [B, 1, H, W]
        conv = self.cnn(x)  # [B, C, H', W']
        b, c, h, w = conv.size()

        assert h == 2, "CNN output height must be fixed (got {})".format(h)

        conv = conv.permute(0, 3, 1, 2)  # [B, W', C, H']
        conv = conv.view(b, w, c * h)  # [B, W', C*H']

        rnn_out, _ = self.rnn(conv)  # [B, W', 2*hidden]
        logits = self.fc(rnn_out)    # [B, W', num_classes]
        log_probs = F.log_softmax(logits, dim=2)

        return log_probs


if __name__ == "__main__":
    # Instantiate your CRNN model
    crnn = CRNN()
    crnn.eval()  # turn off dropout/batchnorm randomness

    # Create a dummy input image of shape [batch_size, channels, height, width]
    dummy_img = torch.randn(1, 1, 32, 128)  # B=1, grayscale, 32x128

    # Forward pass through just the CNN
    with torch.no_grad():
        conv_out = crnn.cnn(dummy_img)
        print("CNN output shape:", conv_out.shape)

