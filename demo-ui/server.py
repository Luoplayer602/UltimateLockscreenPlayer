#!/usr/bin/env python3
"""Local demo server for visualizer, lyrics, translation and YouTube thumbnails."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request, urlopen
import json
import argparse
import errno
import re

ROOT = Path(__file__).resolve().parent
UPSTREAM = "https://unison.betterlyrics.org"
MAX_BODY = 120_000
GOOGLE_TRANSLATE = "https://translate.googleapis.com/translate_a/single"
TRANSLATION_SEPARATOR = "\n\n;\n\n"
TRANSLITERATION_SEPARATOR = "0000"
NON_LATIN_SCRIPT = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]")


def fetch_json(request):
    try:
        with urlopen(request, timeout=15) as response:
            try:
                return response.status, json.load(response)
            except (ValueError, UnicodeDecodeError):
                return 502, {"error": "Upstream returned non-JSON content"}
    except HTTPError as error:
        try:
            return error.code, json.load(error)
        except (ValueError, UnicodeDecodeError):
            return error.code, {"error": "Upstream returned a non-JSON error"}


def google_request(params):
    target = GOOGLE_TRANSLATE + "?" + urlencode(params, doseq=True)
    status, data = fetch_json(Request(target, headers={"Accept": "application/json", "User-Agent": "ULP-Lyrics-API-Demo/1.0"}))
    if status != 200 or not isinstance(data, list) or not data or not isinstance(data[0], list):
        raise ValueError(f"Google Translate returned HTTP {status}")
    return data[0]


def fallback_translate(lines, to, source, need_translation=True):
    result = [{"translation": None, "romanization": None, "needsTranslation": False} for _ in lines]
    warnings = []
    source = source or ("ja" if any(re.search(r"[\u3040-\u30ff]", line) for line in lines) else
                        "ko" if any(re.search(r"[\uac00-\ud7af]", line) for line in lines) else
                        "zh-CN" if any(re.search(r"[\u4e00-\u9fff]", line) for line in lines) else "auto")
    # Small batches keep query URLs short; never assign text to a line if separators are lost.
    for start in range(0, len(lines), 5):
        batch = lines[start:start + 5]
        indexed = [(i, line) for i, line in enumerate(batch) if line.strip() and line.strip() != "♪"]
        if not indexed:
            continue
        texts = [line for _, line in indexed]
        if need_translation:
            try:
                parts = google_request({"client": "gtx", "sl": "auto", "tl": to, "dt": "t", "q": TRANSLATION_SEPARATOR.join(texts)})
                translated = "".join(str(part[0]) for part in parts if isinstance(part, list) and part and part[0] is not None)
                split = [line.strip() for line in translated.split(TRANSLATION_SEPARATOR)]
                if len(split) != len(texts):
                    raise ValueError(f"Expected {len(texts)} translation lines, got {len(split)}")
                for (offset, original), value in zip(indexed, split):
                    if value and value.casefold() != original.casefold():
                        result[start + offset]["translation"] = value
                        result[start + offset]["needsTranslation"] = True
            except (URLError, TimeoutError, ValueError, TypeError) as error:
                warnings.append(f"Translation batch {start // 5 + 1}: {error}")
        non_latin = [(offset, line) for offset, line in indexed if NON_LATIN_SCRIPT.search(line)]
        if not non_latin or source == "auto":
            continue
        texts = [line for _, line in non_latin]
        try:
            parts = google_request({"client": "gtx", "sl": source, "tl": source + "-Latn", "dt": ["t", "rm"], "q": (" " + TRANSLITERATION_SEPARATOR + " ").join(texts)})
            romanized = "".join(str(part[3] if len(part) > 3 and part[3] else part[2] if len(part) > 2 and part[2] else "") for part in parts if isinstance(part, list))
            split = [line.strip() for line in re.split(r"\s*" + TRANSLITERATION_SEPARATOR + r"\s*", romanized)]
            if len(split) != len(texts):
                raise ValueError(f"Expected {len(texts)} romanization lines, got {len(split)}")
            for (offset, original), value in zip(non_latin, split):
                if value and value.casefold() != original.casefold():
                    result[start + offset]["romanization"] = value
        except (URLError, TimeoutError, ValueError, TypeError) as error:
            warnings.append(f"Romanization batch {start // 5 + 1}: {error}")
    return {"lines": result, "detectedLang": source, "provider": "google-translate-fallback", "warnings": warnings}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def reply(self, status, body, content_type="application/json; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def proxy(self, request):
        try:
            with urlopen(request, timeout=15) as response:
                self.reply(response.status, response.read(MAX_BODY), response.headers.get("Content-Type", "application/json"))
        except HTTPError as error:
            self.reply(error.code, error.read(MAX_BODY), error.headers.get("Content-Type", "application/json"))
        except (URLError, TimeoutError) as error:
            self.reply(502, json.dumps({"error": str(error)}).encode())

    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == "/api/thumbnail":
            video_id = parse_qs(url.query).get("v", [""])[0]
            if not re.fullmatch(r"[A-Za-z0-9_-]{11}", video_id):
                return self.reply(400, b'{"error":"Invalid YouTube video ID"}')
            try:
                request = Request(f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg", headers={"User-Agent": "ULP-Demo-UI/1.0"})
                with urlopen(request, timeout=15) as response:
                    return self.reply(200, response.read(2_000_000), "image/jpeg")
            except (HTTPError, URLError, TimeoutError) as error:
                return self.reply(502, json.dumps({"error": str(error)}).encode())
        if url.path != "/api/lyrics":
            return super().do_GET()
        raw = parse_qs(url.query, keep_blank_values=False)
        fields = {key: raw[key][0].strip() for key in ("v", "song", "artist", "duration", "album") if key in raw}
        if not fields.get("v") and not (fields.get("song") and fields.get("artist")):
            return self.reply(400, b'{"error":"Provide a video ID or song and artist"}')
        if any(len(value) > 250 for value in fields.values()):
            return self.reply(400, b'{"error":"Query value too long"}')
        if "duration" in fields and not fields["duration"].isdigit():
            return self.reply(400, b'{"error":"Duration must be whole seconds"}')
        target = UPSTREAM + "/lyrics?" + urlencode(fields)
        self.proxy(Request(target, headers={"Accept": "application/json", "User-Agent": "ULP-Lyrics-API-Demo/1.0"}))

    def do_POST(self):
        if urlsplit(self.path).path != "/api/translate":
            return self.reply(404, b'{"error":"Not found"}')
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_BODY:
                raise ValueError("Invalid body size")
            data = json.loads(self.rfile.read(length))
            lines = data.get("lines")
            if not isinstance(lines, list) or not 0 < len(lines) <= 200 or any(not isinstance(x, str) or len(x) > 500 for x in lines):
                raise ValueError("Expected 1–200 lines, each at most 500 characters")
            if not isinstance(data.get("to"), str) or not data["to"].strip():
                raise ValueError("Target language is required")
            payload = {"lines": lines, "to": data["to"].strip()}
            if data.get("from"):
                payload["from"] = str(data["from"]).strip()
            if data.get("videoId"):
                payload["videoId"] = str(data["videoId"]).strip()
        except (ValueError, TypeError, json.JSONDecodeError) as error:
            return self.reply(400, json.dumps({"error": str(error)}).encode())
        body = json.dumps(payload, ensure_ascii=False).encode()
        try:
            upstream_status, upstream_data = fetch_json(Request(UPSTREAM + "/translate", data=body, headers={"Accept": "application/json", "Content-Type": "application/json", "User-Agent": "ULP-Lyrics-API-Demo/1.0"}, method="POST"))
        except (URLError, TimeoutError) as error:
            upstream_status, upstream_data = 502, {"error": str(error)}
        if upstream_status == 200 and isinstance(upstream_data.get("lines"), list):
            if len(upstream_data["lines"]) != len(lines):
                return self.reply(502, b'{"error":"Unison returned a different line count"}')
            missing = [i for i, line in enumerate(lines) if NON_LATIN_SCRIPT.search(line) and not upstream_data["lines"][i].get("romanization")]
            if missing:
                supplement = fallback_translate([lines[i] for i in missing], payload["to"], payload.get("from"), need_translation=False)
                for i, extra in zip(missing, supplement["lines"]):
                    upstream_data["lines"][i]["romanization"] = extra["romanization"]
                upstream_data["provider"] = "unison+google-romanization"
                upstream_data["warnings"] = supplement["warnings"]
            return self.reply(200, json.dumps(upstream_data, ensure_ascii=False).encode())
        fallback = fallback_translate(lines, payload["to"], payload.get("from"))
        fallback["unisonStatus"] = upstream_status
        fallback["unisonError"] = upstream_data.get("error") or upstream_data.get("detail")
        status = 200 if any(line["translation"] or line["romanization"] for line in fallback["lines"]) else 502
        return self.reply(status, json.dumps(fallback, ensure_ascii=False).encode())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run the ULP demo UI with lyrics API")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    except OSError as error:
        if error.errno != errno.EADDRINUSE or args.port != 8765:
            parser.error(f"Không mở được cổng {args.port}: {error}. Thử --port <cổng khác>.")
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        print("Cổng 8765 đang bận; đã chọn cổng trống.", flush=True)
    print(f"ULP demo UI: http://127.0.0.1:{server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
