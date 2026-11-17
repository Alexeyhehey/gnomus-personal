#!/usr/bin/env python3
"""Самопроверка Гномуса: всё ли на месте. Ничего не меняет, личные файлы не читает (только наличие и дату).

    python tools/doctor.py

Строки: [ok] / [!!] (сломано, надо чинить) / [..] (не подключено, но не страшно). Код выхода 1 — есть [!!].
"""
from __future__ import annotations

import json
import shutil
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path.home()
G = Path(__file__).resolve().parent.parent
SKILLS = ("znakomstvo", "utro", "idei", "zdorovie", "apteka", "dengi", "zarabotok", "rabota", "dokumenty",
          "novyi-navyk", "alexu", "obnovlenie", "moduli", "bezopasnost", "gorod", "itogi", "telefon")
LIFE = ("profile.md", "health.md", "meds.md", "money.md", "work.md", "journal.md")
bad = 0


def say(level: str, text: str) -> None:
    global bad
    bad += level == "!!"
    print(f"[{level}] {text}")


def main() -> int:
    for s in (sys.stdout, sys.stderr):
        s.reconfigure(encoding="utf-8", errors="replace")

    say("ok" if (G / "CLAUDE.md").is_file() else "!!", f"прошивка {G / 'CLAUDE.md'}")
    missing = [f for f in LIFE if not (G / "life" / f).is_file()]
    say("ok" if not missing else "!!", "память life/: " + ("все файлы на месте" if not missing else "нет " + ", ".join(missing)))
    prof = G / "life" / "profile.md"
    if prof.is_file():
        filled = "СТАТУС: заполнен" in prof.read_text(encoding="utf-8", errors="replace")[:400]
        say("ok" if filled else "..", "знакомство: " + ("пройдено" if filled else "ещё не пройдено — напиши «привет»"))

    g = HOME / ".claude" / "CLAUDE.md"
    say("ok" if g.is_file() and "Gnomus" in g.read_text(encoding="utf-8", errors="replace") else "!!", "общая заметка ~/.claude/CLAUDE.md (чтобы Гномус работал из любой папки)")
    lost = [s for s in SKILLS if not (HOME / ".claude" / "skills" / s / "SKILL.md").is_file()]
    say("ok" if not lost else "!!", "скиллы: " + (f"все {len(SKILLS)} на месте" if not lost else "нет " + ", ".join(lost)))

    try:
        with urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=5) as r:
            models = [m["name"] for m in json.load(r).get("models", [])]
        say("ok" if models else "..", "локальная модель: " + (", ".join(models) if models else "сервер жив, моделей нет"))
    except (urllib.error.URLError, OSError, ValueError):
        say("..", "локальная модель не отвечает — запусти задачу GnomusOllama или перезайди в Windows; пока работаю без неё")

    sys.path.insert(0, str(G / "tools"))
    try:
        import ask_free
        have = [k for k in ask_free.KEYS if ask_free.setting(k)]
        say("ok" if have else "..", "бесплатные облачные модели: " + (", ".join(k.split("_")[0].lower() for k in have) if have else "не подключены (tools\\add_key.cmd)"))
    except Exception as e:  # noqa: BLE001 — самопроверка не должна падать
        say("!!", f"tools/ask_free.py не загрузился: {type(e).__name__}")

    zips = sorted((HOME / "Gnomus-backup").glob("life-*.zip"))
    if zips:
        age = (time.time() - zips[-1].stat().st_mtime) / 3600
        say("ok" if age < 50 else "!!", f"копия памяти: {zips[-1].name}, {age:.0f} ч назад, всего {len(zips)}")
    else:
        say("..", "копий памяти ещё нет (первая появится вечером; вручную: tools\\backup_life.ps1)")

    free = shutil.disk_usage(G).free / 2**30
    say("ok" if free > 10 else "!!", f"свободно на диске: {free:.0f} ГБ")
    print("итог: " + ("всё в порядке" if not bad else f"нужно починить: {bad}"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
