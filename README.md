# Pomodoro Desktop — 8-Week Study Companion

A sleek, native Windows desktop Pomodoro timer and structured 8-week learning sprint companion built with **Elixir**, **Phoenix LiveView**, and **elixir-desktop**.

Designed with a dark glassmorphic aurora aesthetic, vector iconography, gentle notification chimes, wall-clock timetable tracking, and an integrated Brain.fm ambient audio player.

---

## Features

- **Real-Time Pomodoro Timer**: Phase-aware timer (Focus / Short Break / Long Break) with circular svg progress ring, quick subject tagging, and unconstrained manual override.
- **8-Week Structured Study Roadmap**: Starts **October 14, 2026** with prioritized daily time blocks:
  - **Fixed Priorities**: CodeIntuition (Problem Solving) & Erlang/Elixir (Job Prep)
  - **Rotating Priorities**: C# / .NET & Software Engineering books
- **Wall-Clock Schedule Tracking**: Timetable dynamically tracks local system time via `:calendar.local_time()`, highlighting the active block with a pulsing `● NOW` indicator regardless of study pacing.
- **Saturday Weekly Review**: Interactive 6-point checklist directly from your sprint methodology with persistent SQLite storage and Monday task planning.
- **Focus Analytics & Streaks**: Real-time stats with session counts, total minutes focused today/this week, subject distribution bars, and daily streak counters.
- **Gentle Sound System**: Soft non-jarring transitional bells and wind chimes served natively from `priv/static/sounds/`.
- **Integrated Background Audio Player**: Plays focus/relax ambient music during sessions with animated equalizer bars, track display, skip controls, and independent volume sliders.
- **Native Windows Desktop Integration**: Frameless translucent window, custom drag bridge, system tray minimize (`Desktop.Window`), and embedded high-resolution 3D application and taskbar icons.

---

## Adding Your Own Music (`music_pomodoro/`)

The background audio player scans the `music_pomodoro/` directory for `.mp3` tracks and automatically categorizes and shuffles playlists based on filename keywords:

1. Create a `music_pomodoro/` folder in the root of the project (or alongside `PomodoroTimer.exe` in the release).
2. Drop your favorite Brain.fm or ambient MP3 files into the folder.
3. The catalog engine classifies tracks based on keywords in the filename:
   - **Focus Playlist**: filenames containing `focus`, `piano`, or `moon` (e.g. `brain.fm_piano_focus.mp3`)
   - **Relax / Break Playlist**: filenames containing `relax` (e.g. `brain.fm_relax.mp3`)
   - **Power Nap**: filenames containing `nap` (e.g. `power_nap_15min.mp3`)
   - **Sleep**: filenames containing `sleep` (e.g. `brain.fm_sleep.mp3`)

*Note: `music_pomodoro/` is excluded from git so you can keep your local audio library without bloating the repository.*

---

## Running in Development

### Prerequisites
- Elixir 1.17+ & Erlang/OTP 26+
- Node.js (for Tailwind assets)

```bash
# 1. Install dependencies & initialize SQLite database
mix setup

# 2. Start Phoenix server with native desktop window
mix phx.server
```

You can interact with the app via the native desktop window or open [`http://localhost:4000`](http://localhost:4000) in your browser.

---

## Building the Windows Production Release

To compile a standalone, self-contained Windows release package:

```powershell
.\build_release.ps1
```

This PowerShell script will:
1. Compile and minify production Tailwind CSS and JavaScript bundles.
2. Assemble an Elixir/OTP release into `_build/prod/rel/pomodoro_app`.
3. Run SQLite database migrations and seed the 8-week study plan.
4. Copy the complete runtime distribution to `..\PomodoroTimer\`.
5. Compile the native Windows `PomodoroTimer.exe` launcher with the custom 3D squircle timer icon embedded directly into the executable PE header.

To launch the compiled app, simply double-click **`PomodoroTimer.exe`** in the root directory!

---

## Tech Stack

- **Backend**: Elixir, Phoenix 1.8, Ecto SQLite3, GenServer PubSub architecture
- **Frontend**: Phoenix LiveView 1.2, Tailwind CSS v4, Vanilla CSS Design System
- **Desktop Bridge**: `elixir-desktop` (wxWidgets & WebView2 integration)
- **Audio Engine**: HTML5 Audio Webhooks with independent volume control
