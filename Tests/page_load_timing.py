#!/usr/bin/env python3
"""How long pages take to load, in a hidden probe: a number to hold a change
to what Relay puts into every page against.

    RELAY_PROBE_APP="$(./probe.sh)" python3 Tests/page_load_timing.py [RUNS] [LABEL]

Three local pages, served from two origins (127.0.0.1 and localhost, so the
frames are cross-origin and a tab going from one to the other crosses sites):

    plain    a short page
    frames   a page of 20 cross-origin iframes, as ads and embeds are
    form     a sign-in form, which the password scripts look at

Each is timed two ways, RUNS times, interleaved: in a new bench tab (a web
view made for it) and in a tab already open that comes from the other
origin. What is read is the page's own navigation timing: `dcl`
(DOMContentLoaded end) and `load` (load event end), in ms from the start of
the navigation; and `wall`, from asking for the page to the bench saying it
has loaded. Medians, with the 10th and 90th percentiles. The probe's world
is removed afterwards. Nothing is shown or brought forward.
"""
import json
import statistics
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

RUNS = int(sys.argv[1]) if len(sys.argv) > 1 else 15
LABEL = sys.argv[2] if len(sys.argv) > 2 else ""
FRAMES = 20


class Pages(BaseHTTPRequestHandler):
    def do_GET(self):
        port = self.server.server_port
        # The other origin: frames are served from the one the page is not on.
        other = "localhost" if self.headers.get("Host", "").startswith("127.") else "127.0.0.1"
        path = self.path.split("?")[0]
        if path == "/frames":
            frames = "".join(f"<iframe src='http://{other}:{port}/leaf?{n}' width=120 height=60></iframe>" for n in range(FRAMES))
            body = f"<!doctype html><title>frames</title><p>frames</p>{frames}"
        elif path == "/form":
            body = ("<!doctype html><title>form</title><form action='/plain' method='post'>"
                    "<input name='user' type='email' autocomplete='username'>"
                    "<input name='pass' type='password' autocomplete='current-password'>"
                    "<button>Sign in</button></form>")
        elif path == "/leaf":
            body = "<!doctype html><title>leaf</title><p>leaf</p><script>var x = 1</script>"
        else:
            body = "<!doctype html><title>plain</title>" + "<p>Some words on a plain page.</p>" * 40
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Pages)
threading.Thread(target=server.serve_forever, daemon=True).start()
PORT = server.server_port
A, B = f"http://127.0.0.1:{PORT}", f"http://localhost:{PORT}"

TIMING = ("(function(){var t=performance.getEntriesByType('navigation')[0];"
          "return JSON.stringify({dcl:t.domContentLoadedEventEnd-t.startTime,load:t.loadEventEnd-t.startTime})})()")


def read(tab):
    """The page's timing, once its load event has ended."""
    for _ in range(100):
        try:
            value = sv.cmd({"do": "eval", "id": tab, "js": TIMING})
            got = json.loads(value.get("result") or value.get("value") or "{}")
            if got.get("load", 0) > 0:
                return got
        except (RuntimeError, ValueError, TypeError):
            pass
        time.sleep(0.02)
    return None


def loaded(tab, began):
    sv.cmd({"do": "wait", "id": tab, "seconds": 15})
    wall = (time.perf_counter() - began) * 1000
    got = read(tab)
    return None if got is None else {**got, "wall": wall}


def new_tab(page):
    began = time.perf_counter()
    tab = sv.cmd({"do": "open", "url": f"{A}/{page}"})["id"]
    got = loaded(tab, began)
    sv.cmd({"do": "close", "id": tab})
    return got


def same_tab(tab, page, origin):
    began = time.perf_counter()
    sv.cmd({"do": "go", "id": tab, "url": f"{origin}/{page}?{time.time()}"})
    return loaded(tab, began)


def spread(values):
    values = sorted(values)
    pick = lambda q: values[min(len(values) - 1, int(q * len(values)))]
    return f"{statistics.median(values):7.1f}  ({pick(0.1):.1f} to {pick(0.9):.1f})"


def main():
    sv.use("load-timing")
    sv.setup()
    sv.launch()
    results = {}
    try:
        # One load of each first, uncounted: the first of anything is the slow one.
        for page in ("plain", "frames", "form"):
            new_tab(page)
        kept = sv.cmd({"do": "open", "url": f"{B}/plain"})["id"]
        loaded(kept, time.perf_counter())
        for run in range(RUNS):
            for page in ("plain", "frames", "form"):
                for kind, got in (("new tab", new_tab(page)),
                                  ("same tab", same_tab(kept, page, A if run % 2 == 0 else B))):
                    if got: results.setdefault((page, kind), []).append(got)
        sv.cmd({"do": "close", "id": kept})
    finally:
        sv.finish()
    print(f"page load timing{' — ' + LABEL if LABEL else ''}: {RUNS} runs each, ms, median (10th to 90th percentile)")
    print(f"{'page':8} {'how':9} {'n':>3}  {'dcl':24} {'load':24} {'wall':24}")
    summary = {}
    for (page, kind), rows in sorted(results.items()):
        cells = [spread([r[key] for r in rows]) for key in ("dcl", "load", "wall")]
        summary[f"{page}/{kind}"] = {key: statistics.median(r[key] for r in rows) for key in ("dcl", "load", "wall")}
        print(f"{page:8} {kind:9} {len(rows):>3}  {cells[0]:24} {cells[1]:24} {cells[2]:24}")
    print("json:", json.dumps(summary))


if __name__ == "__main__":
    main()
