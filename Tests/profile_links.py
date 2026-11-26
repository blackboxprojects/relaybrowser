#!/usr/bin/env python3
"""A link another app sends to a profile it names
(relay://open?profile=<id>&url=<address>, Links.named), checked in a hidden
probe.

Build first (`./build.sh`), then `python3 Tests/profile_links.py`. The app
starts hidden in a world of its own (see split_view.use), is driven through
./bench's socket, and is quit; its world is removed afterwards. Local pages
only, from 127.0.0.1. Links are handed over the way macOS hands them (the
bench's `windows link`).

With Personal in front and a second profile, Work, with no window open, once
with Profiles in one window off and once on:

- a link sent to Work opens as a tab of a window of Work, which comes in
  front, and Personal's tabs stay as they were;
- the next one opens in the same window, not a second;
- one sent to Personal, with Work in front, opens in Personal's window;
- one with a profile nobody has, and one with none, open where a link from
  another app opens: in the window in front;
- one whose address isn't http or https opens nothing at all.

Then, with Ask which space on and links opening in small windows: a link
sent to Work still opens as a tab of Work's window, nothing asked and no
small window, while an ordinary link is asked about.

Last, a launch a link sent to Work makes (SEARCH_LINK): the page is in a
window of Work.

Nothing here brings a window onto a screen.
"""
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("profile-links")


def c(req): return sv.cmd(req)
def windows(): return c({"do": "windows"})["windows"]
def of(name): return [w for w in windows() if w["profile"] == name and (w["open"] or w["tucked"])]
def tabs(name): return [u for w in of(name) for u in w["tabs"]]
def front(): return next((w["profile"] for w in windows() if w["front"]), None)


def sent(url, profile=None):
    link = "relay://open?" + (f"profile={profile}&" if profile is not None else "") + "url=" + quote(url, safe="")
    c({"do": "windows", "action": "link", "url": link, "sender": "Caddie"})
    time.sleep(1.5)


def off_screen(t, label):
    up = [w for w in windows() if w.get("shown")]
    t.ok(f"no window on screen ({label})", not up, up)
    if up:
        sv.quit()
        sys.exit("a window reached the screen: stopped")


def case(t, one_window):
    label = "one window" if one_window else "own windows"
    print(f"-- profiles in {label}")
    page = lambda name: f"{sv.BASE}/{'one' if one_window else 'own'}-{name}"
    sv.quit()
    sv.setup(**{"spaces": True, "profiles.oneWindow": one_window})
    sv.launch()
    work = c({"do": "profile", "action": "new", "name": "Work"})["id"]
    time.sleep(0.8)
    c({"do": "open", "url": page("mine")}); time.sleep(1)
    mine = tabs("Personal")
    t.ok(f"[{label}] Work has no window to begin with", of("Work") == [], windows())

    sent(page("first"), work)
    off_screen(t, f"{label}, to Work")
    t.ok(f"[{label}] a link sent to Work opens in a window of Work", page("first") in tabs("Work"), windows())
    t.ok(f"[{label}] which comes in front", front() == "Work", windows())
    t.ok(f"[{label}] Personal's tabs stay as they were", tabs("Personal") == mine, tabs("Personal"))

    sent(page("second"), work.lower())
    t.ok(f"[{label}] the next one opens in the same window",
         len(of("Work")) == 1 and {page("first"), page("second")} <= set(tabs("Work")), windows())

    personal = "00000000-0000-0000-0000-0000000000A1"
    sent(page("home"), personal)
    off_screen(t, f"{label}, to Personal")
    # Not which is in front: a hidden probe's window, already open, never
    # becomes key on its own (see the bench's `windows front`).
    t.ok(f"[{label}] one sent to Personal, with Work in front, opens in Personal's",
         page("home") in tabs("Personal") and page("home") not in tabs("Work"), windows())

    sent(page("third"), work)
    t.ok(f"[{label}] and back to Work", page("third") in tabs("Work") and front() == "Work", windows())
    sent(page("nobody"), str(uuid.uuid4()))
    t.ok(f"[{label}] a profile nobody has: where any link opens, the window in front",
         page("nobody") in tabs("Work") and page("nobody") not in tabs("Personal"), windows())
    sent(page("unnamed"))
    sent(page("broken"), "work")
    t.ok(f"[{label}] and so with no profile, or one that isn't an id",
         {page("unnamed"), page("broken")} <= set(tabs("Work")), windows())

    before = [(w["profile"], w["tabs"]) for w in windows()]
    for address in ["file:///etc/hosts", "javascript:alert(1)", "relay://open?url=" + quote(page("twice"), safe="")]:
        sent(address, work)
    t.ok(f"[{label}] an address that isn't http or https opens nothing",
         [(w["profile"], w["tabs"]) for w in windows()] == before, windows())
    off_screen(t, label)


def case_asking(t):
    print("-- asking which space, links in small windows")
    page = lambda name: f"{sv.BASE}/ask-{name}"
    sv.quit()
    sv.setup(**{"spaces": True, "links.ask": True, "links.little": True})
    sv.launch()
    work = c({"do": "profile", "action": "new", "name": "Work"})["id"]
    time.sleep(0.8)
    littles = lambda: c({"do": "little", "what": "look"}).get("littles") or []
    asked = lambda: c({"do": "chooser", "action": "look"})
    sent(page("chosen"), work)
    t.ok("a link sent to Work opens as a tab of Work's window",
         page("chosen") in tabs("Work"), windows())
    t.ok("nothing asked, and no small window", not asked()["shown"] and not littles(), (asked(), littles()))
    c({"do": "windows", "action": "link", "url": page("plain"), "sender": "Caddie"}); time.sleep(1.5)
    t.ok("while an ordinary link is asked about",
         asked()["shown"] and asked()["url"] == page("plain") and page("plain") not in tabs("Work") + tabs("Personal"),
         (asked(), windows()))
    off_screen(t, "asking")


def case_launch(t):
    print("-- a launch the link makes")
    page = f"{sv.BASE}/launched"
    sv.quit()
    sv.setup(spaces=True)
    sv.launch()
    work = c({"do": "profile", "action": "new", "name": "Work"})["id"]
    time.sleep(0.8)
    sv.quit()
    sv.launch(link="relay://open?profile=" + work + "&url=" + quote(page, safe=""))
    time.sleep(2)
    t.ok("the page is in a window of Work", page in tabs("Work") and page not in tabs("Personal"), windows())
    off_screen(t, "launch")


def main():
    t = sv.T()
    try:
        case(t, False)
        case(t, True)
        case_asking(t)
        case_launch(t)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
