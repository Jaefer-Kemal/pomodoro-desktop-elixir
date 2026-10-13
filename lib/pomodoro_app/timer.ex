defmodule PomodoroApp.Timer do
  @moduledoc """
  This is the heart of the Pomodoro application. It is a GenServer, which means it
  is a long-running Elixir process that can hold "state" (like a variable that
  remembers the current time) and receive messages.
  """

  use GenServer

  # This is the name we use for Phoenix PubSub broadcasts
  @topic "timer_updates"

  # Default durations in seconds
  @focus_time 25 * 60
  @short_break 5 * 60

  # --------------------------------------------------------
  # 1. Client API (Functions we call from our UI or other code)
  # --------------------------------------------------------

  @doc "Starts the GenServer process."
  def start_link(_opts) do
    # We name the process `__MODULE__` (PomodoroApp.Timer) so we can 
    # easily call it from anywhere without needing its Process ID (PID).
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Starts the countdown timer."
  def start_timer do
    GenServer.cast(__MODULE__, :start)
  end

  @doc "Pauses the countdown timer."
  def pause_timer do
    GenServer.cast(__MODULE__, :pause)
  end

  @doc "Resets the timer."
  def reset_timer do
    GenServer.cast(__MODULE__, :reset)
  end

  @doc "Gets the current state of the timer."
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc "Updates the timer settings."
  def update_settings(attrs) do
    GenServer.cast(__MODULE__, {:update_settings, attrs})
  end

  @doc "Sets the active subject and optional task name."
  def set_subject(subject, task_name \\ nil) do
    GenServer.cast(__MODULE__, {:set_subject, subject, task_name})
  end

  @doc "Helper function for UI to subscribe to PubSub updates."
  def subscribe do
    Phoenix.PubSub.subscribe(PomodoroApp.PubSub, @topic)
  end

  # --------------------------------------------------------
  # 2. Server Callbacks (How the GenServer handles internal logic)
  # --------------------------------------------------------

  @impl true
  def init(_state) do
    # This is the initial state of our GenServer when it boots up.
    initial_state = %{
      # Can be :stopped, :running, or :paused
      status: :stopped,
      # Can be :focus or :short_break
      phase: :focus,
      # Time remaining in seconds
      time_left: @focus_time,
      task_name: "Focus Session",
      subject: "CodeIntuition",
      focus_duration: @focus_time,
      short_break_duration: @short_break,
      completed_today: PomodoroApp.Analytics.get_completed_sessions_today()
    }

    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    # handle_call is for synchronous requests where the caller expects a reply.
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:start, state) do
    # handle_cast is for asynchronous messages. We start the timer here.
    if state.status != :running do
      # Send a message to ourselves in 1000ms (1 second) to "tick"
      schedule_tick()
      new_state = %{state | status: :running}
      broadcast(new_state)

      # Start music for the current phase
      music_category = if new_state.phase == :focus, do: :focus, else: :relax
      track = PomodoroApp.Music.next_track(music_category)

      if track do
        Phoenix.PubSub.broadcast(
          PomodoroApp.PubSub,
          @topic,
          {:music_play, track}
        )
      end

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:pause, state) do
    new_state = %{state | status: :paused}
    broadcast(new_state)
    # Pause the music
    Phoenix.PubSub.broadcast(PomodoroApp.PubSub, @topic, :music_pause)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reset, state) do
    # Reset back to the initial state for the current phase
    new_time =
      if state.phase == :focus, do: state.focus_duration, else: state.short_break_duration

    new_state = %{
      state
      | status: :stopped,
        time_left: new_time
    }

    broadcast(new_state)
    # Stop the music
    Phoenix.PubSub.broadcast(PomodoroApp.PubSub, @topic, :music_stop)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_subject, subject, task_name}, state) do
    new_task = task_name || state.task_name
    new_state = %{state | subject: subject, task_name: new_task}
    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_settings, attrs}, state) do
    task = Map.get(attrs, "task_name", state.task_name)
    focus = Map.get(attrs, "focus_duration", state.focus_duration)
    short = Map.get(attrs, "short_break_duration", state.short_break_duration)
    subject = Map.get(attrs, "subject", state.subject)

    new_state = %{
      state
      | task_name: task,
        focus_duration: focus,
        short_break_duration: short,
        subject: subject
    }

    # If the timer is stopped, reset the time left to the new duration
    new_state =
      if new_state.status == :stopped do
        new_time =
          if new_state.phase == :focus,
            do: new_state.focus_duration,
            else: new_state.short_break_duration

        %{new_state | time_left: new_time}
      else
        new_state
      end

    broadcast(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:tick, state) do
    # handle_info handles regular Erlang messages (like the one we scheduled).
    # If the timer is paused or stopped, we ignore the tick and don't schedule another.
    if state.status == :running do
      new_state = process_tick(state)
      broadcast(new_state)

      # If still running after processing, schedule the next tick
      if new_state.status == :running do
        schedule_tick()
      end

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # --------------------------------------------------------
  # 3. Private Helper Functions
  # --------------------------------------------------------

  # This function reduces the time by 1 second. If it hits 0, it switches phases.
  defp process_tick(%{time_left: time} = state) when time > 0 do
    %{state | time_left: time - 1}
  end

  defp process_tick(%{time_left: 0, phase: :focus} = state) do
    # Focus time ended! Save to database with subject and switch to short break.
    PomodoroApp.Analytics.create_session(%{
      duration: state.focus_duration,
      phase: "focus",
      subject: state.subject,
      task_name: state.task_name
    })
    completed = PomodoroApp.Analytics.get_completed_sessions_today()

    # Stop background focus music before alarm
    Phoenix.PubSub.broadcast(PomodoroApp.PubSub, @topic, :music_stop)

    # Broadcast an audio trigger with the phase that just ended
    Phoenix.PubSub.broadcast(PomodoroApp.PubSub, @topic, {:play_alarm, :focus_end})

    %{
      state
      | phase: :short_break,
        time_left: state.short_break_duration,
        status: :stopped,
        completed_today: completed
    }
  end

  defp process_tick(%{time_left: 0, phase: :short_break} = state) do
    # Break time ended! Save to database and switch back to focus.
    PomodoroApp.Analytics.create_session(%{
      duration: state.short_break_duration,
      phase: "short_break",
      subject: state.subject,
      task_name: state.task_name
    })

    # Stop break music before alarm
    Phoenix.PubSub.broadcast(PomodoroApp.PubSub, @topic, :music_stop)

    # Broadcast an audio trigger with the phase that just ended
    Phoenix.PubSub.broadcast(PomodoroApp.PubSub, @topic, {:play_alarm, :break_end})

    %{state | phase: :focus, time_left: state.focus_duration, status: :stopped}
  end

  defp schedule_tick do
    # Tells the Erlang VM to send a :tick message to this process in 1000ms
    Process.send_after(self(), :tick, 1000)
  end

  defp broadcast(state) do
    # This sends the new state to anyone listening (like our LiveView UI)
    Phoenix.PubSub.broadcast(PomodoroApp.PubSub, @topic, {:timer_update, state})
  end
end
