# Frontier Station 13 Discord Rich Presence

A small Windows tool that shows Frontier Station 13's live status (player
count) on your Discord profile while you're playing, ported from
[qwertyquerty/ss13rp](https://github.com/qwertyquerty/ss13rp) and rewritten
to speak this codebase's own `world/Topic()` API
(`code/modules/world_api/`) instead of the old raw `?status` protocol.

This is the **host setup** doc (whoever is configuring the tool). If you're a
player who was just handed a working copy of this folder, see
`CLIENT_GUIDE.txt` instead -- you don't need any of the Discord Developer
Portal steps below.

## One-time setup

Full step-by-step walkthrough: **`SETUP_GUIDE.txt`**. Short version:

1. Double-click `install.bat` (installs/updates dependencies).
2. Copy `.env.example` to `.env`.
3. Create a Discord Application at the [Developer Portal](https://discord.com/developers/applications), copy its Application ID into `.env`'s `DISCORD_CLIENT_ID`.
4. Upload your artwork under **Rich Presence -> Art Assets**, put the key name you gave it into `.env`'s `LARGE_IMAGE_KEY`.
5. Fill in `.env`'s `SERVER_ADDR` / `SERVER_PORT` (Frontier's actual address/port) and check `WINDOW_TITLE_MATCH` against your real DreamSeeker window title.
6. Double-click `run.bat`.

(`install.bat`/`run.bat` just wrap `pip install -r requirements.txt` and `python main.py` respectively -- run those manually instead if you'd rather not use batch files.)

All real values live in `.env`, which is already `.gitignore`d -- never committed, never shared unless you choose to.

## Notes

- The card shows two buttons: **Join Server** (opens `byond://SERVER_ADDR:SERVER_PORT`, derived automatically -- override with `.env`'s `JOIN_URL`) and **Join Discord** (`DISCORD_INVITE_URL`). Discord allows two buttons maximum, so both slots are used.
- The bold **"Frontier Station 13"** header is the Discord Application's own registered name. It can't be changed from here and can't be made clickable -- Rich Presence has no field for it. The Join Server button is the clickable route into the server.
- Discord validates button URLs and may reject non-`http(s)` schemes. If "Join Server" never renders, point `JOIN_URL` at an https page that redirects to the same `byond://` address. See `SETUP_GUIDE.txt` (E).
- Discord never shows your *own* buttons back to you on your own profile -- ask someone else to check them.
- Requires the local Discord desktop client to be running (Rich Presence is set over Discord's local IPC, not the web/mobile client).
- Only queries the unauthenticated `get_serverstatus` endpoint -- no auth token or server-side changes needed.
- This is a deliberately minimal first pass: no map-name field (would need a one-line server-side addition), no ghost/spectator detection, and no settings GUI yet.
