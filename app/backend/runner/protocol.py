"""
Newline-delimited JSON protocol for hxg_runner Unix socket communication.
All messages are single JSON objects terminated by newline.
"""
from dataclasses import dataclass, asdict
from typing import Optional
import json


@dataclass
class RunnerRequest:
    """Request from hxg_server to hxg_runner."""
    action: str          # "scan" | "fix" | "scan_batch" | "ping"
    req_id: str
    rule: Optional[str] = None
    rules: Optional[list] = None  # for scan_batch

    def encode(self) -> bytes:
        return (json.dumps(asdict(self)) + "\n").encode()


@dataclass
class RunnerResult:
    """Single rule result returned by hxg_runner."""
    req_id: str
    rule: str
    status: str          # PASS | FAIL | NOT_APPLICABLE | ERROR
    action: Optional[str] = None  # for fix: EXECUTED | NOT_APPLICABLE | ERROR
    result: Optional[str] = None
    expected: Optional[str] = None
    message: Optional[str] = None
    exit_code: int = 0
    duration_ms: int = 0
    done: bool = False   # True on final batch message

    @classmethod
    def from_dict(cls, d: dict) -> "RunnerResult":
        return cls(**{k: v for k, v in d.items() if k in cls.__dataclass_fields__})

    def encode(self) -> bytes:
        return (json.dumps(asdict(self)) + "\n").encode()
