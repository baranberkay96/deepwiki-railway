"""Write DeepWiki's runtime config directory for this deployment.

DeepWiki reads generator.json / embedder.json / repo.json / lang.json from
DEEPWIKI_CONFIG_DIR (upstream feature, api/config.py). This script copies the
upstream files shipped in the image unchanged and only adjusts generator.json:

* default_provider -> the provider chosen by start.sh (so the UI preselects a
  provider the deployment actually has a key for; upstream defaults to Google);
* the default model of that provider -> DEEPWIKI_MODEL, or a template default
  for OpenAI and Google, whose upstream defaults are being retired
  (gpt-5-nano: shutdown 2026-12-11; gemini-2.5-flash: no longer offered to new
  API users). The new model is listed first and inherits the parameters
  (temperature, top_p, ...) of the provider's upstream default model.

Upstream files are never modified; the output directory is rebuilt on every start.

Usage: python configure.py <upstream config dir> <output dir> <provider> [<model>]
"""
from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

TEMPLATE_DEFAULT_MODELS: dict[str, str] = {
    "openai": "gpt-6-luna",
    "google": "gemini-3.8-flash",
}
CONFIG_FILES: tuple[str, ...] = ("generator.json", "embedder.json", "repo.json", "lang.json")
MODEL_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,127}$")


def fail(message: str) -> None:
    print(f"[deepwiki] ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def with_default_model(provider_cfg: dict, model: str) -> dict:
    """Return a copy of provider_cfg whose default (and first listed) model is `model`."""
    models = dict(provider_cfg.get("models") or {})
    upstream_default = provider_cfg.get("default_model")
    params = models.get(model) or models.get(upstream_default) or {}
    reordered = {model: dict(params)}
    reordered.update({name: cfg for name, cfg in models.items() if name != model})
    return {**provider_cfg, "default_model": model, "models": reordered}


def build_generator(generator: dict, provider: str, model: str) -> tuple[dict, str]:
    providers = generator.get("providers") or {}
    if provider not in providers:
        fail(f"provider '{provider}' is not in DeepWiki's generator.json ({', '.join(sorted(providers))})")
    chosen = model or TEMPLATE_DEFAULT_MODELS.get(provider, "")
    provider_cfg = providers[provider]
    if chosen:
        if not MODEL_ID.match(chosen):
            fail(f"DEEPWIKI_MODEL '{chosen}' is not a valid model id")
        provider_cfg = with_default_model(provider_cfg, chosen)
    new_providers = {**providers, provider: provider_cfg}
    result = {**generator, "default_provider": provider, "providers": new_providers}
    return result, provider_cfg.get("default_model", "")


def main(argv: list[str]) -> int:
    if len(argv) not in (4, 5):
        print(__doc__, file=sys.stderr)
        return 2
    src, out, provider = Path(argv[1]), Path(argv[2]), argv[3]
    model = argv[4].strip() if len(argv) == 5 else ""

    missing = [name for name in CONFIG_FILES if not (src / name).is_file()]
    if missing:
        fail(f"upstream config files missing in {src}: {', '.join(missing)}")

    try:
        generator = json.loads((src / "generator.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        fail(f"cannot read {src / 'generator.json'}: {exc}")
    new_generator, default_model = build_generator(generator, provider, model)

    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for name in CONFIG_FILES:
        if name != "generator.json":
            shutil.copyfile(src / name, out / name)
    (out / "generator.json").write_text(json.dumps(new_generator, indent=2) + "\n", encoding="utf-8")

    print(f"[deepwiki] config {out}: default provider={provider} model={default_model}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
