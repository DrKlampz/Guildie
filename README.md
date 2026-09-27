# Guildie

Auto guild-invite on a whisper phrase, plus a custom welcome message in guild chat. For WoW: Forever (interface 16001).

See CURSEFORGE.md for the full feature list and commands.

## Releasing

1. Create the CurseForge and Wago projects once (see the publishing steps).
2. Add these two lines to `Guildie.toc` with your real IDs:
   ```
   ## X-Curse-Project-ID: 123456
   ## X-Wago-ID: aBcD1234
   ```
   Do not add `X-WoWI-ID`; WoWInterface isn't supported for Forever and the packager run fails.
3. Add repo secrets `CF_API_KEY` and `WAGO_API_TOKEN`.
4. `git tag v1.0.1 && git push --tags`
