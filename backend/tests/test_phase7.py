"""Phase 7 operations tests: secret files."""

import os

from app.config import _load_secret_files


def test_secret_loaded_from_file(tmp_path, monkeypatch):
    key_file = tmp_path / "admin_key"
    key_file.write_text("from-file\n", encoding="utf-8")

    monkeypatch.delenv("ADMIN_API_KEY", raising=False)
    monkeypatch.setenv("ADMIN_API_KEY_FILE", str(key_file))
    try:
        _load_secret_files()
        assert os.environ["ADMIN_API_KEY"] == "from-file"
    finally:
        os.environ.pop("ADMIN_API_KEY", None)


def test_explicit_env_beats_secret_file(tmp_path, monkeypatch):
    monkeypatch.setenv("ADMIN_API_KEY", "explicit")
    monkeypatch.setenv("ADMIN_API_KEY_FILE", str(tmp_path / "missing"))
    try:
        _load_secret_files()
        assert os.environ["ADMIN_API_KEY"] == "explicit"
    finally:
        os.environ.pop("ADMIN_API_KEY", None)


def test_missing_secret_file_is_ignored(tmp_path, monkeypatch):
    monkeypatch.delenv("AUTH_SECRET_KEY", raising=False)
    monkeypatch.setenv("AUTH_SECRET_KEY_FILE", str(tmp_path / "absent"))
    _load_secret_files()  # must not raise
    assert "AUTH_SECRET_KEY" not in os.environ
