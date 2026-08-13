#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["pyyaml"]
# ///
"""Migrate LLM model and skill settings from local Hermes to Docker data/."""

from __future__ import annotations

import os
import shutil
from datetime import datetime
from pathlib import Path

import yaml

# Local Hermes data directory. Defaults to %LOCALAPPDATA%\hermes on Windows;
# override with the LOCAL_HERMES environment variable.
LOCAL_HERMES = Path(
    os.environ.get("LOCAL_HERMES")
    or Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local") / "hermes"
)
DOCKER_DATA = Path(__file__).resolve().parents[1] / "data"

MERGE_KEYS = [
    "model",
    "providers",
    "custom_providers",
    "fallback_providers",
    "credential_pool_strategies",
    "toolsets",
    "auxiliary",
    "skills",
    "display",
    "delegation",
    "curator",
    "x_search",
    "platforms",
    "discord",
    "telegram",
    "slack",
    "whatsapp",
    "mattermost",
    "matrix",
    "onboarding",
    "model_catalog",
]

ENV_KEYS = [
    "CUSTOM_API_KEY",
    "OPENROUTER_API_KEY",
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_ALLOWED_USERS",
    "TELEGRAM_HOME_CHANNEL",
    "TELEGRAM_HOME_CHANNEL_THREAD_ID",
    "DISCORD_BOT_TOKEN",
    "DISCORD_ALLOWED_CHANNELS",
    "DISCORD_ALLOWED_USERS",
    "DISCORD_HOME_CHANNEL",
    "GOOGLE_ACCOUNT",
    "GOOGLE_PASSWORD",
    "GITHUB_TOKEN",
    "GROQ_API_KEY",
    "VOICE_TOOLS_OPENAI_KEY",
    "BROWSERBASE_API_KEY",
    "BROWSERBASE_PROJECT_ID",
]


def docker_url(value: str) -> str:
    if not isinstance(value, str) or not value:
        return value
    return (
        value.replace("http://localhost:", "http://host.docker.internal:")
        .replace("http://127.0.0.1:", "http://host.docker.internal:")
        .replace("https://localhost:", "https://host.docker.internal:")
        .replace("https://127.0.0.1:", "https://host.docker.internal:")
    )


def walk_urls(obj):
    if isinstance(obj, dict):
        return {k: walk_urls(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [walk_urls(v) for v in obj]
    if isinstance(obj, str) and ("://localhost" in obj or "://127.0.0.1" in obj):
        return docker_url(obj)
    return obj


def load_yaml(path: Path) -> dict:
    with path.open(encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def dump_yaml(path: Path, data: dict) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as f:
        yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)


def merge_config() -> None:
    local_cfg = load_yaml(LOCAL_HERMES / "config.yaml")
    docker_cfg_path = DOCKER_DATA / "config.yaml"
    if not docker_cfg_path.exists():
        raise SystemExit(
            f"{docker_cfg_path} not found — run first-time setup before migrating:\n"
            "  docker compose --profile setup run --rm setup"
        )
    docker_cfg = load_yaml(docker_cfg_path)

    backup = docker_cfg_path.with_name(
        f"config.yaml.bak-migrate-{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    )
    shutil.copy2(docker_cfg_path, backup)

    for key in MERGE_KEYS:
        if key in local_cfg:
            docker_cfg[key] = walk_urls(local_cfg[key])

    # Prefer real API key from local .env when config still has placeholder.
    local_env = parse_env(LOCAL_HERMES / ".env")
    api_key = local_env.get("CUSTOM_API_KEY", "")
    if api_key:
        model = docker_cfg.setdefault("model", {})
        if not model.get("api_key") or "change-me" in str(model.get("api_key", "")):
            model["api_key"] = api_key
        for entry in docker_cfg.get("custom_providers") or []:
            if isinstance(entry, dict) and not entry.get("api_key"):
                entry["api_key"] = api_key

    docker_cfg["_config_version"] = max(
        int(docker_cfg.get("_config_version") or 0),
        int(local_cfg.get("_config_version") or 0),
    )

    dump_yaml(docker_cfg_path, docker_cfg)
    print(f"merged config -> {docker_cfg_path}")
    print(f"backup -> {backup}")


def parse_env(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        out[key.strip()] = value.strip()
    return out


def merge_env() -> None:
    local_env = parse_env(LOCAL_HERMES / ".env")
    docker_env_path = DOCKER_DATA / ".env"
    docker_env = parse_env(docker_env_path)

    for key in ENV_KEYS:
        value = local_env.get(key)
        if value:
            docker_env[key] = value

    lines = [f"{k}={v}" for k, v in docker_env.items()]
    docker_env_path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"merged env -> {docker_env_path}")


def copy_skills() -> None:
    src = LOCAL_HERMES / "skills"
    dst = DOCKER_DATA / "skills"
    if not src.exists():
        print(f"no skills to copy ({src} does not exist)")
        return
    exclude = {".archive", ".curator_backups", ".hub"}

    copied = 0
    for item in src.rglob("*"):
        if any(part in exclude for part in item.parts):
            continue
        rel = item.relative_to(src)
        target = dst / rel
        if item.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, target)
            copied += 1

    for meta in [".bundled_manifest", ".curator_state", ".usage.json", ".usage.json.lock"]:
        meta_src = src / meta
        if meta_src.exists():
            shutil.copy2(meta_src, dst / meta)

    print(f"copied/updated {copied} skill files -> {dst}")


def copy_profiles() -> None:
    src = LOCAL_HERMES / "profiles"
    dst = DOCKER_DATA / "profiles"
    if not src.exists():
        print(f"no profiles to copy ({src} does not exist)")
        return

    for profile_dir in src.iterdir():
        if not profile_dir.is_dir():
            continue
        target_dir = dst / profile_dir.name
        target_dir.mkdir(parents=True, exist_ok=True)
        for item in profile_dir.rglob("*"):
            rel = item.relative_to(profile_dir)
            target = target_dir / rel
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif item.suffix in {".yaml", ".yml"}:
                data = load_yaml(item)
                data = walk_urls(data)
                target.parent.mkdir(parents=True, exist_ok=True)
                dump_yaml(target, data)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(item, target)

    print(f"copied profiles -> {dst}")


def main() -> None:
    if not LOCAL_HERMES.exists():
        raise SystemExit(f"local hermes not found: {LOCAL_HERMES}")
    DOCKER_DATA.mkdir(parents=True, exist_ok=True)
    merge_config()
    merge_env()
    copy_skills()
    copy_profiles()
    print("migration complete")


if __name__ == "__main__":
    main()
