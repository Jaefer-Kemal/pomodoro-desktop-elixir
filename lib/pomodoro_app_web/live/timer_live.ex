defmodule PomodoroAppWeb.TimerLive do
  @moduledoc """
  LiveView for the Pomodoro Timer & 8-Week Study Companion.
  Features:
  - Real-time Pomodoro timer with phase transitions & gentle audio chimes
  - Integrated Brain.fm background music player with category shuffle
  - 8-Week Study Schedule with daily timetables and one-click "Focus Now"
  - Interactive Saturday Weekly Review checklist with persistent DB storage
  - Rich Analytics with subject breakdown, daily consistency, and streaks
  - Frameless native window controls and customizable settings
  """
  use PomodoroAppWeb, :live_view

  alias PomodoroApp.Schedule
  alias PomodoroApp.Analytics

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PomodoroApp.Timer.subscribe()
      # Periodic 10s heartbeat to update local clock/schedule "Now" indicator
      Process.send_after(self(), :tick_clock, 10_000)
    end

    current_state = PomodoroApp.Timer.get_state()
    {today, _} = Schedule.local_date_and_time()
    today_dow = Date.day_of_week(today)
    curr_week = Schedule.current_week_number()

    {current_block, next_block} = Schedule.get_current_and_next_block()
    selected_blocks = Schedule.list_study_blocks_for_day(today_dow)
    weekly_review = Schedule.get_weekly_review_by_week(curr_week)

    socket =
      socket
      # Timer state
      |> assign(:time_left, current_state.time_left)
      |> assign(:phase, current_state.phase)
      |> assign(:status, current_state.status)
      |> assign(:task_name, current_state.task_name)
      |> assign(:subject, Map.get(current_state, :subject, "CodeIntuition"))
      |> assign(:focus_duration, current_state.focus_duration)
      |> assign(:short_break_duration, current_state.short_break_duration)
      # Navigation
      |> assign(:view, :timer)
      |> assign(:is_maximized, false)
      # Music & Sound state
      |> assign(:music_enabled, true)
      |> assign(:music_playing, false)
      |> assign(:music_track, nil)
      |> assign(:alarm_volume, 0.6)
      |> assign(:music_volume, 0.35)
      # Schedule state
      |> assign(:today_dow, today_dow)
      |> assign(:selected_dow, today_dow)
      |> assign(:study_blocks, selected_blocks)
      |> assign(:current_block, current_block)
      |> assign(:next_block, next_block)
      # Review state
      |> assign(:current_week, curr_week)
      |> assign(:selected_week, curr_week)
      |> assign(:weekly_review, weekly_review)
      |> assign(:review_saved_notice, false)
      # Analytics state
      |> assign_analytics()

    {:ok, socket}
  end

  defp assign_analytics(socket) do
    socket
    |> assign(:completed_today, Analytics.get_completed_sessions_today())
    |> assign(:focus_minutes_today, Analytics.get_focus_minutes_today())
    |> assign(:focus_minutes_week, Analytics.get_focus_minutes_this_week())
    |> assign(:streak, Analytics.calculate_streak())
    |> assign(:subject_breakdown, Analytics.subject_breakdown_this_week())
    |> assign(:daily_activity, Analytics.daily_activity_this_week())
  end

  # ── Handling incoming messages ──

  @impl true
  def handle_info({:timer_update, new_state}, socket) do
    {current_block, next_block} = Schedule.get_current_and_next_block()

    socket =
      socket
      |> assign(:time_left, new_state.time_left)
      |> assign(:phase, new_state.phase)
      |> assign(:status, new_state.status)
      |> assign(:task_name, new_state.task_name)
      |> assign(:subject, Map.get(new_state, :subject, socket.assigns.subject))
      |> assign(:focus_duration, new_state.focus_duration)
      |> assign(:short_break_duration, new_state.short_break_duration)
      |> assign(:current_block, current_block)
      |> assign(:next_block, next_block)
      |> assign_analytics()

    {:noreply, socket}
  end

  @impl true
  def handle_info(:tick_clock, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick_clock, 10_000)
    {current_block, next_block} = Schedule.get_current_and_next_block()
    {today, _} = Schedule.local_date_and_time()
    today_dow = Date.day_of_week(today)

    socket =
      socket
      |> assign(:current_block, current_block)
      |> assign(:next_block, next_block)
      |> assign(:today_dow, today_dow)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:play_alarm, alarm_type}, socket) do
    sound_file =
      case alarm_type do
        :focus_end -> "/sounds/focus_end.mp3"
        :break_end -> "/sounds/break_end.mp3"
        _ -> "/sounds/notification.mp3"
      end

    {:noreply, push_event(socket, "play_alarm", %{src: sound_file})}
  end

  @impl true
  def handle_info({:music_play, track_filename}, socket) do
    if socket.assigns.music_enabled do
      display_name = track_filename |> String.replace(".mp3", "") |> prettify_track_name()

      socket =
        socket
        |> assign(:music_playing, true)
        |> assign(:music_track, display_name)
        |> push_event("music_play", %{src: "/music/#{URI.encode(track_filename)}"})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:music_pause, socket) do
    socket =
      socket
      |> assign(:music_playing, false)
      |> push_event("music_pause", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_info(:music_stop, socket) do
    socket =
      socket
      |> assign(:music_playing, false)
      |> assign(:music_track, nil)
      |> push_event("music_stop", %{})

    {:noreply, socket}
  end

  # ── User Interaction Event Handlers ──

  @impl true
  def handle_event("toggle_timer", _value, socket) do
    if socket.assigns.status == :running do
      PomodoroApp.Timer.pause_timer()
    else
      PomodoroApp.Timer.start_timer()
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("reset_timer", _value, socket) do
    PomodoroApp.Timer.reset_timer()
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_view", %{"view" => view}, socket) do
    view_atom =
      case view do
        "schedule" -> :schedule
        "analytics" -> :analytics
        "review" -> :review
        "settings" -> :settings
        _ -> :timer
      end

    # Refresh data based on current system local time
    {curr, nxt} = Schedule.get_current_and_next_block()
    {today, _} = Schedule.local_date_and_time()
    today_dow = Date.day_of_week(today)

    socket =
      socket
      |> assign(:current_block, curr)
      |> assign(:next_block, nxt)
      |> assign(:today_dow, today_dow)

    socket =
      case view_atom do
        :analytics ->
          assign_analytics(socket)

        :schedule ->
          blocks = Schedule.list_study_blocks_for_day(socket.assigns.selected_dow)
          assign(socket, :study_blocks, blocks)

        :review ->
          review = Schedule.get_weekly_review_by_week(socket.assigns.selected_week)
          assign(socket, :weekly_review, review)

        _ ->
          socket
      end

    {:noreply, assign(socket, :view, view_atom)}
  end

  @impl true
  def handle_event("quick_select_subject", %{"subject" => subject}, socket) do
    PomodoroApp.Timer.set_subject(subject)
    {:noreply, assign(socket, :subject, subject)}
  end

  # One-click start pomodoro from Schedule block
  @impl true
  def handle_event("start_block_pomodoro", %{"subject" => subject, "title" => title}, socket) do
    PomodoroApp.Timer.set_subject(subject, title)

    socket =
      socket
      |> assign(:subject, subject)
      |> assign(:task_name, title)
      |> assign(:view, :timer)

    {:noreply, socket}
  end

  # Schedule day selection
  @impl true
  def handle_event("select_day", %{"day" => day_str}, socket) do
    day = String.to_integer(day_str)
    blocks = Schedule.list_study_blocks_for_day(day)
    {:noreply, socket |> assign(:selected_dow, day) |> assign(:study_blocks, blocks)}
  end

  # Weekly Review week selection
  @impl true
  def handle_event("select_week", %{"week" => week_str}, socket) do
    week = String.to_integer(week_str)
    review = Schedule.get_weekly_review_by_week(week)
    {:noreply, socket |> assign(:selected_week, week) |> assign(:weekly_review, review)}
  end

  # Toggle 6-point checklist item
  @impl true
  def handle_event("toggle_review_check", %{"field" => field_str}, socket) do
    field_atom = String.to_existing_atom(field_str)
    current_review = socket.assigns.weekly_review

    if current_review do
      {:ok, updated} = Schedule.toggle_review_field(current_review, field_atom)
      {:noreply, assign(socket, :weekly_review, updated)}
    else
      {:noreply, socket}
    end
  end

  # Toggle deliverable completion
  @impl true
  def handle_event("toggle_deliverable", _value, socket) do
    current_review = socket.assigns.weekly_review

    if current_review do
      new_val = !current_review.deliverable_completed
      {:ok, updated} = Schedule.update_weekly_review(current_review, %{deliverable_completed: new_val})
      {:noreply, assign(socket, :weekly_review, updated)}
    else
      {:noreply, socket}
    end
  end

  # Save notes/Monday task in review
  @impl true
  def handle_event("save_review_notes", %{"next_task_notes" => notes}, socket) do
    current_review = socket.assigns.weekly_review

    if current_review do
      {:ok, updated} = Schedule.update_weekly_review(current_review, %{next_task_notes: notes})
      {:noreply, socket |> assign(:weekly_review, updated) |> assign(:review_saved_notice, true)}
    else
      {:noreply, socket}
    end
  end

  # ── Music controls ──
  @impl true
  def handle_event("toggle_music", _value, socket) do
    new_enabled = !socket.assigns.music_enabled

    socket =
      if new_enabled do
        if socket.assigns.status == :running do
          category = if socket.assigns.phase == :focus, do: :focus, else: :relax
          track = PomodoroApp.Music.next_track(category)

          if track do
            display_name = track |> String.replace(".mp3", "") |> prettify_track_name()

            socket
            |> assign(:music_enabled, true)
            |> assign(:music_playing, true)
            |> assign(:music_track, display_name)
            |> push_event("music_play", %{src: "/music/#{URI.encode(track)}"})
          else
            assign(socket, :music_enabled, true)
          end
        else
          assign(socket, :music_enabled, true)
        end
      else
        socket
        |> assign(:music_enabled, false)
        |> assign(:music_playing, false)
        |> assign(:music_track, nil)
        |> push_event("music_stop", %{})
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("skip_track", _value, socket) do
    if socket.assigns.music_enabled and socket.assigns.status == :running do
      category = if socket.assigns.phase == :focus, do: :focus, else: :relax
      track = PomodoroApp.Music.next_track(category)

      if track do
        display_name = track |> String.replace(".mp3", "") |> prettify_track_name()

        socket
        |> assign(:music_track, display_name)
        |> push_event("music_play", %{src: "/music/#{URI.encode(track)}"})

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("track_ended", _value, socket) do
    if socket.assigns.music_enabled and socket.assigns.status == :running do
      category = if socket.assigns.phase == :focus, do: :focus, else: :relax
      track = PomodoroApp.Music.next_track(category)

      if track do
        display_name = track |> String.replace(".mp3", "") |> prettify_track_name()

        socket
        |> assign(:music_track, display_name)
        |> push_event("music_play", %{src: "/music/#{URI.encode(track)}"})

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, assign(socket, :music_playing, false)}
    end
  end

  # Sound test & volume triggers
  @impl true
  def handle_event("test_alarm", %{"type" => sound_type}, socket) do
    src =
      case sound_type do
        "break_end" -> "/sounds/break_end.mp3"
        "wind_chime" -> "/sounds/wind_chime.mp3"
        "notification" -> "/sounds/notification.mp3"
        _ -> "/sounds/focus_end.mp3"
      end

    {:noreply, push_event(socket, "play_alarm", %{src: src})}
  end

  @impl true
  def handle_event("change_volume", %{"target" => target, "value" => val}, socket) do
    case target do
      "alarm" ->
        {:noreply,
         socket
         |> assign(:alarm_volume, String.to_float(val))
         |> push_event("set_alarm_volume", %{volume: val})}

      "music" ->
        {:noreply,
         socket
         |> assign(:music_volume, String.to_float(val))
         |> push_event("set_music_volume", %{volume: val})}

      _ ->
        {:noreply, socket}
    end
  end

  # Window handlers
  @impl true
  def handle_event("window_minimize", _value, socket) do
    Desktop.Window.iconize(PomodoroAppWindow)
    {:noreply, socket}
  end

  @impl true
  def handle_event("window_maximize", _value, socket) do
    new_state = !socket.assigns.is_maximized
    Desktop.Window.maximize(PomodoroAppWindow, new_state)
    {:noreply, assign(socket, :is_maximized, new_state)}
  end

  @impl true
  def handle_event("window_close", _value, socket) do
    Desktop.Window.hide(PomodoroAppWindow)
    {:noreply, socket}
  end

  @impl true
  def handle_event("window_drag", %{"dx" => dx, "dy" => dy}, socket) do
    Desktop.Window.move_by(PomodoroAppWindow, dx, dy)
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "save_settings",
        %{"task_name" => task, "focus_min" => fm, "break_min" => bm, "subject" => subj},
        socket
      ) do
    focus_duration = String.to_integer(fm) * 60
    break_duration = String.to_integer(bm) * 60

    PomodoroApp.Timer.update_settings(%{
      "task_name" => task,
      "focus_duration" => focus_duration,
      "short_break_duration" => break_duration,
      "subject" => subj
    })

    socket =
      socket
      |> assign(:subject, subj)
      |> assign(:task_name, task)
      |> assign(:view, :timer)

    {:noreply, socket}
  end

  # ── Render View ──

  @impl true
  def render(assigns) do
    total_time =
      if assigns.phase == :focus, do: assigns.focus_duration, else: assigns.short_break_duration

    progress = 100 - assigns.time_left / total_time * 100
    radius = 58
    circumference = 2 * 3.14159265359 * radius
    dashoffset = circumference - progress / 100 * circumference

    assigns =
      assigns
      |> assign(:circumference, circumference)
      |> assign(:dashoffset, dashoffset)
      |> assign(:radius, radius)

    ~H"""
    <%!-- Aurora Background --%>
    <div class="aurora-bg">
      <div class="aurora-orb"></div>
    </div>

    <%!-- Main App Shell --%>
    <div
      id="app-shell"
      class="relative z-10 flex flex-col w-full h-screen text-slate-100 select-none"
      style="font-family: 'Inter', system-ui, sans-serif;"
      phx-hook="DragBridge"
    >
      <%!-- ── Custom Title Bar ── --%>
      <div
        id="title-bar"
        class="flex-shrink-0 flex items-center justify-between px-3 h-9 w-full"
        style="
          -webkit-app-region: drag;
          background: rgba(7, 8, 15, 0.75);
          backdrop-filter: blur(20px);
          border-bottom: 1px solid rgba(255,255,255,0.06);
        "
      >
        <%!-- App Logo & Tag --%>
        <div class="flex items-center gap-2" style="-webkit-app-region: no-drag; pointer-events: none;">
          <div class="w-4 h-4 rounded-full flex items-center justify-center bg-gradient-to-tr from-pink-500 to-purple-500 shadow-sm shadow-pink-500/50">
            <svg viewBox="0 0 20 20" fill="currentColor" class="w-2.5 h-2.5 text-white">
              <path
                fill-rule="evenodd"
                d="M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 000-1.5h-3.25V5z"
                clip-rule="evenodd"
              />
            </svg>
          </div>
          <span style="font-size: 11px; font-weight: 700; letter-spacing: 0.12em; color: rgba(255,255,255,0.8); text-transform: uppercase;">
            Pomodoro
          </span>
          <span style="font-size: 9px; font-weight: 600; padding: 1px 6px; border-radius: 9999px; background: rgba(168,85,247,0.2); color: #c4b5fd; border: 1px solid rgba(168,85,247,0.3);">
            Week {@current_week}
          </span>
        </div>

        <%!-- Window Controls --%>
        <div class="flex items-center gap-1" style="-webkit-app-region: no-drag;">
          <button
            id="btn-minimize"
            phx-click="window_minimize"
            title="Minimize"
            class="w-6 h-6 rounded-full flex items-center justify-center text-white/40 hover:text-white hover:bg-white/10 transition"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3 h-3">
              <line x1="5" y1="12" x2="19" y2="12" />
            </svg>
          </button>
          <button
            id="btn-maximize"
            phx-click="window_maximize"
            title={if @is_maximized, do: "Restore", else: "Maximize"}
            class="w-6 h-6 rounded-full flex items-center justify-center text-white/40 hover:text-white hover:bg-white/10 transition"
          >
            <%= if @is_maximized do %>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" class="w-2.5 h-2.5">
                <rect x="7" y="3" width="13" height="13" rx="1.5" />
                <path d="M17 7H5a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2V9" />
              </svg>
            <% else %>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" class="w-2.5 h-2.5">
                <rect x="4" y="4" width="16" height="16" rx="2" />
              </svg>
            <% end %>
          </button>
          <button
            id="btn-close"
            phx-click="window_close"
            title="Hide to tray"
            class="w-6 h-6 rounded-full flex items-center justify-center text-white/40 hover:text-white hover:bg-red-500 transition"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3 h-3">
              <line x1="6" y1="6" x2="18" y2="18" />
              <line x1="18" y1="6" x2="6" y2="18" />
            </svg>
          </button>
        </div>
      </div>

      <%!-- ── Main Dynamic Body ── --%>
      <div class="flex-1 flex flex-col overflow-hidden px-4 pt-2 pb-1 min-h-0">
        <div class="flex-1 glass rounded-[28px] overflow-hidden flex flex-col relative animate-fade-up min-h-0">

          <%!-- Top accent glow stripe --%>
          <div
            class="w-full h-1 flex-shrink-0 transition-all duration-700"
            style={
              if @phase == :focus,
                do: "background: linear-gradient(90deg, #ec4899, #8b5cf6, #3b82f6);",
                else: "background: linear-gradient(90deg, #10b981, #06b6d4, #3b82f6);"
            }
          />

          <%!-- ════════ VIEW 1: TIMER ════════ --%>
          <%= if @view == :timer do %>
            <div class="flex-1 flex flex-col items-center justify-between px-4 py-3 overflow-y-auto pomo-scroll min-h-0">

              <%!-- Phase & Active Block Info Header --%>
              <div class="w-full flex items-center justify-between">
                <%!-- Phase indicator badge --%>
                <div class="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-white/5 border border-white/10">
                  <div
                    class="w-2 h-2 rounded-full animate-pulse-dot"
                    style={
                      if @phase == :focus,
                        do: "background: #f472b6; color: #f472b6;",
                        else: "background: #34d399; color: #34d399;"
                    }
                  />
                  <span style="font-size: 10px; font-weight: 700; letter-spacing: 0.12em; color: rgba(255,255,255,0.7); text-transform: uppercase;">
                    {if @phase == :focus, do: "Focus Phase", else: "Rest Phase"}
                  </span>
                </div>

                <%!-- Today Sessions Counter --%>
                <div class="flex items-center gap-1 text-[11px] text-white/50 bg-white/5 px-2.5 py-1 rounded-full border border-white/5">
                  <span class="text-emerald-400 font-semibold font-ticker">{@completed_today}</span>
                  <span>done</span>
                  <span class="text-white/20">·</span>
                  <span class="text-purple-300 font-ticker font-semibold">{@focus_minutes_today}m</span>
                </div>
              </div>

              <%!-- Subject Banner (Clean Vector Icon, No Emojis) --%>
              <div class="w-full text-center mt-1">
                <div class="inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-xs font-semibold shadow-sm"
                     style={"background: #{subject_bg(@subject)}; color: #{subject_text_color(@subject)}; border: 1px solid #{subject_border(@subject)};"}>
                  {render_subject_icon(@subject)}
                  <span>{@subject}</span>
                </div>
                <div class="text-xs text-white/40 italic mt-1 truncate max-w-[280px] mx-auto">
                  "{@task_name}"
                </div>
              </div>

              <%!-- Circular Progress Ring --%>
              <div class="relative flex items-center justify-center my-2" style="width: 172px; height: 172px;">
                <%!-- Ambient glow halo --%>
                <div
                  class="absolute inset-0 rounded-full transition-all duration-700"
                  style={
                    if @phase == :focus,
                      do: "box-shadow: 0 0 50px -8px rgba(244, 114, 182, 0.3); border: 1px solid rgba(244,114,182,0.08);",
                      else: "box-shadow: 0 0 50px -8px rgba(52, 211, 153, 0.3); border: 1px solid rgba(52,211,153,0.08);"
                  }
                />
                <svg
                  class={if @phase == :focus, do: "absolute inset-0 w-full h-full -rotate-90 ring-focus", else: "absolute inset-0 w-full h-full -rotate-90 ring-break"}
                  viewBox="0 0 136 136"
                >
                  <circle
                    cx="68"
                    cy="68"
                    r={@radius}
                    fill="none"
                    stroke="rgba(255,255,255,0.06)"
                    stroke-width="5"
                  />
                  <circle
                    cx="68"
                    cy="68"
                    r={@radius}
                    fill="none"
                    stroke={if @phase == :focus, do: "#f472b6", else: "#34d399"}
                    stroke-width="5"
                    stroke-linecap="round"
                    stroke-dasharray={@circumference}
                    stroke-dashoffset={@dashoffset}
                    style="transition: stroke-dashoffset 1s linear, stroke 0.8s ease;"
                  />
                </svg>

                <%!-- Time Display --%>
                <div class="absolute flex flex-col items-center justify-center gap-0.5 pointer-events-none">
                  <span
                    class="font-ticker"
                    style="font-size: 42px; font-weight: 300; color: white; line-height: 1; text-shadow: 0 0 35px rgba(255,255,255,0.35);"
                  >
                    {format_time(@time_left)}
                  </span>
                  <span style="font-size: 10px; font-weight: 700; letter-spacing: 0.2em; color: rgba(255,255,255,0.35); text-transform: uppercase;">
                    {if @status == :running, do: "RUNNING", else: "PAUSED"}
                  </span>
                </div>
              </div>

              <%!-- Controls (Reset & Play/Pause) --%>
              <div class="flex items-center justify-center gap-5 my-1">
                <button
                  phx-click="reset_timer"
                  title="Reset session"
                  class="w-11 h-11 rounded-full flex items-center justify-center bg-white/5 border border-white/10 text-white/50 hover:text-white hover:bg-white/10 hover:scale-105 active:scale-95 transition"
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" class="w-4 h-4">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182m0-4.991v4.99"
                    />
                  </svg>
                </button>

                <button
                  phx-click="toggle_timer"
                  class="btn-play w-16 h-16 rounded-full flex items-center justify-center hover:scale-105 active:scale-95 transition shadow-lg"
                >
                  <%= if @status == :running do %>
                    <svg viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6 text-white">
                      <rect x="6" y="5" width="4" height="14" rx="1" />
                      <rect x="14" y="5" width="4" height="14" rx="1" />
                    </svg>
                  <% else %>
                    <svg viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6 text-white ml-0.5">
                      <path d="M6.3 2.841A1.5 1.5 0 004 4.11V15.89a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z" />
                    </svg>
                  <% end %>
                </button>
              </div>

              <%!-- Quick Subject Switcher Pills --%>
              <div class="w-full flex items-center justify-center gap-1.5 pt-1 overflow-x-auto pomo-scroll">
                <%= for subj <- ["CodeIntuition", "Erlang/Elixir", "C# / .NET", "Engineering Book", "Weekly Review"] do %>
                  <button
                    phx-click="quick_select_subject"
                    phx-value-subject={subj}
                    class={"text-[10px] px-2 py-0.5 rounded-lg font-medium transition #{if @subject == subj, do: "bg-white/20 text-white font-bold border border-white/30", else: "bg-white/5 text-white/40 hover:text-white/80 hover:bg-white/10 border border-transparent"}"}
                  >
                    {short_subject_label(subj)}
                  </button>
                <% end %>
              </div>

              <%!-- Current / Next Block Pill --%>
              <%= if @current_block do %>
                <div class="w-full text-center mt-2 px-3 py-1.5 rounded-xl bg-black/20 border border-emerald-500/20 text-[11px] text-white/70 flex items-center justify-between">
                  <span class="text-emerald-400 font-extrabold flex items-center gap-1.5 flex-shrink-0">
                    <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
                    NOW:
                  </span>
                  <span class="text-white/90 font-medium truncate mx-2">{@current_block.title}</span>
                  <span class="text-white/40 font-ticker text-[10px] flex-shrink-0">{format_clock(@current_block.start_time)}–{format_clock(@current_block.end_time)}</span>
                </div>
              <% else %>
                <%= if @next_block do %>
                  <div class="w-full text-center mt-2 px-3 py-1.5 rounded-xl bg-black/20 border border-white/5 text-[11px] text-white/50 flex items-center justify-between">
                    <span class="text-white/40 flex-shrink-0">Next Up:</span>
                    <span class="text-purple-300 font-medium truncate mx-2">{@next_block.title}</span>
                    <span class="text-white/30 font-ticker text-[10px] flex-shrink-0">{format_clock(@next_block.start_time)}</span>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>

          <%!-- ════════ VIEW 2: SCHEDULE ════════ --%>
          <%= if @view == :schedule do %>
            <div class="flex-1 flex flex-col p-4 overflow-y-auto pomo-scroll min-h-0">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <h2 class="text-sm font-bold text-white tracking-tight">8-Week Timetable</h2>
                  <p class="text-[11px] text-white/40">Starts October 14, 2026 · Week {@current_week} of 8</p>
                </div>
                <div class="text-[10px] px-2 py-0.5 rounded-md bg-indigo-500/20 text-indigo-300 border border-indigo-500/30 font-semibold flex items-center gap-1">
                  <span class="w-1.5 h-1.5 rounded-full bg-indigo-400"></span>
                  {Schedule.day_name(@today_dow)} Today
                </div>
              </div>

              <%!-- Day Selector Pills --%>
              <div class="flex gap-1 mb-3 overflow-x-auto pomo-scroll pb-1">
                <%= for day <- 1..7 do %>
                  <button
                    phx-click="select_day"
                    phx-value-day={day}
                    class={"flex-1 py-1.5 rounded-xl text-center text-xs font-semibold transition border #{if @selected_dow == day, do: "bg-pink-500/20 text-pink-300 border-pink-500/40 shadow-sm shadow-pink-500/20", else: "bg-white/5 text-white/40 border-white/5 hover:text-white hover:bg-white/10"}"}
                  >
                    <div>{Schedule.day_short(day)}</div>
                    <%= if day == @today_dow do %>
                      <div class="w-1 h-1 rounded-full bg-pink-400 mx-auto mt-0.5"></div>
                    <% end %>
                  </button>
                <% end %>
              </div>

              <%!-- Timetable list --%>
              <div class="flex-1 flex flex-col gap-2.5 overflow-y-auto pomo-scroll pr-1">
                <%= for block <- @study_blocks do %>
                  <% is_current = @current_block && @current_block.id == block.id && @selected_dow == @today_dow %>
                  <div class={"schedule-card flex flex-col gap-1.5 #{if is_current, do: "current-block", else: ""}"}
                       style={"border-left: 3px solid #{block.color};"}>
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-1.5">
                        {render_subject_icon(block.subject)}
                        <span class="text-xs font-bold text-white/90">{block.title}</span>
                      </div>
                      <div class="flex items-center gap-1.5">
                        <%= if is_current do %>
                          <span class="inline-flex items-center gap-1 text-[9px] font-extrabold px-1.5 py-0.5 rounded bg-emerald-500/30 text-emerald-300 border border-emerald-500/40 animate-pulse">
                            <span class="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
                            NOW
                          </span>
                        <% end %>
                        <span class="text-[11px] font-ticker text-white/40">
                          {format_clock(block.start_time)} – {format_clock(block.end_time)}
                        </span>
                      </div>
                    </div>

                    <%= if block.description do %>
                      <p class="text-[11px] text-white/45 leading-relaxed m-0">
                        {block.description}
                      </p>
                    <% end %>

                    <%= unless block.is_rest_block do %>
                      <div class="flex justify-end pt-1">
                        <button
                          phx-click="start_block_pomodoro"
                          phx-value-subject={block.subject}
                          phx-value-title={block.title}
                          class="px-2.5 py-1 rounded-lg text-[10px] font-bold bg-white/10 hover:bg-pink-500/30 text-white hover:text-pink-200 border border-white/10 hover:border-pink-500/40 transition flex items-center gap-1"
                        >
                          <svg viewBox="0 0 20 20" fill="currentColor" class="w-3 h-3 text-pink-400">
                            <path d="M6.3 2.841A1.5 1.5 0 004 4.11V15.89a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z" />
                          </svg>
                          <span>Focus Now</span>
                        </button>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- ════════ VIEW 3: ANALYTICS ════════ --%>
          <%= if @view == :analytics do %>
            <div class="flex-1 flex flex-col p-4 overflow-y-auto pomo-scroll min-h-0">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <h2 class="text-sm font-bold text-white tracking-tight">Focus Analytics</h2>
                  <p class="text-[11px] text-white/40">Progress aligned with your 8-week sprint</p>
                </div>
                <div class="flex items-center gap-1.5 px-2.5 py-1 rounded-xl bg-amber-500/15 border border-amber-500/30 text-amber-300 text-xs font-bold">
                  <svg viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5 text-amber-400">
                    <path d="M12.75 2.25c-.24-.48-.96-.48-1.2 0-.96 1.92-2.88 4.08-4.56 6.24A10.5 10.5 0 0 0 4.5 15a7.5 7.5 0 0 0 15 0c0-2.4-.96-4.56-2.4-6.48-1.68-2.16-3.6-4.32-4.35-6.27z" />
                  </svg>
                  <span>{@streak} Day Streak</span>
                </div>
              </div>

              <%!-- 4 Metric Tiles --%>
              <div class="grid grid-cols-2 gap-2 mb-3">
                <div class="p-3 rounded-2xl bg-white/5 border border-white/5 text-center">
                  <div class="text-2xl font-light font-ticker text-white">{@completed_today}</div>
                  <div class="text-[10px] font-semibold text-emerald-400 uppercase tracking-wider mt-0.5">Sessions Today</div>
                </div>
                <div class="p-3 rounded-2xl bg-white/5 border border-white/5 text-center">
                  <div class="text-2xl font-light font-ticker text-purple-300">{@focus_minutes_today}m</div>
                  <div class="text-[10px] font-semibold text-purple-400 uppercase tracking-wider mt-0.5">Focused Today</div>
                </div>
                <div class="p-3 rounded-2xl bg-white/5 border border-white/5 text-center">
                  <div class="text-2xl font-light font-ticker text-pink-300">{@focus_minutes_week}m</div>
                  <div class="text-[10px] font-semibold text-pink-400 uppercase tracking-wider mt-0.5">This Week</div>
                </div>
                <div class="p-3 rounded-2xl bg-white/5 border border-white/5 text-center">
                  <div class="text-2xl font-light font-ticker text-cyan-300">{div(@focus_duration, 60)}m</div>
                  <div class="text-[10px] font-semibold text-cyan-400 uppercase tracking-wider mt-0.5">Target / Block</div>
                </div>
              </div>

              <%!-- Subject Breakdown Bars --%>
              <div class="mb-4">
                <div class="text-xs font-bold text-white/80 mb-2">Subject Time Distribution (This Week)</div>
                <%= if @subject_breakdown == [] do %>
                  <div class="p-3 rounded-xl bg-white/5 text-center text-xs text-white/40 italic">
                    No sessions logged yet this week. Complete a Pomodoro to see breakdown!
                  </div>
                <% else %>
                  <div class="flex flex-col gap-2">
                    <%= for item <- @subject_breakdown do %>
                      <div class="p-2.5 rounded-xl bg-white/5 border border-white/5 flex flex-col gap-1">
                        <div class="flex items-center justify-between text-xs">
                          <span class="font-medium text-white/90">{item.subject}</span>
                          <span class="font-ticker text-white/50">{item.minutes}m ({item.percentage}%)</span>
                        </div>
                        <div class="w-full h-1.5 rounded-full bg-white/10 overflow-hidden">
                          <div
                            class="h-full rounded-full transition-all duration-500"
                            style={"width: #{item.percentage}%; background: #{subject_bar_color(item.subject)};"}
                          />
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <%!-- Weekly Consistency Mini Chart --%>
              <div>
                <div class="text-xs font-bold text-white/80 mb-2">Weekly Consistency (Mon–Sun)</div>
                <div class="grid grid-cols-7 gap-1 p-2.5 rounded-2xl bg-white/5 border border-white/5 text-center">
                  <%= for day <- 1..7 do %>
                    <% count = get_in(@daily_activity, [day, :count]) || 0 %>
                    <div class="flex flex-col items-center gap-1">
                      <div class="text-[9px] font-bold text-white/40">{Schedule.day_short(day)}</div>
                      <div class="w-full h-12 flex items-end justify-center">
                        <div
                          class={"w-full rounded-t transition-all duration-500 #{if count > 0, do: "bg-gradient-to-t from-pink-500 to-purple-500", else: "bg-white/5"}"}
                          style={"height: #{min(count * 12 + 4, 48)}px;"}
                        />
                      </div>
                      <div class="text-[10px] font-ticker text-white/70">{count}</div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- ════════ VIEW 4: WEEKLY REVIEW ════════ --%>
          <%= if @view == :review do %>
            <div class="flex-1 flex flex-col p-4 overflow-hidden min-h-0">
              <%!-- Top Header (Pinned) --%>
              <div class="flex-shrink-0 flex items-center justify-between mb-2">
                <div>
                  <h2 class="text-sm font-bold text-white tracking-tight">Saturday Weekly Review</h2>
                  <p class="text-[11px] text-white/40">Checklist from your 8-week learning plan</p>
                </div>
                <%= if @weekly_review && review_completed_count(@weekly_review) == 6 do %>
                  <span class="inline-flex items-center gap-1 text-[10px] font-extrabold px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/40">
                    <svg viewBox="0 0 20 20" fill="currentColor" class="w-3 h-3 text-emerald-400">
                      <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                    </svg>
                    Completed
                  </span>
                <% else %>
                  <span class="text-[10px] font-ticker px-2 py-0.5 rounded-full bg-white/10 text-white/70 border border-white/10">
                    {if @weekly_review, do: review_completed_count(@weekly_review), else: 0} / 6 Checked
                  </span>
                <% end %>
              </div>

              <%!-- Week Tabs Bar (Pinned 8-column grid: permanently visible, never covered!) --%>
              <div class="flex-shrink-0 grid grid-cols-8 gap-1 p-1 bg-white/5 border border-white/5 rounded-2xl mb-3 z-10 relative">
                <%= for w <- 1..8 do %>
                  <button
                    phx-click="select_week"
                    phx-value-week={w}
                    class={"py-1.5 px-0.5 min-w-0 rounded-xl text-center text-[11px] sm:text-xs font-bold transition truncate #{if @selected_week == w, do: "bg-amber-500/25 text-amber-200 shadow-sm shadow-amber-500/30 border border-amber-500/40", else: "text-white/40 hover:text-white hover:bg-white/5"}"}
                  >
                    W{w}
                  </button>
                <% end %>
              </div>

              <%!-- Scrollable Review Body --%>
              <div class="flex-1 overflow-y-auto pomo-scroll pr-1 flex flex-col gap-3 min-h-0">
                <%= if @weekly_review do %>
                  <%!-- Week Goal & Deliverable Banner --%>
                  <div class="p-3 rounded-2xl bg-amber-500/10 border border-amber-500/20 flex flex-col gap-1.5">
                    <div class="text-xs font-bold text-amber-200">{@weekly_review.week_label}</div>
                    <%= if @weekly_review.deliverable_notes do %>
                      <div class="text-[11px] text-amber-300/80 flex items-start gap-1.5">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-amber-400 flex-shrink-0 mt-0.5">
                          <circle cx="12" cy="12" r="10" />
                          <circle cx="12" cy="12" r="6" />
                          <circle cx="12" cy="12" r="2" />
                        </svg>
                        <span><strong class="text-amber-200">Deliverable:</strong> {@weekly_review.deliverable_notes}</span>
                      </div>
                    <% end %>
                  </div>

                  <%!-- 6-Point Checklist Items --%>
                  <div class="flex flex-col gap-2">
                    <% items = [
                      {"concept_explained", "Can explain this week's CodeIntuition concept without reading", @weekly_review.concept_explained},
                      {"problems_solved", "Solved problems independently & recorded mistake insights", @weekly_review.problems_solved},
                      {"erlang_code_run", "Wrote/ran Erlang or Elixir code related to this week's reading", @weekly_review.erlang_code_run},
                      {"csharp_progress", "Made progress in C# on at least 2 scheduled days", @weekly_review.csharp_progress},
                      {"book_ideas_captured", "Captured key ideas from other software engineering book", @weekly_review.book_ideas_captured},
                      {"next_monday_task_selected", "Selected next concrete focus task for Monday morning", @weekly_review.next_monday_task_selected}
                    ] %>

                    <%= for {field, label, checked} <- items do %>
                      <div
                        phx-click="toggle_review_check"
                        phx-value-field={field}
                        class={"review-item #{if checked, do: "checked", else: ""}"}
                      >
                        <div class="review-checkbox">
                          <%= if checked do %>
                            <svg viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5 text-white">
                              <path
                                fill-rule="evenodd"
                                d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                                clip-rule="evenodd"
                              />
                            </svg>
                          <% end %>
                        </div>
                        <span class={"text-xs leading-snug flex-1 #{if checked, do: "text-emerald-200 line-through opacity-80", else: "text-white/80"}"}>
                          {label}
                        </span>
                      </div>
                    <% end %>
                  </div>

                  <%!-- Deliverable Checkbox --%>
                  <div
                    phx-click="toggle_deliverable"
                    class={"review-item #{if @weekly_review.deliverable_completed, do: "checked", else: ""}"}
                  >
                    <div class="review-checkbox">
                      <%= if @weekly_review.deliverable_completed do %>
                        <svg viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5 text-white">
                          <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                        </svg>
                      <% end %>
                    </div>
                    <span class={"text-xs font-semibold leading-snug flex-1 #{if @weekly_review.deliverable_completed, do: "text-emerald-300", else: "text-amber-200"}"}>
                      Deliverable completed & demonstrated
                    </span>
                  </div>

                  <%!-- Monday Notes / Next Task Form --%>
                  <form phx-submit="save_review_notes" class="flex flex-col gap-2">
                    <label class="text-[10px] font-bold uppercase tracking-wider text-white/40">Next Monday Concrete Task</label>
                    <input
                      type="text"
                      name="next_task_notes"
                      value={@weekly_review.next_task_notes || ""}
                      placeholder="e.g. Implement tail recursion on tree traversal"
                      class="pomo-input px-3 py-2 text-xs w-full"
                    />
                    <div class="flex justify-between items-center mt-1">
                      <%= if @review_saved_notice do %>
                        <span class="text-[11px] text-emerald-400 font-semibold">Saved!</span>
                      <% else %>
                        <span></span>
                      <% end %>
                      <button type="submit" class="px-3 py-1.5 rounded-xl text-xs font-bold bg-white/10 hover:bg-white/20 text-white transition">
                        Save Notes
                      </button>
                    </div>
                  </form>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- ════════ VIEW 5: SETTINGS ════════ --%>
          <%= if @view == :settings do %>
            <div class="flex-1 flex flex-col p-4 overflow-y-auto pomo-scroll min-h-0">
              <div class="flex items-center justify-between mb-3">
                <div>
                  <h2 class="text-sm font-bold text-white tracking-tight">Preferences & Audio</h2>
                  <p class="text-[11px] text-white/40">Customize your focus environment</p>
                </div>
              </div>

              <form phx-submit="save_settings" class="flex flex-col gap-3 pb-2">
                <%!-- Active Subject --%>
                <div>
                  <label class="block text-[10px] font-bold text-white/40 uppercase tracking-wider mb-1.5">
                    Default Study Subject
                  </label>
                  <select name="subject" class="pomo-input w-full px-3 py-2 text-xs bg-slate-900">
                    <%= for subj <- ["CodeIntuition", "Erlang/Elixir", "C# / .NET", "Engineering Book", "Weekly Review"] do %>
                      <option value={subj} selected={@subject == subj}>{subj}</option>
                    <% end %>
                  </select>
                </div>

                <%!-- Task Name --%>
                <div>
                  <label class="block text-[10px] font-bold text-white/40 uppercase tracking-wider mb-1.5">
                    Task Name
                  </label>
                  <input
                    type="text"
                    name="task_name"
                    value={@task_name}
                    placeholder="Focus Session description"
                    class="pomo-input w-full px-3 py-2 text-xs"
                  />
                </div>

                <%!-- Durations --%>
                <div class="grid grid-cols-2 gap-2">
                  <div>
                    <label class="block text-[10px] font-bold text-pink-400 uppercase tracking-wider mb-1">
                      Focus (min)
                    </label>
                    <input
                      type="number"
                      name="focus_min"
                      value={div(@focus_duration, 60)}
                      min="1"
                      max="120"
                      class="pomo-input w-full px-3 py-2 text-xs font-ticker"
                    />
                  </div>
                  <div>
                    <label class="block text-[10px] font-bold text-emerald-400 uppercase tracking-wider mb-1">
                      Break (min)
                    </label>
                    <input
                      type="number"
                      name="break_min"
                      value={div(@short_break_duration, 60)}
                      min="1"
                      max="60"
                      class="pomo-input w-full px-3 py-2 text-xs font-ticker"
                    />
                  </div>
                </div>

                <%!-- Sound Testing Section (Vector Icons, No Emojis) --%>
                <div class="p-3 rounded-2xl bg-white/5 border border-white/5 mt-1 flex flex-col gap-2">
                  <div class="text-xs font-bold text-white/80">Gentle Alarm Sound Effects</div>
                  <div class="grid grid-cols-2 gap-2">
                    <button
                      type="button"
                      phx-click="test_alarm"
                      phx-value-type="focus_end"
                      class="px-2.5 py-1.5 rounded-xl text-xs bg-white/5 hover:bg-white/10 text-pink-300 border border-white/10 text-center transition flex items-center justify-center gap-1.5"
                    >
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-pink-400">
                        <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
                        <path d="M13.73 21a2 2 0 0 1-3.46 0" />
                      </svg>
                      <span>Chime (Focus)</span>
                    </button>
                    <button
                      type="button"
                      phx-click="test_alarm"
                      phx-value-type="break_end"
                      class="px-2.5 py-1.5 rounded-xl text-xs bg-white/5 hover:bg-white/10 text-emerald-300 border border-white/10 text-center transition flex items-center justify-center gap-1.5"
                    >
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-emerald-400">
                        <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
                        <path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07" />
                      </svg>
                      <span>Tone (Break)</span>
                    </button>
                  </div>
                </div>

                <button
                  type="submit"
                  class="btn-play w-full py-2.5 rounded-xl font-bold text-xs text-white tracking-wide shadow-md hover:scale-[1.02] active:scale-[0.98] transition mt-2"
                >
                  Save Settings
                </button>
              </form>
            </div>
          <% end %>

          <%!-- ════════ INTEGRATED MUSIC BAR ════════ --%>
          <div
            class="w-full px-3 py-2 flex items-center justify-between gap-2 border-t border-white/5 bg-black/30 backdrop-blur-md"
            style="min-height: 40px;"
          >
            <%!-- Music toggle --%>
            <button
              phx-click="toggle_music"
              title={if @music_enabled, do: "Disable background music", else: "Enable background music"}
              class={"w-7 h-7 rounded-lg flex items-center justify-center transition #{if @music_enabled, do: "bg-purple-500/20 text-purple-300 border border-purple-500/40 shadow-sm shadow-purple-500/20", else: "bg-white/5 text-white/30 hover:text-white"}"}
            >
              <svg viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5">
                <path
                  fill-rule="evenodd"
                  d="M19.952 1.651a.75.75 0 01.298.599V16.303a3 3 0 01-2.176 2.884l-1.32.377a2.553 2.553 0 11-1.403-4.909l2.311-.66a1.5 1.5 0 001.088-1.442V6.994l-9.75 2.572v9.737a3 3 0 01-2.176 2.884l-1.32.377a2.553 2.553 0 11-1.402-4.909l2.31-.66a1.5 1.5 0 001.088-1.442V5.25a.75.75 0 01.544-.721l12-3.75a.75.75 0 01.706.152z"
                  clip-rule="evenodd"
                />
              </svg>
            </button>

            <%!-- Track info with equalizer --%>
            <div class="flex-1 flex items-center gap-2 min-w-0">
              <%= if @music_playing and @music_track do %>
                <div class="flex items-end gap-[2px] flex-shrink-0" style="height: 12px;">
                  <div class="eq-bar w-[2px] bg-purple-400 rounded-full" style="animation: eq 0.8s ease-in-out infinite;"></div>
                  <div class="eq-bar w-[2px] bg-pink-400 rounded-full" style="animation: eq 0.8s ease-in-out 0.2s infinite;"></div>
                  <div class="eq-bar w-[2px] bg-purple-400 rounded-full" style="animation: eq 0.8s ease-in-out 0.4s infinite;"></div>
                </div>
                <span class="text-[11px] text-white/70 italic truncate">{@music_track}</span>
              <% else %>
                <span class="text-[11px] text-white/30 italic">
                  {if @music_enabled, do: "Brain.fm · Ready on focus", else: "Music muted"}
                </span>
              <% end %>
            </div>

            <%!-- Skip Track Button --%>
            <%= if @music_playing do %>
              <button
                phx-click="skip_track"
                title="Skip to next track"
                class="w-6 h-6 rounded flex items-center justify-center text-white/40 hover:text-white transition"
              >
                <svg viewBox="0 0 24 24" fill="currentColor" class="w-3 h-3">
                  <path d="M5.055 7.514a.75.75 0 011.395-.278l2.969 5.936a.75.75 0 010 .656l-2.969 5.936A.75.75 0 015.055 20V7.514z" />
                  <path d="M13.055 7.514a.75.75 0 011.395-.278l2.969 5.936a.75.75 0 010 .656l-2.969 5.936a.75.75 0 01-1.395-.278V7.514z" />
                </svg>
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- ── Bottom Navigation Bar ── --%>
      <div
        class="flex-shrink-0 flex items-center justify-around px-2 h-14 w-full bg-slate-950/80 backdrop-blur-xl border-t border-white/5"
      >
        <button
          phx-click="set_view"
          phx-value-view="timer"
          class={"nav-tab #{if @view == :timer, do: "active", else: ""}"}
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4">
            <circle cx="12" cy="12" r="10" />
            <polyline points="12 6 12 12 16 14" />
          </svg>
          <span>Timer</span>
        </button>

        <button
          phx-click="set_view"
          phx-value-view="schedule"
          class={"nav-tab #{if @view == :schedule, do: "active", else: ""}"}
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4">
            <rect x="3" y="4" width="18" height="18" rx="2" ry="2" />
            <line x1="16" y1="2" x2="16" y2="6" />
            <line x1="8" y1="2" x2="8" y2="6" />
            <line x1="3" y1="10" x2="21" y2="10" />
          </svg>
          <span>Schedule</span>
        </button>

        <button
          phx-click="set_view"
          phx-value-view="analytics"
          class={"nav-tab #{if @view == :analytics, do: "active", else: ""}"}
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4">
            <line x1="18" y1="20" x2="18" y2="10" />
            <line x1="12" y1="20" x2="12" y2="4" />
            <line x1="6" y1="20" x2="6" y2="14" />
          </svg>
          <span>Stats</span>
        </button>

        <button
          phx-click="set_view"
          phx-value-view="review"
          class={"nav-tab #{if @view == :review, do: "active", else: ""}"}
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4">
            <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
            <polyline points="22 4 12 14.01 9 11.01" />
          </svg>
          <span>Review</span>
        </button>

        <button
          phx-click="set_view"
          phx-value-view="settings"
          class={"nav-tab #{if @view == :settings, do: "active", else: ""}"}
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4">
            <circle cx="12" cy="12" r="3" />
            <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z" />
          </svg>
          <span>Settings</span>
        </button>
      </div>
    </div>
    """
  end

  # ── Helpers ──

  defp format_time(seconds) do
    minutes = div(seconds, 60) |> Integer.to_string() |> String.pad_leading(2, "0")
    secs = rem(seconds, 60) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{minutes}:#{secs}"
  end

  defp format_clock(%Time{} = t) do
    h = t.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    m = t.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{h}:#{m}"
  end

  defp prettify_track_name(name) do
    name
    |> String.replace("_(mp3.pm)", "")
    |> String.replace("(mp3.pm)", "")
    |> String.replace("_-_", " · ")
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
    |> String.trim()
  end

  # Clean geometric SVG icons matching the glassmorphic aesthetic (no emojis)
  defp render_subject_icon(subject) do
    svg_str =
      case subject do
        "CodeIntuition" ->
          """
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-indigo-400 inline-block flex-shrink-0">
            <rect x="4" y="4" width="16" height="16" rx="2" />
            <rect x="9" y="9" width="6" height="6" />
            <line x1="9" y1="1" x2="9" y2="4" />
            <line x1="15" y1="1" x2="15" y2="4" />
            <line x1="9" y1="20" x2="9" y2="23" />
            <line x1="15" y1="20" x2="15" y2="23" />
            <line x1="20" y1="9" x2="23" y2="9" />
            <line x1="20" y1="15" x2="23" y2="15" />
            <line x1="1" y1="9" x2="4" y2="9" />
            <line x1="1" y1="15" x2="4" y2="15" />
          </svg>
          """

        "Erlang/Elixir" ->
          """
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-rose-400 inline-block flex-shrink-0">
            <path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 3.5z" />
          </svg>
          """

        "C# / .NET" ->
          """
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-purple-400 inline-block flex-shrink-0">
            <polyline points="16 18 22 12 16 6" />
            <polyline points="8 6 2 12 8 18" />
            <line x1="14" y1="4" x2="10" y2="20" />
          </svg>
          """

        "Engineering Book" ->
          """
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-cyan-400 inline-block flex-shrink-0">
            <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
            <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
          </svg>
          """

        "Weekly Review" ->
          """
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-amber-400 inline-block flex-shrink-0">
            <path d="M9 11l3 3L22 4" />
            <path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" />
          </svg>
          """

        "Lunch & Prayer" ->
          """
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-slate-400 inline-block flex-shrink-0">
            <circle cx="12" cy="12" r="5" />
            <line x1="12" y1="1" x2="12" y2="3" />
            <line x1="12" y1="21" x2="12" y2="23" />
            <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
            <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
            <line x1="1" y1="12" x2="3" y2="12" />
            <line x1="21" y1="12" x2="23" y2="12" />
            <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
            <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
          </svg>
          """

        "Work" ->
          """
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-blue-400 inline-block flex-shrink-0">
            <rect x="2" y="7" width="20" height="14" rx="2" ry="2" />
            <path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16" />
          </svg>
          """

        "Rest Day" ->
          """
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-emerald-400 inline-block flex-shrink-0">
            <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
          </svg>
          """

        "Break" ->
          """
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-emerald-400 inline-block flex-shrink-0">
            <path d="M18 8h1a4 4 0 0 1 0 8h-1" />
            <path d="M2 8h16v9a4 4 0 0 1-4 4H6a4 4 0 0 1-4-4V8z" />
            <line x1="6" y1="1" x2="6" y2="4" />
            <line x1="10" y1="1" x2="10" y2="4" />
            <line x1="14" y1="1" x2="14" y2="4" />
          </svg>
          """

        _ ->
          """
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-3.5 h-3.5 text-pink-400 inline-block flex-shrink-0">
            <circle cx="12" cy="12" r="10" />
            <circle cx="12" cy="12" r="6" />
            <circle cx="12" cy="12" r="2" />
          </svg>
          """
      end

    Phoenix.HTML.raw(svg_str)
  end

  defp short_subject_label(subject) do
    case subject do
      "CodeIntuition" -> "CodeIntuition"
      "Erlang/Elixir" -> "Erlang"
      "C# / .NET" -> "C#"
      "Engineering Book" -> "Book"
      "Weekly Review" -> "Review"
      _ -> subject
    end
  end

  defp subject_bg(subject) do
    case subject do
      "CodeIntuition" -> "rgba(99, 102, 241, 0.18)"
      "Erlang/Elixir" -> "rgba(244, 63, 94, 0.18)"
      "C# / .NET" -> "rgba(139, 92, 246, 0.18)"
      "Engineering Book" -> "rgba(6, 182, 212, 0.18)"
      "Weekly Review" -> "rgba(234, 179, 8, 0.18)"
      _ -> "rgba(255, 255, 255, 0.1)"
    end
  end

  defp subject_text_color(subject) do
    case subject do
      "CodeIntuition" -> "#a5b4fc"
      "Erlang/Elixir" -> "#fda4af"
      "C# / .NET" -> "#c4b5fd"
      "Engineering Book" -> "#67e8f9"
      "Weekly Review" -> "#fde047"
      _ -> "#ffffff"
    end
  end

  defp subject_border(subject) do
    case subject do
      "CodeIntuition" -> "rgba(99, 102, 241, 0.35)"
      "Erlang/Elixir" -> "rgba(244, 63, 94, 0.35)"
      "C# / .NET" -> "rgba(139, 92, 246, 0.35)"
      "Engineering Book" -> "rgba(6, 182, 212, 0.35)"
      "Weekly Review" -> "rgba(234, 179, 8, 0.35)"
      _ -> "rgba(255, 255, 255, 0.2)"
    end
  end

  defp subject_bar_color(subject) do
    case subject do
      "CodeIntuition" -> "linear-gradient(90deg, #6366f1, #818cf8)"
      "Erlang/Elixir" -> "linear-gradient(90deg, #f43f5e, #fb7185)"
      "C# / .NET" -> "linear-gradient(90deg, #8b5cf6, #a78bfa)"
      "Engineering Book" -> "linear-gradient(90deg, #06b6d4, #22d3ee)"
      "Weekly Review" -> "linear-gradient(90deg, #eab308, #facc15)"
      _ -> "linear-gradient(90deg, #ec4899, #f472b6)"
    end
  end

  defp review_completed_count(review) do
    [
      review.concept_explained,
      review.problems_solved,
      review.erlang_code_run,
      review.csharp_progress,
      review.book_ideas_captured,
      review.next_monday_task_selected
    ]
    |> Enum.count(& &1)
  end
end
