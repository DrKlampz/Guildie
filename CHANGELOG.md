# Guildie

## Unreleased
- Removed the add-on-to-add-on theming hooks and cross-add-on names from the window look code; the shared look sync between your add-ons works the same.
- Escape now closes the map pin options window instead of opening the game menu.
- The "Pulse the flair" option now also pulses the edge finish (soft, bevel, double line and glow), not just the corner studs.

## v1.15.3
- Look sync: the first time your add-ons meet, they now all take on the same look right away instead of waiting for you to change something.

## v1.15.2
- Your custom look is now shared with your other add-ons: change colors, background, border or opacity in one and the rest follow (the newest change wins). It is on by default; untick "Sync my look with my other add-ons" in the Look window to turn it off.

## v1.15.0
- Gamer words: the total now covers the times you were offline too. Guildmates share how many were seen in each hour (just an hour and a number: never the words or who said them) and the biggest number for each hour is used. Turn it off with "Share gamer word counts with guildmates" in the settings.

## v1.14.4
- Find recruits: also closes the Looking For Group window if the game opens it when a search comes back.

## v1.14.3
- Find recruits: searching no longer pops up the Who window or fills your chat with the results.

## v1.14.2
- Find recruits: an "Any level" box, for when you don't care what level they are.

## v1.14.1
- Find recruits is now a tab ("Find") in the Armory window instead of its own window. Ctrl-click on the minimap button and /guildie find open that tab.

## v1.14.0
- New: Find recruits. Ctrl-click the minimap button (or /guildie find) to search for players without a guild near your level, then whisper them one click at a time. Choose the level range, whether to stay in your zone, how many days before the same player can be asked again, a daily limit, and the message ({name}, {guild} and {zone} are filled in). Skip a player to never ask them again; a reply of "no" blocks them too.

## v1.13.1
- Invites: the popup no longer keeps telling you to /ginvite someone you already invited. A request now comes off the list when the person is in your guild, and a leftover invite popup is taken down when nothing is waiting any more.

## v1.13.0
- Map: guildmates now show up as pins on the world map. Anyone running Guildie shares their exact spot (green pin); everyone else online is pinned at the middle of the zone the guild roster says they are in (gold pin). Hover a pin for the name and place.
- Options for the map pins (show, share my spot, zone-center pins, names, size, colors) open with Shift-click on the minimap button or /guildie map. /guildie map share off stops sharing your spot.

## v1.12.2
- Fonts: the font pack now ships inside this add-on (Fonts folder), so the separate Look Fonts add-on is no longer needed, and there are about 60 more fonts to pick from under Look > Font.
- Armory: a character saved under a first name only ("Mooman") is no longer listed a second time next to their full name ("Mooman Raintotem"); the old record is folded into the real one.

## v1.12.1
- Release packaging: the automatic release now publishes to Wago and GitHub (the CurseForge upload was rejecting it). Same add-on as v1.12.0.

## v1.12.0
- Invites: Guildie can no longer send guild invites itself on Forever; it alerts you with the name and the /ginvite command instead.
- Welcome: new members get a whisper with their own welcome text.
- New: /issues log.

## v1.11.0
- Armory: the "Also plays" buttons now show each character's professions in shorthand (LW, ECH, ALC...; main professions only). Guildie records your professions on every character you log in on and shares them with the guild, so log in once on each character to fill them in.

## v1.10.3
- Alts: characters that are no longer in the guild roster (deleted) are hidden.
- Guildie no longer re-logs a join date when one is already set.
- Shared look: background color picker, 13 new backgrounds with brightness and grain, a gold trim option, and buttons and slots stay visible on a pure black panel.

## v1.10.0
- New: window customization. Alt-click the minimap button to restyle each window separately (or all together): background textures, colors with copy/paste, opacity sliders, border styles, fonts, scale and position lock. Over 50 fonts to pick from (install the LookFonts folder for the bundled ones; SharedMedia fonts show up too). Off until you tick "Use a custom look"; unticking restores the original. All of the add-on's options now live in that same window, on an Options tab, and the window itself wears the first window's look.

## v1.9.5
- Fix: invites that Guildie said it sent but never went out. The game blocks addon code from sending a guild invite, even from a button (the red "Interface action failed because of an AddOn" message). Now the popup's Invite button types `/ginvite Name` into your chat box and you press Enter, which the game allows. Guildie only says "Invited" and sends the welcome and reply after you press Enter on that command. Other chat lines are ignored. If you don't press Enter within 45 seconds, the popup comes back.

## v1.9.4
- Fix: after you clicked the popup, Guildie could say "The game didn't send the invite" and put the player back in the queue even though the invite had gone out and they joined. The game reports many unrelated blocked actions as UNKNOWN(), and Guildie was blaming the invite for them. Now only a block that names the invite counts as a failed invite; every blocked-action report is written to the log with its name.

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
