#!/usr/bin/env python3
"""Спросить бесплатную локальную модель (Ollama на этом ПК). Наружу ничего не уходит.

    python tools/ask_local.py "придумай 10 заголовков для объявления о ..."
    python tools/ask_local.py -f inbox/текст.txt "перескажи в 5 пунктах"
    python tools/ask_local.py --kind code "напиши функцию ..."
    python tools/ask_local.py --list

Ответ печатается в stdout. Код выхода 1 — модель недоступна (тогда делай сам).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

HOST = "http://127.0.0.1:11434"
PREFS = {  # тип задачи -> модели по убыванию предпочтения
    "text": ("gemma4:12b", "qwen3:8b", "qwen2.5-coder:14b"),
    "code": ("qwen2.5-coder:14b", "qwen3:8b", "gemma4:12b"),
}
FILE_BUDGET = 60_000  # символов файла в запросе


def call(path: str, body: dict | None = None, timeout: int = 10) -> dict:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(HOST + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def models() -> list[str]:
    return [m["name"] for m in call("/api/tags").get("models", [])]


def wake() -> list[str]:
    """Модели; если сервер спит — попробовать разбудить задачей Планировщика и подождать."""
    try:
        return models()
    except (urllib.error.URLError, OSError):
        pass
    subprocess.run(["schtasks", "/run", "/tn", "GnomusOllama"], capture_output=True)
    for _ in range(15):
        time.sleep(2)
        try:
            return models()
        except (urllib.error.URLError, OSError):
            continue
    return []


def main() -> int:
    for s in (sys.stdout, sys.stderr):
        s.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("task", nargs="?", help="что сделать")
    ap.add_argument("-f", "--file", action="append", default=[], help="файл с материалом (можно несколько)")
    ap.add_argument("--kind", choices=sorted(PREFS), default="text")
    ap.add_argument("--model", help="конкретная модель вместо автовыбора")
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--list", action="store_true", help="показать доступные модели")
    a = ap.parse_args()

    have = wake()
    if a.list:
        print("\n".join(have) if have else "локальная модель недоступна")
        return 0 if have else 1
    if not a.task:
        ap.error("нужна задача")
    if not have:
        print("локальная модель недоступна (Ollama не отвечает)", file=sys.stderr)
        return 1
    model = a.model or next((m for m in PREFS[a.kind] if m in have), have[0])

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
    ctx = min(32768, max(8192, 1 << (len(prompt) // 2 + 6000).bit_length()))  # ~2 символа на токен + место под ответ

    try:
        r = call("/api/generate", {"model": model, "prompt": prompt, "stream": False,
                                   "options": {"num_ctx": ctx, "temperature": 0.4}}, timeout=a.timeout)
    except (urllib.error.URLError, OSError) as e:
        print(f"локальная модель не ответила: {e}", file=sys.stderr)
        return 1
    answer = re.sub(r"<think>.*?</think>|<thought>.*?</thought>", "", r.get("response", ""), flags=re.S).strip()
    print(answer)
    print(f"[{model}, {r.get('eval_count', '?')} токенов]", file=sys.stderr)
    return 0 if answer else 1


if __name__ == "__main__":
    sys.exit(main())
