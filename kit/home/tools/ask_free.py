#!/usr/bin/env python3
"""Спросить бесплатную облачную модель (Groq / OpenRouter / Gemini) по своему ключу хозяйки.

    python tools/ask_free.py --status                      # какие ключи подключены
    python tools/ask_free.py "10 вариантов заголовка для объявления о ..."
    python tools/ask_free.py -f inbox/статья.txt "перескажи в 5 пунктах"

ВНИМАНИЕ: запрос уходит в интернет к чужому сервису. Личное (здоровье, деньги, документы, имена,
адреса) сюда не отправлять — для этого tools/ask_local.py, он работает только на этом ПК.
Ключи: tools\\add_key.cmd <ИМЯ> (скрытый ввод). Код выхода 1 — нет ключей или никто не ответил.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

PROVIDERS = [  # (имя, адрес, переменная с ключом, модель) — по порядку, берётся первый ответивший
    ("groq", "https://api.groq.com/openai/v1/chat/completions", "GROQ_API_KEY", "openai/gpt-oss-120b"),
    ("groq-qwen", "https://api.groq.com/openai/v1/chat/completions", "GROQ_API_KEY", "qwen/qwen3.8-27b"),
    ("openrouter", "https://openrouter.ai/api/v1/chat/completions", "OPENROUTER_API_KEY", "nvidia/nemotron-3-ultra-550b-a55b:free"),
    ("gemma", "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", "GEMINI_API_KEY", "gemma-4-31b-it"),
    ("openrouter-2", "https://openrouter.ai/api/v1/chat/completions", "OPENROUTER_API_KEY", "nvidia/nemotron-3.5-super-vl:free"),
    ("gemini-lite", "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", "GEMINI_API_KEY", "gemini-3.1-flash-lite"),
]
KEYS = ("GROQ_API_KEY", "OPENROUTER_API_KEY", "GEMINI_API_KEY")
FILE_BUDGET = 100_000


def setting(name: str) -> str | None:
    """Переменная окружения; на Windows — ещё и свежее значение из реестра пользователя (без перезапуска приложения)."""
    value = os.environ.get(name)
    if value or sys.platform != "win32":
        return value
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
            return winreg.QueryValueEx(key, name)[0]
    except OSError:
        return None


def main() -> int:
    for s in (sys.stdout, sys.stderr):
        s.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("task", nargs="?")
    ap.add_argument("-f", "--file", action="append", default=[])
    ap.add_argument("--status", action="store_true", help="какие ключи подключены")
    ap.add_argument("--timeout", type=int, default=120)
    a = ap.parse_args()

    have = [k for k in KEYS if setting(k)]
    if a.status:
        for k in KEYS:
            print(f"{k}: {'подключён' if k in have else 'нет'}")
        return 0 if have else 1
    if not a.task:
        ap.error("нужна задача")
    if not have:
        print("облачные бесплатные модели не подключены (нет ключей) — используй tools/ask_local.py", file=sys.stderr)
        return 1

    parts, used = [], 0
    for name in a.file:
        try:
            text = open(name, encoding="utf-8", errors="replace").read()
        except OSError as e:
            print(f"не могу прочитать {name}: {e}", file=sys.stderr)
            return 1
        text = text[: max(0, FILE_BUDGET - used)]
        used += len(text)
        parts.append(f"=== {name} ===\n{text}")
    prompt = ("\n\n".join(parts) + "\n\n" if parts else "") + a.task + "\n\nОтвечай по-русски, по делу, без вступлений."

    log = []
    for prov, url, keyname, model in PROVIDERS:
        key = setting(keyname)
        if not key:
            continue
        body = {"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": 4000, "temperature": 0.3}
        if "gpt-oss" in model or "qwen3" in model:
            body["reasoning_effort"] = "low"
        req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers={
            "Authorization": f"Bearer {key}", "Content-Type": "application/json", "User-Agent": "gnomus-personal/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=a.timeout) as r:
                d = json.load(r)
            answer = re.sub(r"<(think|thought)>.*?</\1>", "", d["choices"][0]["message"]["content"] or "", flags=re.S).strip()
            if answer:
                print(answer)
                print(f"[{prov}: {model}]", file=sys.stderr)
                return 0
            log.append(f"{prov}: пустой ответ")
        except urllib.error.HTTPError as e:
            log.append(f"{prov}: HTTP {e.code}" + (" (лимит, позже)" if e.code == 429 else " (ключ не подходит)" if e.code in (401, 403) else ""))
        except (urllib.error.URLError, OSError, ValueError, KeyError, IndexError) as e:
            log.append(f"{prov}: {type(e).__name__}")
    print("никто не ответил: " + "; ".join(log) + " — используй tools/ask_local.py", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
