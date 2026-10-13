# Pomodoro Desktop — 8-Week Study Companion

A sleek, native Windows desktop Pomodoro timer and structured 8-week learning sprint companion built with **Elixir**, **Phoenix LiveView**, and **elixir-desktop**.

Designed with a dark glassmorphic aurora aesthetic, vector iconography, gentle notification chimes, wall-clock timetable tracking, and an integrated Brain.fm ambient audio player.

> **Note on Personal Project & Public Release**  
> This application was created as a personal study companion and daily focus ritual tailored for a dedicated 8-week intensive software engineering sprint. It has been made public for reference, open-source inspiration, or personal adaptation.  
> If you clone or fork this project, you can freely adapt and re-structure it to match your own curriculum, work hours, or daily habits—either manually or using an AI coding agent (e.g. Antigravity, Claude, Cursor, Copilot). See the [Customization Guide](#customization--adaptation-guide) below for a map of where all schedules, seeds, and assets live.

---

## Features

- **Executive 2-Column Desktop Dashboard**: Dual-column layout on desktop ($\ge 768\text{px}$) with the hero Pomodoro timer on the left and an active timetable tracker, metrics panel, and sound launcher on the right. Automatically collapses into a compact single-column widget for small screens or widget-style multitasking.
- **Real-Time Pomodoro Timer**: Phase-aware timer (Focus / Short Break / Long Break) with circular SVG progress ring, subject tagging, and unconstrained manual adjustments.
- **Wall-Clock Schedule Tracking**: Timetable dynamically tracks local system time via `:calendar.local_time()`, highlighting the active block with a pulsing `● NOW` indicator regardless of study pacing.
- **8-Week Structured Study Roadmap**: Starts **October 14, 2026** with prioritized daily time blocks:
  - **Fixed Priorities**: CodeIntuition (Problem Solving) & Erlang/Elixir (Job Prep)
  - **Rotating Priorities**: C# / .NET & Software Engineering books
- **Saturday Weekly Review**: Interactive 6-point checklist directly from your sprint methodology with persistent SQLite storage and Monday task planning.
- **Sound Sanctuary & Vibe Lounge**: Modal audio lounge featuring a 360° neon aurora spectrum equalizer, dynamic rotating vinyl/cassette spool animations, zero-latency client/server volume slider, and track navigation.
- **Gentle Sound System**: Soft non-jarring transitional bells and wind chimes served natively from `priv/static/sounds/`.
- **Integrated Background Audio Player**: Plays focus/relax ambient music during sessions with animated visualizers, playlist selector, and skip controls.
- **Native Windows Desktop Integration**: Frameless translucent window, custom drag bridge, system tray minimize (`Desktop.Window`), and embedded high-resolution 3D application and taskbar icons.
- **Database Safeguards**: Automated timestamped backups before release migrations; non-destructive seed logic preserves all existing session progress and checklist states.

---

## Customization & Adaptation Guide

If you clone this project and want to tailor it to your own learning plan or work routine (manually or via an AI agent), here is the map of key files:

### 1. Study Schedule & Weekly Reviews (`priv/repo/seeds.exs`)
- **Location**: `priv/repo/seeds.exs`
- **Why seeds?**: In this initial version, the timetable schedule and 8-week sprint checklist are populated via local seeds rather than an in-app CRUD UI due to sprint delivery priorities. Seeding is guarded with empty checks (`if Repo.aggregate(...) == 0`) so running seeds or building releases **will never overwrite or erase your ongoing study progress**.
- **How to customize**:
  - Edit `reviews` list in `priv/repo/seeds.exs` to define your own weeks, sprint dates, and deliverables.
  - Edit `StudyBlock` entries to customize your daily time slots, start/end times (`~T[08:00:00]`), subjects, colors (`#6366f1`), icons (`brain`, `coffee`, `code`, `book`), and descriptions.
  - *Future Roadmap*: Upcoming versions will introduce dynamic in-app timetable and goal editors directly in SQLite without needing seed files.

### 2. Adding Your Own Music (`music_pomodoro/`)
- **Location**: `music_pomodoro/` folder in the project root (or alongside `PomodoroTimer.exe`).
- Drop your favorite Brain.fm, lofi, or ambient `.mp3` files into `music_pomodoro/`.
- The catalog engine in `lib/pomodoro_app/music.ex` automatically scans the directory and classifies tracks based on filename keywords:
  - **Focus Playlist**: filenames containing `focus`, `piano`, or `moon` (e.g. `deep_focus_01.mp3`)
  - **Relax / Break Playlist**: filenames containing `relax` (e.g. `gentle_relax.mp3`)
  - **Power Nap**: filenames containing `nap` (e.g. `power_nap_15min.mp3`)
  - **Sleep**: filenames containing `sleep` (e.g. `sleep_ambience.mp3`)
- *Note: `music_pomodoro/` is excluded from git so your personal audio files stay local.*

### 3. Audio Alarm Chimes (`priv/static/sounds/`)
- **Location**: `priv/static/sounds/`
- Place your transition sound files here:
  - `focus_end.mp3`: Chime played when focus session finishes.
  - `break_end.mp3`: Chime played when break ends.
  - `wind_chime.mp3`: Gentle ambient notification chime.

### 4. Desktop Window Dimensions (`lib/pomodoro_app/application.ex`)
- **Location**: `lib/pomodoro_app/application.ex` (under `{Desktop.Window, ...}`)
- **Default Size**: `{860, 680}` opens the full two-column executive dashboard on launch.
- **Minimum Size**: `{400, 620}` allows resizing down to a compact single-column timer widget anytime.

### 5. UI Views & Visualizers (`lib/pomodoro_app_web/live/timer_live.ex`)
- **Location**: `lib/pomodoro_app_web/live/timer_live.ex`
- Contains the LiveView template and event handlers for the Pomodoro timer, schedule timetable, review checklists, sound sanctuary modal, and analytics.

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
1. Purge stale asset caches and compile production Tailwind v4 CSS and JavaScript bundles.
2. Compile and assemble an Elixir/OTP release into `_build/prod/rel/pomodoro_app`.
3. Create an automated timestamped backup of your SQLite database in `%APPDATA%\PomodoroTimer\`.
4. Run migrations and non-destructive seeds without touching existing progress.
5. Copy the complete runtime distribution to `..\PomodoroTimer\`.
6. Compile the native Windows `PomodoroTimer.exe` launcher with the custom 3D timer icon embedded into the executable PE header.

To launch the compiled app, simply double-click **`PomodoroTimer.exe`** in the project root!

---

## Tech Stack

- **Backend**: Elixir, Phoenix 1.8, Ecto SQLite3, GenServer PubSub architecture
- **Frontend**: Phoenix LiveView 1.2, Tailwind CSS v4, Vanilla CSS Design System
- **Desktop Bridge**: `elixir-desktop` (wxWidgets & WebView2 integration)
- **Audio Engine**: HTML5 Audio Webhooks with independent volume control
