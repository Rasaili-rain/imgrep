import os
import string
import torch
import torch.nn as nn
import numpy as np
import cv2
from PIL import Image
from torchvision import transforms
from collections import OrderedDict

from .crnn import CRNN
from .craft.craft import CRAFT
from .craft.craft_utils import getDetBoxes, adjustResultCoordinates
from .craft.imgproc import loadImage, resize_aspect_ratio, normalizeMeanVariance


class OCR:
    def __init__( self, crnn_weights: str, craft_weights: str, image_size: tuple[int, int] = (128, 32), save_word_image: bool = False):
        self.target_size = image_size
        self.save_word = save_word_image

        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

        # Charset setup
        CHARACTERS = string.digits + string.ascii_letters + ' '
        self.BLANK_LABEL = '-'  # CTC blank
        self.VOCAB = list(CHARACTERS) + [self.BLANK_LABEL]
        self.char_to_idx = {char: i for i, char in enumerate(self.VOCAB)}
        self.idx_to_char = {i: char for i, char in enumerate(self.VOCAB)}
        self.num_classes = len(self.VOCAB)

        # Load CRNN model
        self.crnn = CRNN(img_height=image_size[1], num_classes=self.num_classes).to(self.device)
        crnn_ckpt = torch.load(crnn_weights, map_location=self.device)
        self.crnn.load_state_dict(crnn_ckpt['model_state_dict'])
        self.crnn.eval()

        # Load CRAFT model
        self.craft = self.__load_craft_model(craft_weights)

        # Transformation pipeline
        self.transform = transforms.Compose([
            transforms.Grayscale(num_output_channels=1),
            transforms.Resize((image_size[1], image_size[0])),
            transforms.ToTensor(),
            transforms.Normalize((0.5,), (0.5,))
        ])

    def __load_craft_model(self, model_path: str):
        net = CRAFT()
        state_dict = torch.load(model_path, map_location=self.device)
        new_state_dict = OrderedDict()
        for k, v in state_dict.items():
            name = k.replace("module.", "")
            new_state_dict[name] = v
        net.load_state_dict(new_state_dict)
        net.eval()
        if self.device.type == 'cuda':
            net = net.cuda()
        return net

    def __detect_words(self, image: np.ndarray) -> list[tuple[int, int, int, int]]:
        """Detect bounding boxes for text regions using CRAFT."""
        img_resized, target_ratio, _ = resize_aspect_ratio(image, 1280, interpolation=cv2.INTER_LINEAR, mag_ratio=1.5)
        ratio_h = ratio_w = 1 / target_ratio

        x = normalizeMeanVariance(img_resized)
        x = torch.from_numpy(x).permute(2, 0, 1).unsqueeze(0)
        if self.device.type == 'cuda':
            x = x.cuda()

        with torch.no_grad():
            y, _ = self.craft(x)

        score_text = y[0, :, :, 0].cpu().data.numpy()
        score_link = y[0, :, :, 1].cpu().data.numpy()

        boxes, _ = getDetBoxes(score_text, score_link, text_threshold=0.7, link_threshold=0.4, low_text=0.4)
        boxes = adjustResultCoordinates(boxes, ratio_w, ratio_h)

        rects = []
        for box in boxes:
            if box is None or len(box) == 0:
                continue
            x_min = min(pt[0] for pt in box)
            y_min = min(pt[1] for pt in box)
            x_max = max(pt[0] for pt in box)
            y_max = max(pt[1] for pt in box)
            rects.append((x_min, y_min, x_max - x_min, y_max - y_min))

        rects = sorted(rects, key=lambda b: (b[1] // 20, b[0]))  # Sort by row then column
        return rects

    def __extract_word_images(self, image: np.ndarray, boxes: list[tuple[int, int, int, int]]):
        word_images = []
        h_img, w_img = image.shape[:2]
        target_height = self.target_size[1]  # example: 32

        for i, box in enumerate(boxes):
            # Ensure box coordinates are integers
            x, y, w, h = [int(coord) for coord in box]

            if x + w > w_img:
                w = w_img - x
            if y + h > h_img:
                h = h_img - y

            if w <= 0 or h <= 0:
                # Invalid box size, skip
                continue

            # Crop the image
            word_img = image[y:y+h, x:x+w]

            # Check if word_img is empty before processing
            if word_img.size == 0:
                continue

            # If input image is color (3 channels), convert to grayscale
            if len(word_img.shape) == 3:
                word_img = cv2.cvtColor(word_img, cv2.COLOR_BGR2GRAY)

            # Resize proportionally to target height
            scale = target_height / h
            new_w = int(w * scale)
            resized = cv2.resize(word_img, (new_w, target_height), interpolation=cv2.INTER_CUBIC)

            pil_image = Image.fromarray(resized)
            word_images.append(pil_image)

        return word_images

    def __recognize_word(self, image: Image.Image) -> str:
        tensor = self.transform(image).unsqueeze(0).to(self.device)
        with torch.no_grad():
            log_probs = self.crnn(tensor)
            log_probs = log_probs.permute(1, 0, 2)
            probs = log_probs.softmax(2)
            _, preds = probs.max(2)
            preds = preds.squeeze(1)
        decoded = self.ctc_greedy_decoder(preds, blank=len(self.VOCAB) - 1)
        return ''.join(self.idx_to_char[i] for i in decoded)

    def ctc_greedy_decoder(self, preds, blank):
        pred_indices = preds.cpu().numpy().tolist()
        decoded = []
        prev = blank
        for p in pred_indices:
            if p != blank and p != prev:
                decoded.append(p)
            prev = p
        return decoded

    def extract_text(self, pil_image: Image.Image, save_words: bool = False, save_dir: str = "words") -> list[str]:
        gray = np.array(pil_image.convert("RGB"))
        boxes = self.__detect_words(gray)
        word_images = self.__extract_word_images(gray, boxes)

        # Save the word images if requested
        if save_words:
            import os
            os.makedirs(save_dir, exist_ok=True)
            for i, word_img in enumerate(word_images):
                filename = os.path.join(save_dir, f"word_{i+1}.png")
                word_img.save(filename)

        texts = [self.__recognize_word(word_img) for word_img in word_images]
        return texts


# Example use case
if __name__ == "__main__":
    image_path = "test_5.jpg"
    crnn_weights = "ocr_weights.pth"
    craft_weights = "craft_mlt_25k.pth"

    image = Image.open(image_path).convert("RGB")

    ocr = OCR(crnn_weights=crnn_weights, craft_weights=craft_weights, save_word_image=True)
    texts = ocr.extract_text(image, save_words=True)
    print("[RESULT]")
    for text in texts:
        print(text)
    print(f"\nTotal words: {len(texts)}")
