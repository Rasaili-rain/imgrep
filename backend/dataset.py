# dataset.py
import os
import json
import torch
from torch.utils.data import Dataset
from PIL import Image
import pickle
from collections import Counter
import nltk
from nltk.tokenize import word_tokenize

# Download required NLTK data
try:
    nltk.data.find('tokenize/punkt')
except LookupError:
    nltk.download('punkt')

class Vocabulary:
    def __init__(self, freq_threshold=4):
        self.itos = {0: "<PAD>", 1: "<SOS>", 2: "<EOS>", 3: "<UNK>"}
        self.stoi = {"<PAD>": 0, "<SOS>": 1, "<EOS>": 2, "<UNK>": 3}
        self.freq_threshold = freq_threshold

    def __len__(self):
        return len(self.itos)

    @staticmethod
    def tokenizer_eng(text):
        return [tok.lower().strip() for tok in word_tokenize(text)]

    def build_vocabulary(self, sentence_list):
        frequencies = Counter()
        idx = 4

        for sentence in sentence_list:
            for word in self.tokenizer_eng(sentence):
                frequencies[word] += 1

                if frequencies[word] == self.freq_threshold:
                    self.stoi[word] = idx
                    self.itos[idx] = word
                    idx += 1

    def numericalize(self, text):
        tokenized_text = self.tokenizer_eng(text)
        return [
            self.stoi[token] if token in self.stoi else self.stoi["<UNK>"]
            for token in tokenized_text
        ]

class COCODataset(Dataset):
    def __init__(self, root_dir, captions_file, transform=None, freq_threshold=4, vocab=None):
        self.root_dir = root_dir
        self.transform = transform
        
        # Load COCO annotations
        with open(captions_file, 'r') as f:
            self.annotations = json.load(f)
        
        # Extract image info and annotations
        self.images = {img['id']: img for img in self.annotations['images']}
        self.captions = self.annotations['annotations']
        
        # Build or load vocabulary
        if vocab is None:
            self.vocab = Vocabulary(freq_threshold)
            self.build_vocab()
        else:
            self.vocab = vocab
            
    def build_vocab(self):
        print("Building vocabulary...")
        captions_text = [ann['caption'] for ann in self.captions]
        self.vocab.build_vocabulary(captions_text)
        print(f"Vocabulary built with {len(self.vocab)} words")
        
    def save_vocab(self, vocab_path):
        with open(vocab_path, 'wb') as f:
            pickle.dump(self.vocab, f)
            
    @staticmethod
    def load_vocab(vocab_path):
        with open(vocab_path, 'rb') as f:
            return pickle.load(f)
    
    def __len__(self):
        return len(self.captions)
    
    def __getitem__(self, index):
        annotation = self.captions[index]
        caption = annotation['caption']
        img_id = annotation['image_id']
        
        # Get image filename
        img_info = self.images[img_id]
        img_name = img_info['file_name']
        img_path = os.path.join(self.root_dir, img_name)
        
        # Load image
        image = Image.open(img_path).convert("RGB")
        
        if self.transform is not None:
            image = self.transform(image)
            
        # Convert caption to numerical representation
        caption_vec = []
        caption_vec += [self.vocab.stoi["<SOS>"]]
        caption_vec += self.vocab.numericalize(caption)
        caption_vec += [self.vocab.stoi["<EOS>"]]
        
        return image, torch.tensor(caption_vec)

class MyCollate:
    def __init__(self, pad_idx):
        self.pad_idx = pad_idx

    def __call__(self, batch):
        imgs = [item[0].unsqueeze(0) for item in batch]
        imgs = torch.cat(imgs, dim=0)
        
        targets = [item[1] for item in batch]
        lengths = [len(target) for target in targets]
        
        # Pad sequences to same length
        max_len = max(lengths)
        padded_targets = torch.zeros(len(targets), max_len).long()
        
        for idx, target in enumerate(targets):
            padded_targets[idx, :len(target)] = target
            
        return imgs, padded_targets, torch.tensor(lengths)

def get_loader(root_folder, annotation_file, transform, batch_size=32, 
               num_workers=8, shuffle=True, pin_memory=True, vocab_path=None):
    
    # Try to load existing vocabulary
    if vocab_path and os.path.exists(vocab_path):
        print(f"Loading vocabulary from {vocab_path}")
        vocab = COCODataset.load_vocab(vocab_path)
        dataset = COCODataset(root_folder, annotation_file, transform=transform, vocab=vocab)
    else:
        print("Building new vocabulary...")
        dataset = COCODataset(root_folder, annotation_file, transform=transform)
        if vocab_path:
            dataset.save_vocab(vocab_path)
            print(f"Vocabulary saved to {vocab_path}")
    
    pad_idx = dataset.vocab.stoi["<PAD>"]
    
    loader = torch.utils.data.DataLoader(
        dataset=dataset,
        batch_size=batch_size,
        num_workers=num_workers,
        shuffle=shuffle,
        pin_memory=pin_memory,
        collate_fn=MyCollate(pad_idx=pad_idx),
    )
    
    return loader, dataset