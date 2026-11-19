"""AI provider auto-detection, CLI configuration, and reviewer live probe tests."""

import json

import httpx

import manage
from app import config


def test_resolve_ai_settings_autodetects_and_respects_disabled():
    assert config._resolve_ai_settings({})["AI_PROVIDER"] == "disabled"

    gemini = config._resolve_ai_settings({"GEMINI_API_KEY": "gm-test-key"})
    assert gemini["AI_PROVIDER"] == "gemini"
    assert gemini["AI_API_KEY"] == "gm-test-key"
    assert "generativelanguage.googleapis.com" in gemini["AI_BASE_URL"]

    openrouter = config._resolve_ai_settings({"OPENROUTER_API_KEY": "or-test-key"})
    assert openrouter["AI_PROVIDER"] == "openrouter"
    assert openrouter["AI_API_KEY"] == "or-test-key"

    openai = config._resolve_ai_settings({"OPENAI_API_KEY": "oa-test-key"})
    assert openai["AI_PROVIDER"] == "openai"
    assert openai["AI_API_KEY"] == "oa-test-key"

    explicit_off = config._resolve_ai_settings(
        {"AI_PROVIDER": "disabled", "GEMINI_API_KEY": "gm-test-key"}
    )
    assert explicit_off["AI_PROVIDER"] == "disabled"
    assert explicit_off["AI_API_KEY"] == ""


def test_upsert_env_file_updates_ai_and_preserves_other_vars(tmp_path):
    env_file = tmp_path / ".env"
    env_file.write_text(
        "AUTH_PROVIDER=local\nAI_PROVIDER=disabled\nCUSTOM_FLAG=keep\n",
        encoding="utf-8",
    )
    manage._upsert_env_file(
        env_file,
        {
            "AI_PROVIDER": "gemini",
            "AI_API_KEY": "secret-placeholder",
            "AI_BASE_URL": "https://generativelanguage.googleapis.com/v1beta/openai",
            "AI_MODEL": "gemini-3.5-flash-lite",
        },
    )
    text = env_file.read_text(encoding="utf-8")
    assert "AUTH_PROVIDER=local" in text
    assert "CUSTOM_FLAG=keep" in text
    assert "AI_PROVIDER=gemini" in text
    assert "AI_API_KEY=secret-placeholder" in text
    assert "AI_MODEL=gemini-3.5-flash-lite" in text


def test_system_ai_test_permissions_and_live_probe(client, headers, monkeypatch):
    creator_res = client.post("/api/v1/system/ai-test", headers=headers["creator"])
    assert creator_res.status_code == 403

    disabled_res = client.post("/api/v1/system/ai-test", headers=headers["reviewer"])
    assert disabled_res.status_code == 200
    disabled_body = disabled_res.json()
    assert disabled_body["configured"] is False
    assert disabled_body["live_ok"] is False
    assert disabled_body["status"] == "abstained"

    class _FakeResp:
        status_code = 200
        is_error = False
        text = ""

        @staticmethod
        def json():
            return {
                "choices": [
                    {
                        "finish_reason": "stop",
                        "message": {
                            "content": json.dumps(
                                {
                                    "status": "supported",
                                    "message": "Matches the SLA reference.",
                                    "citations": [
                                        {
                                            "passage_id": "ai-probe-fact:0",
                                            "quote": "Acme Enterprise includes a 99.95% uptime SLA and costs $49 per month.",
                                        }
                                    ],
                                    "findings": [],
                                }
                            )
                        },
                    }
                ]
            }

    monkeypatch.setattr(config, "AI_PROVIDER", "gemini")
    monkeypatch.setattr(config, "AI_API_KEY", "test-only-key")
    monkeypatch.setattr(
        config,
        "AI_BASE_URL",
        "https://generativelanguage.googleapis.com/v1beta/openai",
    )
    monkeypatch.setattr(config, "AI_MODEL", "gemini-3.5-flash-lite")
    monkeypatch.setattr(httpx, "post", lambda *args, **kwargs: _FakeResp())

    live_res = client.post("/api/v1/system/ai-test", headers=headers["reviewer"])
    assert live_res.status_code == 200
    live_body = live_res.json()
    assert live_body["configured"] is True
    assert live_body["provider"] == "gemini"
    assert live_body["live_ok"] is True
    assert live_body["status"] == "supported"


def test_manage_test_ai_cli_isolated(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "BACKEND_DIR", tmp_path)
    for var in (
        "AI_PROVIDER",
        "AI_API_KEY",
        "AI_BASE_URL",
        "AI_MODEL",
        "GEMINI_API_KEY",
        "GOOGLE_API_KEY",
        "OPENROUTER_API_KEY",
        "OPENAI_API_KEY",
    ):
        monkeypatch.delenv(var, raising=False)

    assert manage.test_ai_live() == 1
