"""Tests for the clickstream OneLake shortcut helper."""

from __future__ import annotations

from deploy.scripts import configure_shortcuts as cs


class _Resp:
    def __init__(self, status_code: int, payload: dict | None = None, text: str = ""):
        self.status_code = status_code
        self._payload = payload or {}
        self.text = text

    def json(self) -> dict:
        return self._payload


def test_create_shortcut_posts_expected_body(monkeypatch) -> None:
    captured: dict = {}

    def fake_post(url, headers, json, timeout):  # noqa: A002 - mirror requests API
        captured["url"] = url
        captured["json"] = json
        return _Resp(201)

    import requests

    monkeypatch.setattr(requests, "post", fake_post)

    cs.create_shortcut(
        workspace_id="ws",
        lakehouse_id="lh",
        schema="bronze",
        shortcut_name="clickstream_events",
        target_item_id="kqldb",
        target_table="clickstream_events",
        credential=_Credential(),
    )

    assert "/workspaces/ws/items/lh/shortcuts" in captured["url"]
    assert "shortcutConflictPolicy=CreateOrOverwrite" in captured["url"]
    body = captured["json"]
    assert body["path"] == "Tables/bronze"
    assert body["name"] == "clickstream_events"
    assert body["target"]["oneLake"] == {
        "workspaceId": "ws",
        "itemId": "kqldb",
        "path": "Tables/clickstream_events",
    }


def test_create_shortcut_retries_then_succeeds(monkeypatch) -> None:
    responses = [
        _Resp(404, {"errorCode": "EntityNotFound"}, "target not found"),
        _Resp(201),
    ]
    calls = {"n": 0}

    def fake_post(url, headers, json, timeout):  # noqa: A002
        calls["n"] += 1
        return responses.pop(0)

    import requests

    monkeypatch.setattr(requests, "post", fake_post)
    monkeypatch.setattr(cs.time, "sleep", lambda _s: None)

    cs.create_shortcut(
        workspace_id="ws",
        lakehouse_id="lh",
        schema="bronze",
        shortcut_name="clickstream_events",
        target_item_id="kqldb",
        target_table="clickstream_events",
        credential=_Credential(),
        retries=3,
        retry_interval=0,
    )

    assert calls["n"] == 2


def test_create_shortcut_raises_after_exhausting_retries(monkeypatch) -> None:
    import requests

    monkeypatch.setattr(
        requests, "post", lambda *a, **k: _Resp(404, {}, "still not found")
    )
    monkeypatch.setattr(cs.time, "sleep", lambda _s: None)

    try:
        cs.create_shortcut(
            workspace_id="ws",
            lakehouse_id="lh",
            schema="bronze",
            shortcut_name="clickstream_events",
            target_item_id="kqldb",
            target_table="clickstream_events",
            credential=_Credential(),
            retries=2,
            retry_interval=0,
        )
    except RuntimeError as exc:
        assert "Failed to create clickstream shortcut" in str(exc)
    else:  # pragma: no cover - the call must raise
        raise AssertionError("expected RuntimeError")


def test_configure_enables_availability_then_creates_shortcut(monkeypatch) -> None:
    calls: list[str] = []

    monkeypatch.setattr(
        cs,
        "enable_onelake_availability",
        lambda **kw: calls.append(f"enable:{kw['table_name']}"),
    )
    monkeypatch.setattr(
        cs, "create_shortcut", lambda **kw: calls.append(f"shortcut:{kw['schema']}")
    )

    rc = cs.configure(
        workspace_id="ws",
        lakehouse_id="lh",
        schema="bronze",
        shortcut_name="clickstream_events",
        target_item_id="kqldb",
        target_table="clickstream_events",
        credential=_Credential(),
    )

    assert rc == 0
    assert calls == ["enable:clickstream_events", "shortcut:bronze"]


class _Credential:
    def get_token(self, _scope: str):  # noqa: D401 - test stub
        class _Token:
            token = "fake"

        return _Token()
