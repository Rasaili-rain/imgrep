import torch
from torchvision import transforms
import json
from PIL import Image
import faiss
import os
import numpy as np

from .models.image_encoder import ResNetImageEncoder
from .models.text_encoder import TransformerTextEncoder
from .models.dual_encoder import ImageTextRetrievalModel
from .data.tokenizer import CaptionTokenizer
from .ocr.ocr import OCR
from .caption_model.captioner import ImageCaptioner
from .face_recog.face_recog import FaceRecognitionModel

class ImGrep:
    def __init__(
        self,
        vocabs: str,
        weights: str,
        ocr_weights: str,
        craft_weights: str,
        captioner_weights:str,
        captioner_vocab: str,
        tokenizer_length: int = 20,
        embedding_dim: int = 256
    ):
        self.tokenizer_length = tokenizer_length
        self.embedding_dim = embedding_dim

        self.transform = transforms.Compose([
            transforms.Resize((128, 128)),
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
        ])

        self.__load_tokenizer(vocabs)
        self.__load_encoders(tokenizer_length, embedding_dim)
        self.__load_model(weights, embedding_dim)

        # Loading other models
        self.ocr = OCR(ocr_weights, craft_weights)
        self.captioner = ImageCaptioner(captioner_weights, captioner_vocab)
        self.face_recog = FaceRecognitionModel()

    def __load_tokenizer(self, vocabs: str):
        # Creating the tokenizer
        with open(vocabs, "r") as f:
            captions = json.load(f)
            all_captions = [a["caption"] for a in captions["annotations"]]
        self.tokenizer = CaptionTokenizer(all_captions)

    def __load_encoders(self, tokenizer_length: int, embedding_dim: int):
        # Loading the Image and Text Encoders
        self.image_encoder = ResNetImageEncoder(output_dim = embedding_dim)
        self.text_encoder = TransformerTextEncoder(
            vocab_size = self.tokenizer.vocab_size(),
            embed_dim = embedding_dim,
            max_len = tokenizer_length
        )

    def __load_model(self, weights: str, embedding_dim: int):
        # Creating the model
        self.model = ImageTextRetrievalModel(
            embed_dim = embedding_dim,
            image_encoder = self.image_encoder,
            text_encoder = self.text_encoder
        )

        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

        # Load the Model
        checkpoint = torch.load(weights, map_location = self.device)
        if "model_state_dict" in checkpoint:
            self.model.load_state_dict(checkpoint["model_state_dict"])
            print(f"Loaded model (epoch {checkpoint.get('epoch', 'unknown')})")
        else:
            self.model.load_state_dict(checkpoint)
            print("Loaded final model")

        self.model.to(self.device)
        self.model.eval()

    def encode_text(self, text: str) -> torch.Tensor:
        tokens = self.tokenizer.encode(text, self.tokenizer_length)
        tokens = torch.tensor(tokens, dtype = torch.long).unsqueeze(0).to(self.device)

        with torch.no_grad():
            _, text_feat = self.model(
                torch.zeros(1, 3, 128, 128, device = self.device),
                tokens
            )
            text_feat = torch.nn.functional.normalize(text_feat, dim = -1)
        return text_feat.squeeze(0).cpu()

    def encode_image(self, image: Image) -> torch.Tensor:
        with torch.no_grad():
            img_tensor = self.transform(image).unsqueeze(0).to(self.device)
            img_feat, _ = self.model(img_tensor, torch.zeros(
                1, self.tokenizer_length,
                dtype = torch.long, device = self.device
            ))
            img_feat = torch.nn.functional.normalize(img_feat, dim = -1)
        return img_feat.squeeze(0).cpu()


# NOTE(slok): This is a example use case

if __name__ == "__main__":
    image_dir = "images"
    images = os.listdir(image_dir)

    imgrep = ImGrep("vocabs.json", "best_model.pt")

    # Creating faiss index of 256 cuz the size of our embeddings is 256
    index = faiss.IndexFlatL2(256)

    for image_name in images:
        image_path = f"{image_dir}/{image_name}"
        image = Image.open(image_path).convert("RGB")
        image_features = imgrep.encode_image(image).numpy().astype("float32")
        image_features = np.expand_dims(image_features, axis=0)
        index.add(image_features)
        print(f"DONE: {image_name}")

    while True:
        query = input(">")

        if (query == "q"):
            break

        text_features = imgrep.encode_text(query).numpy().astype("float32")
        text_features = np.expand_dims(text_features, axis=0)
        dist, indices = index.search(text_features, k = 5)

        for i in indices[-1]:
            print(images[i])
