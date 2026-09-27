# Guildie

**Recruit on autopilot.** Players whisper you a phrase, Guildie sends the guild invite, and when they join it posts your custom welcome in guild chat.

Built for **WoW: Forever**.

## Features

- **Whisper-to-invite:** set a phrase like `guild inv`. Anyone who whispers it gets an invite.
- **Exact or loose matching:** require the exact phrase, or catch it anywhere in a whisper.
- **Custom welcome message:** posted in guild chat when a new member joins. Use `{name}` and `{guild}`.
- **No double welcomes:** by default Guildie only welcomes players it invited, so several officers can run it at once.
- **Reply whisper:** optionally tell the player their invite is on the way.
- **Spam protection:** per-player cooldown.
- **Confirm mode:** approve each invite with a popup. Guildie switches to this by itself if the game ever blocks automatic invites.
- **Activity log and stats** right in the settings window.

## How to use

Open settings with `/guildie`, the AddOns button next to the minimap, or **Options → AddOns → Guildie**.

| Command | What it does |
|---|---|
| `/guildie` | Open settings |
| `/guildie on` / `off` | Toggle auto-invite |
| `/guildie phrase <text>` | Set the invite phrase |
| `/guildie welcome <text>` | Set the welcome message |
| `/guildie preview` | Preview the welcome in your chat |

Your guild rank needs permission to invite.

## Notes

- Guild chat messages wait until chat is unlocked (for example, after a boss encounter) and then send.
- Some Forever beta builds don't reload saved settings reliably. Guildie keeps a per-character copy as a backup.

Bug reports and ideas welcome!
