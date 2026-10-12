"""Lambda de procesamiento con patron cache-aside
Cualquier excepcion se registra en CloudWatch ydevuelve HTTP 500 con el mensaje
"""

import base64
import hashlib
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple

from redis_client import RedisClient

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

_REDIS: Optional[RedisClient] = None
_S3 = None

def _config() -> Dict[str, Any]:
    return {
        "redis_host": os.environ["REDIS_HOST"],
        "redis_port": int(os.environ.get("REDIS_PORT", "6379")),
        "redis_tls": os.environ.get("REDIS_TLS", "true").lower() == "true",
        "bucket": os.environ["RESULTS_BUCKET"],
        "ttl": int(os.environ.get("CACHE_TTL_SECONDS", "60")),
        "region": os.environ.get("AWS_S3_REGION") or os.environ.get("AWS_REGION", "us-east-1"),
    }

def _get_redis(cfg: Dict[str, Any]) -> RedisClient:
    global _REDIS
    if _REDIS is None:
        _REDIS = RedisClient(cfg["redis_host"], cfg["redis_port"], cfg["redis_tls"])
    return _REDIS

def _get_s3(cfg: Dict[str, Any]):
    global _S3
    if _S3 is None:
        import boto3

        _S3 = boto3.client(
            "s3",
            region_name = cfg["region"],
            endpoint_url = f"https://s3.{cfg['region']}.amazonaws.com",
        )
    return _S3

def parse_request(event: Dict[str, Any]) -> Tuple[Any, Dict[str, str]]:
    """Extrae body (JSON si es posible, texto si no) y query params del evento HTTP API v2."""
    raw = event.get("body") or ""
    if event.get("isBase64Encoded") and raw:
        raw = base64.b64decode(raw).decode("utf-8")

    body: Any = raw
    if raw:
        try:
            body = json.loads(raw)
        except ValueError:
            body = raw

    query = event.get("queryStringParameters") or {}
    return body, dict(query)

def build_cache_key(body: Any, query: Dict[str, str]) -> str:
    """SHA-256 de una forma canonica (claves ordenadas): el mismo contenido da siempre la misma clave."""
    canonical = json.dumps({"body": body, "query": query}, sort_keys = True, separators = (", ", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

def process(body: Any, query: Dict[str, str], cache_key: str) -> Dict[str, Any]:
    """Transformación de ejemplo: hash SHA-256 del contenido y su inversion."""
    text = body if isinstance(body, str) else json.dumps(body, sort_keys = True, ensure_ascii = False)
    return {
        "cache_key": cache_key,
        "input": body,
        "query": query,
        "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "reversed": text[::-1],
        "processed_at": datetime.now(timezone.utc).isoformat(),
        "s3_key": f"results/{cache_key}.json",
    }

def _response(status: int, payload: Dict[str, Any] | str, cache: str) -> Dict[str, Any]:
    body = payload if isinstance(payload, str) else json.dumps(payload, ensure_ascii = False)
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", "X-Cache": cache},
        "body": body,
    }

def _handle(event: Dict[str, Any]) -> Dict[str, Any]:
    cfg = _config()
    body, query = parse_request(event)

    if body in ("", None) and not query:
        return _response(
            400, {"error": "BadRequest", "message": "Envía un body o query params para procesar."}, "MISS"
        )

    cache_key = build_cache_key(body, query)
    redis_key = f"result:{cache_key}"
    redis = _get_redis(cfg)

    cached = redis.get(redis_key)
    if cached is not None:
        logger.info("cache HIT key = %s", cache_key)
        return _response(200, cached, "HIT")

    logger.info("cache MISS key = %s", cache_key)
    result = process(body, query, cache_key)
    serialized = json.dumps(result, ensure_ascii = False)

    _get_s3(cfg).put_object(
        Bucket = cfg["bucket"],
        Key = result["s3_key"],
        Body = serialized.encode("utf-8"),
        ContentType = "application/json",
    )
    redis.set_with_ttl(redis_key, serialized, cfg["ttl"])

    return _response(200, serialized, "MISS")

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    request_id = getattr(context, "aws_request_id", "local")
    try:
        return _handle(event)
    except Exception as exc:
        logger.exception("request_id = %s fallo procesando la solicitud", request_id)
        return _response(
            500,
            {
                "error": "InternalServerError",
                "message": f"Error procesando la solicitud: {type(exc).__name__}: {exc}",
                "request_id": request_id,
            },
            "MISS",
        )
