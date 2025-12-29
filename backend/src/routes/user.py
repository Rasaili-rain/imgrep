from flask import Blueprint, jsonify, Response
from uuid import uuid4, UUID as UUIDType
from sqlalchemy.orm import Session
from typing import Tuple
import os
import faiss

from src.config import Config
from src.utils.logger import logger
from src.db import get_db_session, User

user_bp: Blueprint = Blueprint('user', __name__)

@user_bp.route('/user/new', methods=['POST'])
def create_user() -> Tuple[Response, int]:
    try:
        session: Session = get_db_session()

        # Create new user
        user_id: UUIDType = uuid4()
        new_user: User = User(id=user_id)
        session.add(new_user)
        session.commit()
        session.close()

        if not os.path.exists(Config.FAISS_DATABASE):
            os.mkdir(Config.FAISS_DATABASE)

        # Creating faiss db for image
        faiss.write_index(
            faiss.IndexFlatL2(Config.EMBEDDING_DIM),
            f"{Config.FAISS_DATABASE}/{user_id}_img.faiss"
        )

        # Creating faiss db for face
        faiss.write_index(
            faiss.IndexFlatL2(Config.FACE_EMBEDDING_DIM),
            f"{Config.FAISS_DATABASE}/{user_id}_face.faiss"
        )

        return jsonify({
            "status": "success",
            "user_id": str(user_id),
            "message": "User created successfully"
        }), 201

    except Exception as e:
        logger.error(f"Error creating user: {str(e)}")
        return jsonify({
            "status": "error",
            "message": "Failed to create user"
        }), 500
