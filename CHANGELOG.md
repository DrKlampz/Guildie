# Guildie

## v1.9.3
- `/guildie selftest`: sends two fake whispers through the real pipeline (phrase match, popup, stacking, your click) without inviting anyone, then prints PASS/FAIL for each step.

## v1.9.2
- The "Invite sent!" reply whisper and the Invited counter now wait a few seconds and only happen if the game gave no sign of trouble: a blocked call, an error message (shown in chat and the activity log), or a decline / already-in-a-guild reply. A blocked invite goes back to the popup instead of being reported as sent.
- The options window and the Armory window now stack properly: clicking one brings the whole window forward instead of the two bleeding through each other.

## v1.9.1
- Diagnostics: Guildie now keeps its last 250 debug lines in the saved settings all the time (nothing prints unless debug is on), records which events the game accepted at login, and `/guildie report` prints what this game has taught it (does inviting or chatting need a click, one invite per click, whispers seen) plus the latest lines. Use it right after an invite fails to fire.

## v1.9.0
- New **Zone** tab (`/guildie zone`): who in the guild is in your zone, and who else has quests from it. Shared quests are highlighted, hover a row for the full list, click to whisper. Look up any other zone too.
- Guildmates share their quest list with each other (turn off with `/guildie zone share off`); optional chat alert when a guildmate arrives in your zone (`/guildie zone alerts off`).
- New **Dates** tab: guild join dates and birthdays. Your join date is logged automatically when you join, or type it in (`/guildie joined 2024-03-05`); birthdays with `/guildie birthday 3/5`. Both are shared so only one person needs to know a date.
- Anniversary and birthday shout-outs, with guildmates' Guildies avoiding repeats.
- Armory: a player's combined gold across all their characters now shows at the top right of the detail panel and on the main's row.
- Invite popup: requests wait 30 minutes, the popup refreshes itself, and clicking Invite now tells you in chat whether the invite went out.

## v1.0.0
- First release for WoW: Forever.
- Auto guild-invite when someone whispers your phrase (exact or "anywhere" matching).
- Optional confirm popup; switches on automatically if the game blocks automatic invites.
- Per-player cooldown and customizable reply whisper.
- Custom welcome message in guild chat when a new member joins, with {name} and {guild}.
- "Only welcome players Guildie invited" option to prevent double welcomes between officers.
- Settings window (/guildie, the AddOns compartment button, or Options > AddOns).
- Recent activity log and invite/welcome stats.
