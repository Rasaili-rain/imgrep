from flask import Blueprint, Response, jsonify, request
from sqlalchemy.orm import Session

from src.db import get_db_session, Label


label_bp = Blueprint("label", __name__)

@label_bp.route("/label/get/<string:label_id>", methods=["GET"])
def get_label(label_id: str) -> Response:
    session: Session = get_db_session()

    label = session.query(Label).get(label_id)
    session.close()

    if not label:
        return jsonify({'error': 'Label not found'}), 404

    return jsonify({'name': label.name}), 200


@label_bp.route("/label/update", methods=["POST"])
def update_label() -> Response:
    session = get_db_session()
    payload = request.get_json()

    if "label_id" not in payload:
        return jsonify({"status": "error", "message": "label_id is required"}), 400
    if "name" not in payload:
        return jsonify({"status": "error", "message": "name is required"}), 400

    label_id = payload.get("label_id")
    name = payload.get("name")

    # Fetch the label from the database
    label = session.query(Label).filter_by(id=label_id).first()
    if not label:
        session.close()
        return jsonify({"status": "ERROR", "message": "Label not found"}), 404

    # Update the label's name
    label.name = name
    session.commit()
    session.close()

    return jsonify({"status": "OK", "message": "Label updated" }), 200
