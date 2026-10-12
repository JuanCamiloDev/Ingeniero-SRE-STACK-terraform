"""Pruebas unitarias sin AWS: Redis y S3 se sustituyen por fakes.

Ejecutar desde la raíz del repo:  python -m unittest discover -s lambda/tests -v
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

os.environ.update(
    REDIS_HOST="fake", RESULTS_BUCKET="fake-bucket", CACHE_TTL_SECONDS="60", AWS_S3_REGION="us-east-1"
)

import handler  # noqa: E402


class FakeRedis:
    def __init__(self):
        self.store = {}
        self.ttls = {}

    def get(self, key):
        return self.store.get(key)

    def set_with_ttl(self, key, value, ttl):
        self.store[key] = value
        self.ttls[key] = ttl


class FakeS3:
    def __init__(self):
        self.objects = {}

    def put_object(self, Bucket, Key, Body, ContentType):
        self.objects[(Bucket, Key)] = Body


class Ctx:
    aws_request_id = "test-req"


def event(body=None, query=None):
    return {"body": json.dumps(body) if body is not None else None, "queryStringParameters": query}


class HandlerTests(unittest.TestCase):
    def setUp(self):
        handler._REDIS = FakeRedis()
        handler._S3 = FakeS3()

    def test_miss_then_hit(self):
        first = handler.lambda_handler(event({"msg": "hola"}), Ctx())
        second = handler.lambda_handler(event({"msg": "hola"}), Ctx())
        self.assertEqual(first["statusCode"], 200)
        self.assertEqual(first["headers"]["X-Cache"], "MISS")
        self.assertEqual(second["headers"]["X-Cache"], "HIT")
        self.assertEqual(first["body"], second["body"])

    def test_saves_to_s3_under_results_prefix_and_redis_has_ttl(self):
        res = handler.lambda_handler(event({"a": 1}), Ctx())
        key = json.loads(res["body"])["s3_key"]
        self.assertTrue(key.startswith("results/") and key.endswith(".json"))
        self.assertIn(("fake-bucket", key), handler._S3.objects)
        self.assertEqual(list(handler._REDIS.ttls.values()), [60])

    def test_cache_key_ignores_json_key_order(self):
        a = handler.build_cache_key({"x": 1, "y": 2}, {})
        b = handler.build_cache_key({"y": 2, "x": 1}, {})
        self.assertEqual(a, b)

    def test_plain_text_body_is_supported(self):
        res = handler.lambda_handler({"body": "texto plano"}, Ctx())
        self.assertEqual(res["statusCode"], 200)
        self.assertEqual(json.loads(res["body"])["reversed"], "onalp otxet")

    def test_empty_request_returns_400(self):
        res = handler.lambda_handler({"body": None}, Ctx())
        self.assertEqual(res["statusCode"], 400)

    def test_exception_returns_500_with_message_and_header(self):
        class BoomRedis(FakeRedis):
            def get(self, key):
                raise RuntimeError("redis caído")

        handler._REDIS = BoomRedis()
        res = handler.lambda_handler(event({"a": 1}), Ctx())
        self.assertEqual(res["statusCode"], 500)
        self.assertIn("redis caído", json.loads(res["body"])["message"])
        self.assertIn("X-Cache", res["headers"])


if __name__ == "__main__":
    unittest.main()
