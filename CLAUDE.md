# Project rules (read before every change)

Samuel builds games entirely from his phone. Claude writes and pushes the code,
GitHub Actions builds it, and he playtests the web link on his iPhone. These rules
keep every game port-ready for iPhone (App Store), Android and Steam
(Windows/Mac/Linux/Steam Deck) without rewrites. Copy this file into every new
game repo, including Yes And.

## Platforms
- Every feature must work on web, iOS, Android and desktop. No web-only shortcuts.
- Never use `JavaScriptBridge` or other browser-only APIs. If something really is
  platform-specific, wrap it: `if OS.has_feature("web"):`, `"ios"`, `"android"`,
  `"mobile"`, `"pc"`, and give every other platform a working fallback.
- Language is GDScript only. No C#: it can't export to web.

## Renderer
- Use the Compatibility renderer on every platform, so the web build looks
  exactly like the shipped app. Switching renderers is a deliberate decision
  made with Samuel, never a side effect of another change.
- Shaders must be written for and tested on Compatibility.

## Screen and layout
- Design for both portrait phones and landscape monitors. Build UI with
  Control nodes, anchors and containers (VBox/HBox/Grid/Margin), never fixed
  pixel positions for UI.
- Use stretch mode `canvas_items`. Respect safe areas on phones
  (`DisplayServer.get_display_safe_area()`) so nothing hides under the notch.
- Touch targets are at least 88 px tall at the 720-wide base resolution.
- Phone Pong: the native phone apps are locked to portrait. On wide screens
  (desktop/Steam, or a phone turned sideways in the browser) the field is
  drawn rotated so it plays left to right, with the player on the right
  (right thumb).

## Input
- Every action works with touch AND mouse. Keep `emulate_touch_from_mouse` on,
  or handle both event types. Keyboard and gamepad support is a bonus for Steam.
- Map gameplay actions in the Input Map (`ui_*` or named actions); don't
  hard-code keys in scripts.

## Saves and data
- Save only to `user://`. Use `ConfigFile` or JSON, include a `save_version`
  field, and write migration code when the format changes.
- Web saves can be cleared by Safari, so never rely on them for anything
  beyond playtesting.

## Audio
- Start music only after the player's first tap or key press: browsers block
  sound before that.
- Short sound effects are WAV. Long music should be OGG to keep downloads small.
- Generated sounds live in `tools/make_audio.py`. Re-run it after editing, and
  update `MUSIC_FRAMES` in `main.gd` to the number it prints.

## Size and performance budgets
- Keep the web download under about 30 MB and memory modest: iPhone Safari
  crashes tabs that use too much. Compress art, prefer atlases, and load big
  assets per scene instead of all at startup.
- The web build is single-threaded. Don't depend on threads for correctness.

## Build pipeline
- `.github/workflows/deploy.yml` builds the web version on every push to `main`
  and publishes it to GitHub Pages.
- Godot errors appear as annotations on the build job. Check them after
  every push, and fix any failure before telling Samuel a change is live.
- After each change, give Samuel the play link and one line on what changed.
  He may need to pull down to refresh if Safari shows a cached version.

## Publishing a change
- Only pushes to `main` rebuild the play link. When a change is done, commit it
  and push it to `main` (merge your working branch into `main` and push), unless
  Samuel asks for a separate branch. If pushing to `main` is blocked, open a pull
  request and give him the link with "tap Merge pull request".
- Then watch the Actions run (`gh run list`, `gh run view`) until it succeeds,
  and send him https://humble-house-studios.github.io/phone-pong/

## Working with Samuel
- He works from his phone and is new to code: explain results in plain words,
  keep replies short, and handle git, builds and fixes yourself.
- When he needs to sign in, create an account or tap a setting, give him the
  exact link and the exact option to choose.
