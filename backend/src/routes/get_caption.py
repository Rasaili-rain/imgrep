from flask import Blueprint, request, jsonify

from src.db import ImageTable, get_db_session

get_caption = Blueprint('get_caption', __name__)

@get_caption.route('/get-caption', methods=['POST'])
def caption():
    payload = request.get_json()
    faiss_id = payload.get('faiss_id')
    user_id = payload.get('user_id')

    session = get_db_session()
    caption = session.query(ImageTable).filter(ImageTable.faiss_id == faiss_id, ImageTable.user_id == user_id).one()

    return jsonify({
        "status": "ok", 
        "caption": caption.description
        }), 200


