"""
Queries a BYOND server's world/Topic() endpoint using Aurora-Persistence's
own JSON command-dispatch protocol (code/game/world.dm, code/modules/world_api/).

This is NOT the old-style "?status" raw query/URL-encoded-response protocol
most other SS13 codebases (and the original ss13rp project) speak -- this
server expects {"query": "<command name>"} as the payload and returns
{"statuscode": ..., "response": ..., "data": {...}}. The low-level BYOND wire
framing (the leading \\x00\\x83 marker, the big-endian length prefix, and the
five padding bytes before the payload) is unchanged standard BYOND protocol,
independent of what the DM-side handler does with the decoded string.
"""

from __future__ import annotations

import json
import socket
import struct


class ByondQueryError(RuntimeError):
    """Raised when a query fails at the network or protocol level."""


class RateLimitedError(ByondQueryError):
    """
    Raised specifically for statuscode 429 -- the server's own fail2topic
    anti-abuse subsystem (code/controllers/subsystems/fail2topic.dm) rejects
    requests from the same IP that arrive too close together. Distinct from
    ByondQueryError so callers can back off hard instead of just retrying on
    the normal schedule: fail2topic counts each rejection as a strike, and
    enough consecutive strikes triggers a real firewall ban if the server has
    that escalation enabled -- so repeating the same cadence that already
    tripped it risks compounding the strike count instead of clearing it.
    """


def query(addr: str, port: int, command: str, timeout: float = 5.0) -> dict:
    """
    Runs a single unauthenticated topic_command against a BYOND server and
    returns its "data" payload.

    Raises ByondQueryError on any connection failure, timeout, or malformed/
    error response -- callers should catch this and treat the server as
    temporarily unreachable rather than crashing.
    """
    payload = json.dumps({"query": command}).encode()
    packet = (
        b"\x00\x83"
        + struct.pack(">H", len(payload) + 6)
        + b"\x00\x00\x00\x00\x00"
        + payload
        + b"\x00"
    )

    try:
        with socket.create_connection((addr, port), timeout=timeout) as sock:
            sock.sendall(packet)
            data = sock.recv(65536)
    except OSError as e:
        raise ByondQueryError(f"connection to {addr}:{port} failed: {e}") from e

    if len(data) < 6:
        raise ByondQueryError(f"response too short ({len(data)} bytes)")

    try:
        result = json.loads(data[5:-1].decode())
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ByondQueryError(f"malformed response: {e}") from e

    statuscode = result.get("statuscode")
    if statuscode == 429:
        raise RateLimitedError(f"server returned 429: {result.get('response')}")
    if statuscode != 200:
        raise ByondQueryError(f"server returned statuscode={statuscode}: {result.get('response')}")

    return result.get("data") or {}
