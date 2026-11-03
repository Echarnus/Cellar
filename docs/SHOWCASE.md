# Showcase: screenshots and video

What the site shows of Cellar, and how to capture it. The site renders a capture only when its file
is in `pages/media/` (`SHOTS`, `HERO_SHOT` and `TOUR_VIDEO` in `pages/gen-site.py`), so these can land
one at a time. Until then the home page shows the cover shelf and no "See it work" section.

## Rules

- **Real captures of the shipping app, never a mock-up.** Take them from a release build installed
  the way a player installs it (the DMG), not from a checkout.
- **What a player sees, nothing more.** No Technical Details window, no Terminal, no Finder window
  in a bottle, no debug overlay. If a capture would show the words Wine, bottle, runner or profile,
  the app has a bug to fix first (docs/DESIGN.md §2).
- **Honest state.** Show a game marked Playable actually playing. Don't stage a state the app
  can't reach, and don't crop out an error to make a shot work.
- **No one's private data.** Sign in with a Cellar demo Steam account, not Kenneth's: the account
  name and library show in the sidebar and on the Accounts screen. Its library should hold the games
  being shown (Planet Coaster 2 and Skyrim Special Edition are the confirmed Playable ones; Fallout
  Shelter is free).
- **Game footage is the publisher's.** Keep in-game footage short and incidental to showing that
  Cellar started the game. No logos or key art beyond the store's own covers, which the app already
  shows. If in doubt, end the shot at the game's title screen.

## Capture setup

- An Apple Silicon Mac on the current macOS, a clean user account, Cellar installed from the DMG.
- Display at a "looks like 1440 × 900" scaling or larger, so text is crisp at 2×.
- Light appearance for the stills (the site's default), default accent colour, Dock visible,
  menu bar visible, no other apps' windows, Do Not Disturb on, wallpaper set to a plain macOS one.
- Cellar's window at about 1280 × 800 points, centred.
- Window stills: ⇧⌘4, then Space, then ⌥-click the window (no shadow), or
  `screencapture -o -l <window id>`. Full-screen stills (the Dock shot): ⇧⌘3.
- Video: QuickTime Player → New Screen Recording, of the whole screen, at 60 fps, with the
  pointer shown and clicks highlighted off. Trim in QuickTime; no music needed.

## Files

| File | What | Limit |
|---|---|---|
| `hero.png` | The hero image, in place of the cover shelf | 600 KB |
| `library.png`, `game.png`, `installing.png`, `playing.png` | The four stills, below | 600 KB each |
| `tour.mp4` | The tour video, H.264, 1920 × 1080 or 1600 × 1000, 60–75 s, no audio track | 15 MB |
| `tour.vtt` | English captions for the video (WebVTT), describing what happens | 50 KB |
| `tour-poster.jpg` | The video's first frame worth seeing, same size as the video | 600 KB |

Stills are 1600 px wide (`sips --resampleWidth 1600 shot.png`), then squeezed with `pngquant` or
saved as JPEG at about 80 % if a PNG stays over the limit. `python3 pages/check-site.py` checks the
limits; the video needs all three of its files or the generator refuses to build.

## Shot list

| File | Screen | State to set up | Site caption |
|---|---|---|---|
| `hero.png` | Main window, library | Signed in, 8–12 games with covers loaded, Planet Coaster 2 selected, its page showing **Play** | — |
| `library.png` | Main window, library | Same, nothing selected or the first game selected, the search field empty | Your Steam library, on your Mac |
| `game.png` | A game's page | Skyrim Special Edition, installed, **Play** button and its sentence visible | One button, and a sentence saying what it does |
| `installing.png` | A game's page | A game mid-install, progress bar about a third of the way, the sentence saying what it is doing | Cellar does the setting up |
| `playing.png` | Full screen | Planet Coaster 2 at its main menu in a window, the Dock showing Cellar and **Planet Coaster 2** by name (hover the icon so the tooltip shows) | Then it's just the game |

## Tour video storyboard (about 70 s)

| Time | Shot | Caption track |
|---|---|---|
| 0–5 s | The DMG window: drag Cellar to Applications | Download Cellar and drag it to Applications. |
| 5–12 s | First open: the welcome screen, then **Sign in to Steam** with the QR code | Sign in to Steam once. Scan the code with the Steam app on your phone. |
| 12–20 s | The library fills in with the games the demo account owns | Cellar shows the Windows games you own. |
| 20–28 s | Search "planet", select Planet Coaster 2, the page with **Install** | Pick a game. Each one has a single next step. |
| 28–40 s | Press **Install**; progress runs (cut, time-lapse the download) | Cellar downloads it from your account and sets it up. |
| 40–48 s | **Play**; the game window opens, Dock shows Planet Coaster 2 | Press Play. The game opens under its own name. |
| 48–62 s | A few seconds of the game's main menu, then the Workshop page loading | It runs much as it does on a PC, online features included. |
| 62–70 s | Quit the game; back in Cellar, **Play** ready again; end on the app icon and the site's address | Quit, and nothing is left running. Free at echarnus.github.io/Cellar |

Cuts: a cross-dissolve only across the download time-lapse; everything else plays in real time, so
nothing looks faster than it is. Say "time-lapse" in the caption track where it is one.

## Later

- Short clips (10–15 s each) of the same beats for social posts, cut from the tour recording.
- A dark-appearance set, once the site can swap images with its own light/dark toggle.
