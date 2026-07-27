# PartyRock

YouTube surfing + PiP on the phone, one button to crate the whole set on the Mac.

Browse YouTube in-app (keeps playing in the background / PiP like Tube-PiP),
hit **Setlist It** on any DJ set, and the Mac's setlist pipeline takes over:
tracklist resolve (chapters → description → 1001tracklists → comments → Shazam
sampling) → downloads → Serato crate → rekordbox sync. Talks to the Mac over
Tailscale, so it works from anywhere.

## How it works

- `PlayerWebView` — WKWebView tuned for YouTube: inline + PiP playback, mobile
  UA, background audio session so sound survives leaving the app.
- `SetlistAPI` — mirrors the setlist web flow against the Flask server:
  `/api/resolve` → tracklist ? `/api/download` : `/api/shazam` → `/api/download`,
  then polls `/api/job/<id>` for live progress in the status bar.
- Server URL lives in Settings (defaults to the tailnet address).

## Build

XcodeGen project — never edit the .xcodeproj, it's generated:

```
xcodegen generate
xcodebuild -scheme PartyRock -destination 'generic/platform=iOS' build
```

## Roadmap

- 0.1 iPhone: browse + PiP + Setlist It + progress
- 0.2 sanitize pass surfaced in-app (amapiano sanitize: kill official-video
  rips, keep clean audio/lyric-quality only)
- 0.3 library/listening tab (stream what's already crated — think private
  Spotify/SoundCloud for sets we introduce)
- 0.4 watchOS listening companion
- 0.5 Quest 3 (WebXR shell around the same server)
