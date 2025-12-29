import os
from pathlib import Path
from flask import Flask
from src.config import Config
from sqlalchemy import create_engine

# Models
from src.imgrep.imgrep import ImGrep

# Routes
from src.routes.image_upload import image_upload_bp
from src.routes.search import search_bp
from src.routes.user import user_bp
from src.routes.label import label_bp
from src.routes.get_caption import get_caption

# Extras
from src.config import Config
from src.utils.logger import logger


os.environ['MKL_NUM_THREADS'] = '1'
os.environ['OMP_NUM_THREADS'] = '1'
os.environ["KMP_DUPLICATE_LIB_OK"]="TRUE"

app: Flask = Flask(__name__)
app.config.from_object(Config)

# Create storage directory if it doesn't exist
Config.STORAGE_DIR.mkdir(exist_ok=True)


# Check SQLite database connection
def check_db_connection() -> None:
    try:
        engine = create_engine(Config.DATABASE_URL)
        with engine.connect():
            logger.info(f"Local db : SQLite database connected at {Config.SQLITE_DB_PATH}")
    except Exception as e:
        logger.error(f"Local db : SQLite connection failed: {str(e)}")
        raise


# Loading the models
logger.info("Loading ImGrep Model")
# NOTE(slok): Download these files from drive (pinned in discord)
app.imgrep = ImGrep(
    "assets/vocabs.json", "assets/best_model.pt",
    "assets/ocr_weights.pth", "assets/craft_mlt_25k.pth",
    "assets/captioner_weights.pth.tar", "assets/vocab.pkl"
) # type: ignore
logger.info("Loaded ImGrep Model")

# Register blueprints
app.register_blueprint(image_upload_bp, url_prefix="/api")
app.register_blueprint(user_bp, url_prefix="/api")
app.register_blueprint(search_bp, url_prefix="/api")
app.register_blueprint(label_bp, url_prefix="/api")
app.register_blueprint(get_caption, url_prefix="/api")


@app.route("/test")
def hello_world() -> str:
    return "hello world"


# Global error handler
# NOTE(slok): Removing error handler cuz it makes harder to debug
# @app.errorhandler(Exception)
# def handle_error(error: Exception) -> tuple[Response, int]:
#     logger.error(f"Unexpected error: {str(error)}")
#     return jsonify({"status": "error", "message": "An unexpected error occurred"}), 500


# Run via: uv run main.py
if __name__ == "__main__":
    logger.debug("Starting Imgrep backend")
    check_db_connection()
    if Config.DEBUG:
        logger.info(f"Running Imgrep Backend in {Config.SERVER_IP}:{Config.PORT} with hot reloading")
    app.run(debug=Config.DEBUG, host=Config.SERVER_IP, port=Config.PORT)