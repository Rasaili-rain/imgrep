# caption_generator.py
"""
Reusable image captioning module that can be imported into other projects
"""

import torch
import torch.nn.functional as F
import torchvision.transforms as transforms
from PIL import Image
import pickle
import numpy as np
from .models import CNNEncoder, DecoderWithAttention

class ImageCaptioner:
    def __init__(self, model_path, vocab_path, device=None):
        """
        Initialize the image captioner
        
        Args:
            model_path (str): Path to the trained model checkpoint
            vocab_path (str): Path to the vocabulary file
            device (str, optional): Device to run on ('cuda' or 'cpu')
        """
        self.device = device if device else torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.model_path = model_path
        self.vocab_path = vocab_path
        
        # Image preprocessing transform
        self.transform = transforms.Compose([
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        ])
        
        # Load model and vocabulary
        
        
        
        self._load_vocabulary()
        self._load_model()
       
   
        
        print(f"Image Captioner initialized on {self.device}")
    def _load_model(self):
        """Load the trained model"""
        try:
            # Try loading with weights_only=False first
            checkpoint = torch.load(self.model_path, map_location=str(self.device), weights_only=False)
        except Exception as e:
            print(f"Warning: {e}")
            print("Trying alternative loading method...")
            # Fallback method
            from torch.serialization import safe_globals
            with safe_globals([CNNEncoder, DecoderWithAttention]):
                checkpoint = torch.load(self.model_path, map_location=str(self.device), weights_only=False)
  
        self.encoder = CNNEncoder().to(self.device)
        self.decoder = DecoderWithAttention(
            attention_dim=512,
            embed_dim=512,
            decoder_dim=512,
            vocab_size=len(self.vocab)
        ).to(self.device)

        self.encoder.load_state_dict(checkpoint['encoder_state_dict'])
        self.decoder.load_state_dict(checkpoint['decoder_state_dict'])
        self.encoder.eval()
        self.decoder.eval()
    
    def _load_vocabulary(self):
        """Load vocabulary"""
        with open(self.vocab_path, 'rb') as f:
            self.vocab = pickle.load(f)
        
        self.word_map = self.vocab.stoi
        self.rev_word_map = self.vocab.itos
    
    def _preprocess_image(self, image_input):
        """
        Preprocess image for the model
        
        Args:
            image_input: Can be PIL Image, numpy array, or file path (str)
            
        Returns:
            torch.Tensor: Preprocessed image tensor
        """
        if isinstance(image_input, str):
            # Load from file path
            image = Image.open(image_input).convert('RGB')
        elif isinstance(image_input, np.ndarray):
            # Convert numpy array to PIL Image
            image = Image.fromarray(image_input).convert('RGB')
        elif isinstance(image_input, Image.Image):
            # Already a PIL Image
            image = image_input.convert('RGB')
        else:
            raise ValueError("image_input must be a file path (str), PIL Image, or numpy array")
        
        # Apply transforms and add batch dimension
        image_tensor = self.transform(image).unsqueeze(0).to(self.device)
        return image_tensor
    
    def generate_caption(self, image_input, beam_size=5, max_length=50):
        """
        Generate caption for an image
        
        Args:
            image_input: Image file path (str), PIL Image, or numpy array
            beam_size (int): Beam size for beam search (higher = better quality, slower)
            max_length (int): Maximum caption length
            
        Returns:
            str: Generated caption
        """
        with torch.no_grad():
            # Preprocess image
            image_tensor = self._preprocess_image(image_input)
            
            # Generate caption using beam search
            seq, _ = self._beam_search(image_tensor, beam_size, max_length)
            
            # Convert sequence to caption
            caption_words = [self.rev_word_map[ind] for ind in seq 
                           if ind not in {self.word_map['<SOS>'], self.word_map['<EOS>'], self.word_map['<PAD>']}]
            
            caption = ' '.join(caption_words)
            return caption
    
    def generate_caption_with_attention(self, image_input, beam_size=5, max_length=50):
        """
        Generate caption and return attention weights for visualization
        
        Args:
            image_input: Image file path (str), PIL Image, or numpy array
            beam_size (int): Beam size for beam search
            max_length (int): Maximum caption length
            
        Returns:
            tuple: (caption, attention_weights, word_sequence)
        """
        with torch.no_grad():
            # Preprocess image
            image_tensor = self._preprocess_image(image_input)
            
            # Generate caption with attention
            seq, alphas = self._beam_search(image_tensor, beam_size, max_length)
            
            # Convert sequence to caption
            caption_words = [self.rev_word_map[ind] for ind in seq 
                           if ind not in {self.word_map['<SOS>'], self.word_map['<EOS>'], self.word_map['<PAD>']}]
            
            caption = ' '.join(caption_words)
            return caption, alphas, seq
    
    def _beam_search(self, image_tensor, beam_size=5, max_length=50):
        """Internal beam search implementation"""
        k = beam_size
        vocab_size = len(self.word_map)
        
        # Encode image
        encoder_out = self.encoder(image_tensor)
        enc_image_size = encoder_out.size(1)
        encoder_dim = encoder_out.size(3)
        
        # Flatten and expand for beam search
        encoder_out = encoder_out.view(1, -1, encoder_dim)
        num_pixels = encoder_out.size(1)
        encoder_out = encoder_out.expand(k, num_pixels, encoder_dim)
        
        # Initialize beam search
        k_prev_words = torch.LongTensor([[self.word_map['<SOS>']]] * k).to(self.device)
        seqs = k_prev_words
        top_k_scores = torch.zeros(k, 1).to(self.device)
        seqs_alpha = torch.ones(k, 1, enc_image_size, enc_image_size).to(self.device)
        
        complete_seqs, complete_seqs_alpha, complete_seqs_scores = [], [], []
        step = 1
        h, c = self.decoder.init_hidden_state(encoder_out)
        
        while True:
            embeddings = self.decoder.embedding(k_prev_words).squeeze(1)
            awe, alpha = self.decoder.attention(encoder_out, h)
            alpha = alpha.view(-1, enc_image_size, enc_image_size)
            gate = self.decoder.sigmoid(self.decoder.f_beta(h))
            awe = gate * awe
            h, c = self.decoder.decode_step(torch.cat([embeddings, awe], dim=1), (h, c))
            scores = self.decoder.fc(h)
            scores = F.log_softmax(scores, dim=1)
            scores = top_k_scores.expand_as(scores) + scores
            
            if step == 1:
                top_k_scores, top_k_words = scores[0].topk(k, 0, True, True)
            else:
                top_k_scores, top_k_words = scores.view(-1).topk(k, 0, True, True)
            
            prev_word_inds = top_k_words // vocab_size
            next_word_inds = top_k_words % vocab_size
            
            seqs = torch.cat([seqs[prev_word_inds], next_word_inds.unsqueeze(1)], dim=1)
            seqs_alpha = torch.cat([seqs_alpha[prev_word_inds], alpha[prev_word_inds].unsqueeze(1)], dim=1)
            
            incomplete_inds = [ind for ind, next_word in enumerate(next_word_inds) if next_word != self.word_map['<EOS>']]
            complete_inds = list(set(range(len(next_word_inds))) - set(incomplete_inds))
            
            if len(complete_inds) > 0:
                complete_seqs.extend(seqs[complete_inds].tolist())
                complete_seqs_alpha.extend(seqs_alpha[complete_inds].tolist())
                complete_seqs_scores.extend(top_k_scores[complete_inds])
            k -= len(complete_inds)
            
            if k == 0:
                break
                
            seqs = seqs[incomplete_inds]
            seqs_alpha = seqs_alpha[incomplete_inds]
            h = h[prev_word_inds[incomplete_inds]]
            c = c[prev_word_inds[incomplete_inds]]
            encoder_out = encoder_out[prev_word_inds[incomplete_inds]]
            top_k_scores = top_k_scores[incomplete_inds].unsqueeze(1)
            k_prev_words = next_word_inds[incomplete_inds].unsqueeze(1)
            
            if step > max_length:
                break
            step += 1
        
        # Return best sequence
        if complete_seqs_scores:
            i = complete_seqs_scores.index(max(complete_seqs_scores))
            return complete_seqs[i], complete_seqs_alpha[i]
        else:
            # Fallback if no complete sequences
            return seqs[0].tolist(), seqs_alpha[0].tolist()

