"""Build-time check of the patched OpenAI streamer (no network, no API key).

Feeds fake Responses API events and fake Chat Completions chunks through
api.chat._stream.OpenAIChatStreamer.respond_stream and asserts the text that comes
out. Run from /app: python /tmp/check_openai_stream.py
"""
import asyncio
import sys
from types import SimpleNamespace

sys.path.insert(0, "/app")

from api.chat._stream import OpenAIChatStreamer  # noqa: E402


class FakeClient:
    def __init__(self, events: list) -> None:
        self._events = events

    def convert_inputs_to_api_kwargs(self, input, model_kwargs, model_type):  # noqa: A002
        return {"input": input, **model_kwargs}

    async def acall(self, api_kwargs, model_type):
        async def stream():
            for event in self._events:
                yield event

        return stream()


def make_streamer(events: list) -> OpenAIChatStreamer:
    streamer = object.__new__(OpenAIChatStreamer)
    streamer.client = FakeClient(events)
    streamer.model_kwargs = {"model": "test", "stream": True}
    return streamer


async def collect(events: list) -> str:
    parts = []
    async for text in make_streamer(events).respond_stream("prompt"):
        parts.append(text)
    return "".join(parts)


def chat_chunk(text):
    return SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content=text))])


def main() -> int:
    responses_events = [
        SimpleNamespace(type="response.created"),
        SimpleNamespace(type="response.output_text.delta", delta="Hello"),
        SimpleNamespace(type="response.output_text.delta", delta=", wiki"),
        SimpleNamespace(type="response.completed"),
    ]
    assert asyncio.run(collect(responses_events)) == "Hello, wiki", "Responses API events"

    chat_chunks = [chat_chunk("a"), chat_chunk(None), chat_chunk("b"), SimpleNamespace(choices=[])]
    assert asyncio.run(collect(chat_chunks)) == "ab", "Chat Completions chunks"

    failed = [
        SimpleNamespace(type="response.output_text.delta", delta="x"),
        SimpleNamespace(
            type="response.failed",
            response=SimpleNamespace(error=SimpleNamespace(message="quota exceeded")),
        ),
    ]
    try:
        asyncio.run(collect(failed))
    except RuntimeError as exc:
        assert "quota exceeded" in str(exc), exc
    else:
        raise AssertionError("response.failed must raise")

    print("OpenAI stream patch: Responses events, chat chunks and failures handled")
    return 0


if __name__ == "__main__":
    sys.exit(main())
