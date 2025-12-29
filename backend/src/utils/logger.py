import logging
import colorlog
from logging import Logger

def setup_logger() -> Logger:
    logger: Logger = logging.getLogger('image_search_engine')
    logger.setLevel(logging.DEBUG)

    if logger.hasHandlers():
        logger.handlers.clear()

    handler = colorlog.StreamHandler()
    handler.setFormatter(
        colorlog.ColoredFormatter(
            '%(log_color)s             ==>  %(levelname)s -> %(filename)s:%(lineno)d : %(message)s',
            log_colors={
                'DEBUG': 'cyan',
                'INFO': 'green',
                'WARNING': 'yellow',
                'ERROR': 'red',
                'CRITICAL': 'red,bg_white',
            }
        )
    )
    logger.addHandler(handler)
    return logger

logger: Logger = setup_logger()
