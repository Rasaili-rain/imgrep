import torch
from PIL import Image
from facenet_pytorch import MTCNN, InceptionResnetV1
import numpy as np
from typing import Optional


class FaceRecognitionModel:
    def __init__(self):
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        self.mtcnn = MTCNN(image_size=160, margin=20, keep_all=False, device=self.device)
        self.model = InceptionResnetV1(pretrained='vggface2').eval().to(self.device)

    def extract_face_embedding(self, image: Image.Image) -> Optional[np.ndarray]:
        face = self.mtcnn(image)

        # If there is no face in image then return none
        if face is None:
            return None

        face = face.unsqueeze(0).to(self.device)
        with torch.no_grad():
            embedding = self.model(face).cpu().numpy()

        return embedding


"""
    def predict_identity(self, embedding, known_embeddings, known_labels, threshold=0.7):
        if len(known_embeddings) == 0:
            return "Unknown", 0.0

        sims = cosine_similarity(embedding, known_embeddings)
        best_idx = np.argmax(sims)
        best_score = sims[0][best_idx]

        if best_score > threshold:
            return known_labels[best_idx], best_score
        else:
            return "Unknown", best_score
"""
