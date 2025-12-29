from sqlalchemy import DateTime, Float, create_engine, Column, UUID, Integer, Text, ForeignKey
from sqlalchemy.orm import sessionmaker, Session, relationship
from sqlalchemy.ext.declarative import declarative_base
from uuid import uuid4

from src.config import Config
from src.utils.logger import logger

Base = declarative_base()


def get_db_session() -> Session:
    try:
        engine = create_engine(Config.DATABASE_URL, echo=Config.DEBUG)
        Session = sessionmaker(bind=engine)
        return Session()
    except Exception as e:
        logger.error(f"Database connection error: {str(e)}")
        raise


##########################
#         MODELS         #
##########################

class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid4)


# class Ocr(Base):
#     __tablename__ = "ocr"

#     id = Column(Integer, primary_key=True, autoincrement=True)
#     user_id = Column(Text, nullable=False)
#     faiss_id = Column(Text, nullable=False)
#     text = Column(Text, nullable=False)



class ImageTable(Base):
    __tablename__ = "image_table"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Text, nullable=False)
    faiss_id = Column(Text, nullable=False)
    face_id = Column(Text, nullable=True)
    text = Column(Text, nullable=True)
    created_at = Column(DateTime, nullable=False)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    description = Column(Text, nullable=True)
    label_id = Column(Integer, ForeignKey("label.id"), nullable=True)

    label = relationship("Label", back_populates="images")


class Label(Base):
    __tablename__ = "label"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Text, nullable=True)
    name = Column(Text, nullable=False)

    images = relationship("ImageTable", back_populates="label")
