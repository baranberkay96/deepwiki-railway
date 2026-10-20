"""Build-time patch: make DeepWiki's OpenAI-compatible streamer read Responses API events.

Upstream bug: https://github.com/AsyncFuncAI/deepwiki-open/issues/585 (open fix: PR #586).
adalflow 1.1.3's OpenAIClient streams through the Responses API, but
api/chat/_stream.py (_OpenAICompatStreamer.respond_stream) only understands Chat
Completions chunks (`chunk.choices`), so every OpenAI (and Azure) generation fails
with "'ResponseCreatedEvent' object has no attribute 'choices'".

This script replaces exactly that loop. It refuses to run if the upstream code no
longer matches (the build then fails instead of silently shipping something else).
Drop it once upstream ships the fix.

Usage: python patch_openai_stream.py /app/api/chat/_stream.py
"""
import sys
from pathlib import Path

ORIGINAL = """        async for chunk in response:
            if (
                chunk.choices
                and chunk.choices[0].delta is not None
                and chunk.choices[0].delta.content is not None
            ):
                yield chunk.choices[0].delta.content
"""

REPLACEMENT = """        async for chunk in response:
            # [railway-template] Responses API events (adalflow >= 1.1 OpenAIClient).
            event_type = getattr(chunk, "type", None)
            if event_type == "response.output_text.delta":
                delta = getattr(chunk, "delta", None)
                if delta:
                    yield delta
                continue
            if event_type in ("error", "response.failed"):
                failure = getattr(getattr(chunk, "response", None), "error", None)
                message = getattr(chunk, "message", None) or getattr(
                    failure, "message", None
                )
                raise RuntimeError(message or f"OpenAI stream reported {event_type}")
            # Chat Completions chunks (older clients, OpenAI-compatible servers).
            choices = getattr(chunk, "choices", None)
            if (
                choices
                and choices[0].delta is not None
                and choices[0].delta.content is not None
            ):
                yield choices[0].delta.content
"""

MARKER = "[railway-template] Responses API events"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_openai_stream.py <path to api/chat/_stream.py>", file=sys.stderr)
        return 2
    target = Path(sys.argv[1])
    source = target.read_text(encoding="utf-8")
    if MARKER in source:
        print(f"{target}: already patched")
        return 0
    count = source.count(ORIGINAL)
    if count != 1:
        print(
            f"{target}: expected the upstream OpenAI stream loop exactly once, found {count}. "
            "Upstream changed; review issue #585 / PR #586 and update or drop this patch.",
            file=sys.stderr,
        )
        return 1
    target.write_text(source.replace(ORIGINAL, REPLACEMENT), encoding="utf-8")
    print(f"{target}: patched OpenAI Responses API stream handling")
    return 0


if __name__ == "__main__":
    sys.exit(main())
