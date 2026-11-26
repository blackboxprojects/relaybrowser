#!/usr/bin/env python3
"""A link another app sends to a space it names
(relay://open?space=<id>&url=<address>, Links.named), checked in a hidden
probe.

Build first (`./build.sh`), then `python3 Tests/named_space_links.py`. The
app starts hidden in a world of its own (see split_view.use), is driven
through ./bench's socket, and is quit; its world is removed afterwards.
Local pages only, from 127.0.0.1 and localhost. Links are handed over the
way macOS hands them (the bench's `windows link`).

One profile with three spaces, the last of them, Home, on screen:

- a link sent to Family opens as a tab there, the window now showing Family;
- the next one opens beside it;
- one sent to Home opens in Home, and Family's pages aren't there;
- one with a space nobody has, one that isn't an id and one with none open
  where a link from another app opens: in the space on screen;
- one naming a space and a profile opens in the space;
- one whose address isn't http or https opens nothing at all.

Then, with Ask which space on, links opening in small windows and a rule
sending localhost to Home: a link to localhost sent to Family opens as a tab
in Family, nothing asked, no small window and the rule not followed, while
an ordinary link is asked about.

Then a launch a link sent to Family makes (SEARCH_LINK): the page is in
Family, though Home was on screen at the last quit.

Last, with Spaces turned off: the link opens as any link does.

Nothing here brings a window onto a screen.
"""
import subprocess
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("named-space-links")

PERSONAL = "00000000-0000-0000-0000-0000000000A1"


def c(req): return sv.cmd(req)
def windows(): return c({"do": "windows"})["windows"]
def space(action, **f): return c({"do": "space", "action": action, **f})
def front(): return next((w for w in windows() if w["front"]), None) or windows()[0]
def on_screen(): return front()["space"]
def tabs(): return front()["tabs"]


def sent(url, space_id=None, profile=None):
    named = "".join(f"{k}={v}&" for k, v in (("profile", profile), ("space", space_id)) if v is not None)
    c({"do": "windows", "action": "link", "url": "relay://open?" + named + "url=" + quote(url, safe=""), "sender": "Caddie"})
    time.sleep(1.5)


def off_screen(t, label):
    up = [w for w in windows() if w.get("shown")]
    t.ok(f"no window on screen ({label})", not up, up)
    if up:
        sv.quit()
        sys.exit("a window reached the screen: stopped")


def seed(**prefs):
    """Family and Home made after the first space, and Home on screen.
    The ids of Family and Home."""
    sv.quit()
    sv.setup(**{"spaces": True, **prefs})
    sv.launch()
    space("new", name="Family", fresh=True); time.sleep(0.8)
    space("new", name="Home", fresh=True); time.sleep(0.8)
    listed = space("list")["spaces"]
    return [next(s["id"] for s in listed if s["name"] == name) for name in ("Family", "Home")]


def case_plain(t):
    print("-- a space named")
    page = lambda name: f"{sv.BASE}/plain-{name}"
    family, home = seed()
    c({"do": "open", "url": page("mine")}); time.sleep(1)
    t.ok("Home on screen to begin with", on_screen() == "Home", windows())

    sent(page("first"), family)
    off_screen(t, "to Family")
    t.ok("a link sent to Family opens as a tab there", on_screen() == "Family" and page("first") in tabs(), windows())
    sent(page("second"), family.lower())
    t.ok("the next one opens beside it",
         on_screen() == "Family" and {page("first"), page("second")} <= set(tabs()) and len(windows()) == 1, windows())

    sent(page("home"), home)
    t.ok("one sent to Home opens in Home", on_screen() == "Home" and {page("mine"), page("home")} <= set(tabs()), windows())
    t.ok("where Family's pages aren't", not {page("first"), page("second")} & set(tabs()), tabs())

    sent(page("nobody"), str(uuid.uuid4()))
    sent(page("broken"), "Family")
    sent(page("unnamed"))
    t.ok("a space nobody has, one that isn't an id, and none: the space on screen",
         on_screen() == "Home" and {page("nobody"), page("broken"), page("unnamed")} <= set(tabs()), windows())

    sent(page("both"), family, PERSONAL)
    t.ok("a space and a profile: the space", on_screen() == "Family" and page("both") in tabs(), windows())
    sent(page("both-lost"), family, str(uuid.uuid4()))
    t.ok("whatever the profile", on_screen() == "Family" and page("both-lost") in tabs(), windows())

    before = [(w["space"], w["tabs"]) for w in windows()]
    for address in ["file:///etc/hosts", "javascript:alert(1)", "relay://open?url=" + quote(page("twice"), safe="")]:
        sent(address, home)
    t.ok("an address that isn't http or https opens nothing",
         [(w["space"], w["tabs"]) for w in windows()] == before, windows())
    off_screen(t, "plain")


def case_asking(t):
    print("-- asking which space, links in small windows, and a rule")
    family, home = seed(**{"links.ask": True, "links.little": True, "spaces.links": True})
    # The rule, written as Settings writes it, read at the next launch.
    sv.quit(); time.sleep(1)
    subprocess.run(["defaults", "write", sv.SUITE, "spaces.links.rules", "-array",
                    f'{{ site = localhost; space = "{home}"; }}'], check=True)
    sv.launch(); time.sleep(1)
    ruled = f"http://localhost:{sv.srv.server_port}/ask-ruled"
    plain = f"{sv.BASE}/ask-plain"
    littles = lambda: c({"do": "little", "what": "look"}).get("littles") or []
    asked = lambda: c({"do": "chooser", "action": "look"})
    sent(ruled, family)
    t.ok("a link sent to Family opens as a tab in Family, not where the rule says",
         on_screen() == "Family" and ruled in tabs(), windows())
    t.ok("nothing asked, and no small window", not asked()["shown"] and not littles(), (asked(), littles()))
    c({"do": "windows", "action": "link", "url": plain, "sender": "Caddie"}); time.sleep(1.5)
    t.ok("while an ordinary link is asked about",
         asked()["shown"] and asked()["url"] == plain and plain not in tabs(), (asked(), windows()))
    off_screen(t, "asking")


def case_launch(t):
    print("-- a launch the link makes")
    page = f"{sv.BASE}/launched"
    family, _ = seed()
    sv.quit()
    sv.launch(link="relay://open?space=" + family + "&url=" + quote(page, safe=""))
    time.sleep(2)
    t.ok("the page is in Family", on_screen() == "Family" and page in tabs(), windows())
    off_screen(t, "launch")


def case_off(t):
    print("-- Spaces turned off")
    page = f"{sv.BASE}/off"
    family, _ = seed()
    sv.quit(); time.sleep(1)
    subprocess.run(["defaults", "write", sv.SUITE, "spaces", "-bool", "false"], check=True)
    sv.launch(); time.sleep(1)
    sent(page, family)
    t.ok("the link opens as any link does", page in tabs(), windows())
    off_screen(t, "off")


def main():
    t = sv.T()
    try:
        case_plain(t)
        case_asking(t)
        case_launch(t)
        case_off(t)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
