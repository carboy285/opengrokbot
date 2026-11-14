# Run OpenGrokBot in Docker (experimental)

This runs the Windows/Electron app headless in a container and serves it through **Web access**, so you open it in a browser. It exists for people who want it on a home server. It has **not been built or run in Docker by the maintainers**; the same start-up sequence (settings written, Electron under a virtual screen, browser login) was checked outside Docker.

## Start

```bash
export OPENGROKBOT_WEB_PASSWORD='choose-a-long-password'   # 10 or more characters
docker compose -f docker/compose.yml up --build
```

Open <http://127.0.0.1:8765>, sign in as `admin` (change with `OPENGROKBOT_WEB_USER`). Chats and settings live in the `opengrokbot-data` volume.

The compose file publishes the port only to this computer. To use it from another device, put it behind your own HTTPS reverse proxy or a private network such as Tailscale. Web access over plain HTTP is for networks you trust, and it refuses clients outside private address ranges.

## AI CLIs

OpenGrokBot drives AI CLIs that are installed where it runs, so a container needs its own. The compose file installs Claude Code; change `CLIS` (a space-separated list of npm packages) to add more. Then sign each in once:

```bash
docker compose -f docker/compose.yml exec opengrokbot claude login
```

Your sign-in is stored in the container's home folder, not in the image. Keep it out of any image you share.

## Settings

| Variable | Meaning |
| --- | --- |
| `OPENGROKBOT_WEB_PASSWORD` | Required. 10 or more characters. |
| `OPENGROKBOT_WEB_USER` | Default `admin`. |
| `OPENGROKBOT_PLUGINS` | Comma-separated plugin names to allow (see [PLUGINS.md](PLUGINS.md)). |
| `OPENGROKBOT_DATA_DIR` | Where chats and settings are kept. Default `/data`. |

## Limits

- No microphone, speakers or GUI: voice, desktop notifications and the local browser window do not apply.
- Only the calls allowed by Web access work from a browser; secrets, API keys and updates stay host-only, so set API keys another way before relying on them.
