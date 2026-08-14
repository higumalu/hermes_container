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
