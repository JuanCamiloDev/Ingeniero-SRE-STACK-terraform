"""Cliente Redis minimo (protocolo RESP sobre socket)

Solo implementa GET y SET - EX, que es todo lo que necesita este servicio
"""

import socket
import ssl
from typing import Optional


class RedisError(Exception):
    """Error de comunicacion o respuesta de error devuelta por Redis."""


class RedisClient:
    def __init__(self, host: str, port: int = 6379, use_tls: bool = True, timeout: float = 2.0):
        self._host = host
        self._port = port
        self._use_tls = use_tls
        self._timeout = timeout
        self._sock = None
        self._reader = None

    # ------------------------------------------------------------------ API
    def get(self, key: str) -> Optional[str]:
        return self._execute("GET", key)

    def set_with_ttl(self, key: str, value: str, ttl_seconds: int) -> None:
        """SET key value EX ttl. El TTL es obligatorio: nunca se escribe sin expiracion."""
        if ttl_seconds <= 0:
            raise ValueError("ttl_seconds debe ser > 0")
        reply = self._execute("SET", key, value, "EX", str(ttl_seconds))
        if reply != "OK":
            raise RedisError(f"Respuesta inesperada a SET: {reply!r}")

    def close(self) -> None:
        for resource in (self._reader, self._sock):
            try:
                if resource is not None:
                    resource.close()
            except OSError:
                pass
        self._reader = None
        self._sock = None

    # ------------------------------------------------------------ internals
    def _connect(self) -> None:
        raw = socket.create_connection((self._host, self._port), timeout=self._timeout)
        if self._use_tls:
            context = ssl.create_default_context()
            raw = context.wrap_socket(raw, server_hostname=self._host)
        raw.settimeout(self._timeout)
        self._sock = raw
        self._reader = raw.makefile("rb")

    def _execute(self, *args: str):
        """Envía un comando; reintenta una vez si la conexion reutilizada estaba rota."""
        last_error = None
        for _ in range(2):
            try:
                if self._sock is None:
                    self._connect()
                self._sock.sendall(self._encode(args))
                return self._read_reply()
            except OSError as exc:  # incluye timeouts, resets y errores TLS
                last_error = exc
                self.close()
        raise RedisError(
            f"No se pudo comunicar con Redis en {self._host}:{self._port}: {last_error}"
        ) from last_error

    @staticmethod
    def _encode(args) -> bytes:
        parts = [f"*{len(args)}\r\n".encode()]
        for arg in args:
            data = arg.encode("utf-8")
            parts.append(f"${len(data)}\r\n".encode() + data + b"\r\n")
        return b"".join(parts)

    def _read_reply(self):
        line = self._reader.readline()
        if not line:
            raise ConnectionError("Redis cerro la conexion")
        kind, payload = line[:1], line[1:-2]
        if kind == b"+":
            return payload.decode()
        if kind == b"-":
            raise RedisError(payload.decode())
        if kind == b":":
            return int(payload)
        if kind == b"$":
            length = int(payload)
            if length == -1:
                return None
            data = self._reader.read(length + 2)
            return data[:-2].decode("utf-8")
        raise RedisError(f"Tipo de respuesta RESP no soportado: {kind!r}")
