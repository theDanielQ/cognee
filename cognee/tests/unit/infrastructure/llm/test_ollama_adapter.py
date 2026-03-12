from contextlib import asynccontextmanager
from types import SimpleNamespace

import asyncio
from pydantic import BaseModel

from cognee.infrastructure.llm.structured_output_framework.litellm_instructor.llm.ollama.adapter import (
    OllamaAPIAdapter,
)


@asynccontextmanager
async def _noop_rate_limiter():
    yield


class _AnswerModel(BaseModel):
    answer: str


def test_acreate_structured_output_returns_plain_text_for_str(monkeypatch):
    adapter = OllamaAPIAdapter.__new__(OllamaAPIAdapter)
    adapter.model = "llama3.1:8b"

    captured = {}

    def _create(**kwargs):
        captured.update(kwargs)
        return SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content="local answer"))]
        )

    adapter.aclient = SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=_create)))

    monkeypatch.setattr(
        "cognee.infrastructure.llm.structured_output_framework.litellm_instructor.llm.ollama.adapter.llm_rate_limiter_context_manager",
        _noop_rate_limiter,
    )

    output = asyncio.run(adapter.acreate_structured_output("Q", "S", str))

    assert output == "local answer"
    assert "response_model" not in captured


def test_acreate_structured_output_keeps_structured_path_for_models(monkeypatch):
    adapter = OllamaAPIAdapter.__new__(OllamaAPIAdapter)
    adapter.model = "llama3.1:8b"

    structured_response = _AnswerModel(answer="ok")
    captured = {}

    def _create(**kwargs):
        captured.update(kwargs)
        return structured_response

    adapter.aclient = SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=_create)))

    monkeypatch.setattr(
        "cognee.infrastructure.llm.structured_output_framework.litellm_instructor.llm.ollama.adapter.llm_rate_limiter_context_manager",
        _noop_rate_limiter,
    )

    output = asyncio.run(adapter.acreate_structured_output("Q", "S", _AnswerModel))

    assert output is structured_response
    assert captured["response_model"] is _AnswerModel
