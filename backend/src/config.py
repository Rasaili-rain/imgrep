import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()


class Config:
    DEBUG: bool = True
    PORT: int = 5000
    SERVER_IP: str = "0.0.0.0"

    TOKENIZER_LENGTH = 20
    EMBEDDING_DIM = 256
    FACE_EMBEDDING_DIM = 512

    FAISS_DATABASE: str = "faiss_db"
    
    # SQLite database configuration
    STORAGE_DIR: Path = Path("storage")
    SQLITE_DB_PATH: Path = STORAGE_DIR / "imgrep.db"
    DATABASE_URL: str = os.getenv("DATABASE_URL", f"sqlite:///{SQLITE_DB_PATH}")


    ###############################
    #      WEIGHT ADJUSTMENTS     #
    ###############################

    SEARCH_SCORE_THRESHOLD: float = 0.15
    LABEL_SCORE_THRESHOLD: float = 0.5

    EMBEDDING_SEARCH_RANGE: float = 1.5
    OCR_WEIGHT: float = 0.3
    LABEL_WEIGHT: float = 0.5
    DATE_TIME_BOOST_AMOUNT : float = 0.5  