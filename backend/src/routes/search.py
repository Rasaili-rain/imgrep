from datetime import datetime
from rapidfuzz.fuzz import token_set_ratio
from flask import Blueprint, request, jsonify, Response, current_app
import numpy as np
import faiss
import json
from PIL import Image

from src.config import Config
from src.db import ImageTable, get_db_session, Label
import src.imgrep.date_time_parser.date_time_parser as dt

search_bp = Blueprint("search", __name__)


def datetime_match_boost(all_results, images_from_db, datetime_ranges):
    if not datetime_ranges or not datetime_ranges.get('datetime_ranges'):
        return all_results

    for image in images_from_db:
        if not image.created_at:
            continue

        image_time = image.created_at
        # Access the datetime_ranges list from the dictionary
        for time_range in datetime_ranges['datetime_ranges']:
            try:
                start_time = datetime.fromisoformat(time_range['start_datetime'])
                end_time = datetime.fromisoformat(time_range['end_datetime'])
                if start_time <= image_time <= end_time:
                    if image.faiss_id in all_results:
                        all_results[image.faiss_id] += Config.DATE_TIME_BOOST_AMOUNT
            except (ValueError, AttributeError, KeyError):
                continue

    return all_results


@search_bp.route("/search", methods=["POST"])
def search() -> tuple[Response, int]:
    payload = request.get_json()

    if "user_id" not in payload:
        return jsonify({"status": "error", "message": "user_id is required"}), 400
    if "query" not in payload:
        return jsonify({"status": "error", "message": "query is required"}), 400

    user_id = payload.get("user_id")
    query = payload.get("query")

    # NOTE(slok): Amount is depricated
    amount = payload.get("amount") if "amount" in payload else 5

    # --- Parse the date from the query --- #
    extractor = dt.DateTimeRangeExtractor()
    datetime_ranges = extractor.extract_datetime_ranges(query)
    print(extractor.to_json(datetime_ranges))
    # -- --- --- -- #

    # Generate text embeddings of the query
    feat = current_app.imgrep.encode_text(query).numpy().astype("float32")  # type: ignore
    feat = np.expand_dims(feat, axis=0)
    faiss.normalize_L2(feat)

    all_results = {}

    #######################
    #    Text to Image    #
    #######################

    img_index = faiss.read_index(f"{Config.FAISS_DATABASE}/{user_id}_img.faiss")
    _, img_dists, img_indices = img_index.range_search(feat, Config.EMBEDDING_SEARCH_RANGE)

    # Converting distances to the score from 0 - 1 (1 Begin the top)
    max_dist = np.max(img_dists)
    image_scores = {
        str(idx): float(1 - (dist / max_dist))
        for idx, dist in zip(img_indices, img_dists)
    }

    for faiss_id, img_score in image_scores.items():
        all_results[faiss_id] = img_score


    #######################
    #      OCR SEARCH     #
    #######################

    session = get_db_session()
    user_images = session.query(ImageTable).filter(ImageTable.user_id == user_id).all()

    # Apply datetime boost
    all_results = datetime_match_boost(all_results, user_images, datetime_ranges)

    # Apply OCR scoring
    for image in user_images:
        ocr_score = token_set_ratio(query.lower(), image.text.lower()) / 100.0
        if image.faiss_id in all_results:
            all_results[image.faiss_id] += Config.OCR_WEIGHT * ocr_score
        else:
            all_results[image.faiss_id] = ocr_score


    #########################
    #      LABEL SEARCH     #
    #########################

    labels = session.query(Label).filter(Label.user_id == user_id).all()
    for label in labels:
        label_score = token_set_ratio(query.lower(), label.name.lower()) / 100

        # If the label has sufficient score
        if label_score > Config.LABEL_SCORE_THRESHOLD:

            # Get all the images related to that label
            images = label.images

            # Add it to the result
            for image in images:
                if image.faiss_id in all_results:
                    all_results[image.faiss_id] += Config.LABEL_WEIGHT * label_score 
                else:
                    all_results[image.faiss_id] = label_score 


    # Sorting the result and triming off the poor results
    print("All Result:", json.dumps(all_results, indent=4))
    final_result = sorted(
    	[(i, s) for i, s in all_results.items() if s > Config.SEARCH_SCORE_THRESHOLD],
    	key=lambda x: x[1],
    	reverse=True
    )[:amount]
    print("Final Result:", json.dumps(final_result, indent=4))

    distances = [score for _, score in final_result]
    indices = [int(faiss_id) for faiss_id, _ in final_result]

    return jsonify({
        "status": "ok",
        "distances": distances,
        "indices": indices
    }), 200


@search_bp.route("/search/image", methods=["POST"])
def search_image() -> tuple[Response, int]:
    # Get the image file
    if 'image' not in request.files:
        return jsonify({'status': 'error', 'message': 'No image provided'}), 400
    file = request.files["image"]

    # Get user ID
    user_id = request.form.get("user_id")
    if not user_id:
        return jsonify({"status": "error", "message": "user_id not provided"}), 400

    #NOTE(slok): Haven't added the extension check here
    if not file or not file.filename:
        return jsonify({'status': 'error', 'message': 'Invalid or no file selected'}), 400

    # Load the PIL image
    pil_image = Image.open(file.stream).convert("RGB")

    # Generate image embeddings
    img_feat = current_app.imgrep.encode_image(pil_image).numpy().astype("float32") # type: ignore
    img_feat = np.expand_dims(img_feat, axis=0)
    faiss.normalize_L2(img_feat)

    # Searching in the image faiss db
    img_index = faiss.read_index(f"{Config.FAISS_DATABASE}/{user_id}_img.faiss")
    _, img_dists, img_indices = img_index.range_search(img_feat, 1.5)

    print("Distances:", json.dumps(img_dists.tolist(), indent=4))
    print("Indices:", json.dumps(img_indices.tolist(), indent=4))

    result = {}
    for dist, idx in zip(img_dists, img_indices):
        result[int(idx)] = float(dist)

    final_result = sorted(result.items(), key=lambda x:x[1]) 
    print("Final Result:", json.dumps(final_result,indent=4))
    
    distances = [d for _, d in final_result]
    indices = [i for i, _ in final_result]

    return jsonify({
        "status": "ok",
        "distances": distances,
        "indices": indices
    }), 200