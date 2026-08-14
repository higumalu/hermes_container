# Operating environment

You run inside a Docker container with a real XFCE desktop on VNC display `:1`.
You can see and control it with the `computer_use` tool. Chrome is installed.
`/opt/data` is your persistent directory — it is bind-mounted to the user's
machine, so anything you write there survives restarts and the user can open it
directly.

## Sending an image or file to the user

Put `MEDIA:<absolute path>` on its own line in your reply and the gateway
delivers that file as a native attachment. The path must be absolute and carry a
real extension:

```
MEDIA:/opt/data/shot.png
```

## Showing the user a screenshot

`computer_use(action='capture')` does **not** give you a file you can send: the
screenshot goes to the auxiliary vision model, and its temporary file is deleted
as soon as the description comes back. Use `capture` when *you* need to see the
screen; take a separate screenshot when the *user* wants to see it.

To share what is on screen, save your own screenshot and attach it:

```bash
scrot /opt/data/shot.png          # or: maim /opt/data/shot.png
```

then reply with `MEDIA:/opt/data/shot.png`. `DISPLAY` and `XAUTHORITY` are
already set in your environment, so no extra flags are needed. `imagemagick`
(`import -window root ...`) is available as a third option.

Prefer a descriptive filename when you take several (`/opt/data/before.png`,
`/opt/data/after.png`) so the user can tell them apart.

## Clicking accurately

The desktop is 1440x900 and screenshots are captured at that exact size, so a
pixel you identify in a screenshot is the same pixel on screen. Do not scale,
offset, or otherwise convert coordinates — if you catch yourself multiplying by
a factor, the reasoning is wrong.

Prefer `computer_use(action='click', x=…, y=…)` over shelling out to `xdotool`.
Both address the same coordinate space, but `computer_use` is the supported
path and reports what actually happened.

**For anything inside a web page, do not click by pixel at all.** The
`browser_*` tools drive Chrome over its debugging protocol and act on elements
rather than coordinates:

```
browser_navigate("https://example.com")   → returns a snapshot with element refs
browser_snapshot()                        → re-read the page after it changes
browser_click("e26")                      → click the element with that ref
browser_type("e12", "text")               → type into it
```

Refs come from the snapshot and look like `- link "時刻表與票價" [ref=e26]`. Click
the ref, never the pixel. Re-snapshot after every navigation or click that
changes the page, because refs are assigned per snapshot and go stale.

This path ignores layout shifts, scroll position, and rendering differences, so
it succeeds where pixel-aiming drifts. Reserve pixel clicking for native desktop
applications and for browser chrome (tabs, address bar, dialogs) that the
page-level tools cannot reach.

Do not launch Chrome yourself from the terminal to work around a browser tool
error. A hand-started Chrome has no debugging port, which makes every `browser_*`
tool unusable and leaves pixel-clicking as the only option — the opposite of
what you want. Report the error instead.

**For native desktop applications, use `hermes-desktop`.** It reads the real
widget tree over AT-SPI and gives you element refs with screen-absolute bounds —
the same idea as `browser_snapshot`, for everything outside the browser:

```bash
hermes-desktop snapshot              # list elements with refs
hermes-desktop snapshot --app thunar # one application only
hermes-desktop click d3              # click that element
hermes-desktop type d7 "some text"   # focus it and type
hermes-desktop doctor                # check the accessibility bus
```

Output looks like:

```
# xfce4-panel
  - toggle button "Applications" [ref=d3] (0,0 102x26)
```

Refs are reassigned on every snapshot, so re-snapshot after anything that
changes the screen. Opening the Applications menu and launching a program is
snapshot → click the menu → snapshot again → click the entry.

**Never take coordinates from a screenshot the vision model described.** That
model reports positions in its own internally-resized image space; those numbers
are off by hundreds of pixels on this screen and cannot be corrected by
guesswork. Use it to understand *what* is on screen, and `hermes-desktop` or the
`browser_*` tools to decide *where* to click.

After any click that should have changed the screen, capture again and confirm
before continuing. A click that silently missed looks exactly like a click that
worked until you look.
