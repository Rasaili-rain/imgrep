from datetime import date, datetime
from flask import Blueprint, request, jsonify, Response, current_app
from sqlalchemy import Date, func, and_
from werkzeug.datastructures import FileStorage
from PIL import Image
import numpy as np
import faiss

from src.config import Config
from src.db import ImageTable, get_db_session, Label
from src.utils.logger import logger


image_upload_bp = Blueprint('image_upload', __name__)
ALLOWED_EXTENSIONS: set[str] = {'png', 'jpg', 'jpeg', 'avif'}

def allowed_file(filename: str) -> bool:
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def parse_datetime(datetime_str: str) -> datetime:
    try:
        logger.info(f"datetime received: {datetime_str}")
        return datetime.fromisoformat(datetime_str.replace('Z', '+00:00'))
    except:
        logger.warning("fallback to now()")
        return datetime.now(datetime.timezone.utc)


def parse_float(value_str: str) -> float | None:
    if not value_str:
        return None
    try:
        return float(value_str)
    except:
        return None


@image_upload_bp.route("/upload-image", methods=["POST"])
def upload() -> tuple[Response, int]:
    if 'image' not in request.files:
        return jsonify({'status': 'error', 'message': 'No image provided'}), 400

    user_id = request.form.get("user_id")
    if not user_id:
        return jsonify({"status": "error", "message": "user_id not provided"}), 400

    file: FileStorage = request.files['image']
    if not file or not file.filename or not allowed_file(file.filename):
        return jsonify({'status': 'error', 'message': 'Invalid or no file selected'}), 400

    latitude = parse_float(request.form.get("latitude", ""))
    longitude = parse_float(request.form.get("longitude", ""))
    created_at = parse_datetime(request.form.get("created_at", ""))

    # Get the session
    session = get_db_session()

    # Load the image using PIL
    pil_image = Image.open(file.stream).convert("RGB")


    #########################
    #    Image Embedding    #
    #########################

    # Generate image embeddings
    img_feat = current_app.imgrep.encode_image(pil_image).numpy().astype("float32") # type: ignore
    img_feat = np.expand_dims(img_feat, axis=0)
    faiss.normalize_L2(img_feat)

    # Saving the image embeddings in faiss
    img_index = faiss.read_index(f"{Config.FAISS_DATABASE}/{user_id}_img.faiss")
    idx = img_index.ntotal
    img_index.add(img_feat)
    faiss_path : str =f"{Config.FAISS_DATABASE}/{user_id}_img.faiss"
    faiss.write_index(img_index, faiss_path)

    # Creating captions
    img_caption = current_app.imgrep.captioner.generate_caption(pil_image)


    #######################
    #         OCR         #
    #######################

    ocr_texts = current_app.imgrep.ocr.extract_text(pil_image)
    joined_ocr_texts = " ".join(ocr_texts).lower()


    ##########################
    #    Face Recognition    #
    ##########################

    face_id = None
    label_id = None

    face_feat = current_app.imgrep.face_recog.extract_face_embedding(pil_image)
    if face_feat is not None:
        # Ensure it's a NumPy array
        face_feat = np.asarray(face_feat)

        # Ensure it's float32 and 2D
        face_feat = face_feat.astype("float32")
        if face_feat.ndim == 1:
            face_feat = np.expand_dims(face_feat, axis=0)  # (1, 512)

        # Check with the db to get label
        face_index = faiss.read_index(f"{Config.FAISS_DATABASE}/{user_id}_face.faiss")

        # Get the top result only
        dist, indices = face_index.search(face_feat, k=5)
        dist = dist.tolist()
        indices = indices.tolist()

        print(indices)
        print(dist)

        # This means that we found a valid index
        if indices[0][0] != -1 and dist[0][0] < 0.7:
            another_face_id = str(indices[0][0])
            similar_image = session.query(ImageTable).filter(
                and_(
                    ImageTable.face_id == another_face_id,
                    ImageTable.user_id == user_id
                )
            ).first()
            label_id = similar_image.label_id

        # If new image generate new label
        else:
            label_count = session.query(func.count(Label.id)).scalar()
            new_label = Label(
                name=f"Label_{label_count}",
                user_id=user_id
            )
            session.add(new_label)
            session.commit()
            label_id = new_label.id

        # Saving the face index into the faiss db
        face_id = str(face_index.ntotal)
        face_index.add(face_feat)
        faiss_path : str =f"{Config.FAISS_DATABASE}/{user_id}_face.faiss"
        faiss.write_index(face_index, faiss_path)

    # Saving the image in db
    new_image = ImageTable(
        user_id=user_id,
        faiss_id=str(idx),
        face_id=face_id,
        label_id=label_id,
        text=joined_ocr_texts,
        created_at=created_at,
        latitude=latitude,
        longitude=longitude,
        description = img_caption
    )
    session.add(new_image)
    session.commit()
    session.close()

    return jsonify({
        "status": "OK",
        "index": idx,
        "label_id": label_id,
        "message": f'{file.filename.split(".")[0]}',
    }), 200
