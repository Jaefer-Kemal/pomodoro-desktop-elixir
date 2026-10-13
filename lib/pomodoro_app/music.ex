defmodule PomodoroApp.Music do
  @moduledoc """
  Music catalog that scans the `music_pomodoro/` folder and categorizes
  tracks by parsing their filenames. Provides shuffled playlists for
  focus, relax, nap, and sleep moods.

  Categories are inferred from filename keywords:
    - "focus", "piano_focus", "moon_garden" → :focus
    - "relax"                               → :relax
    - "nap"                                 → :nap
    - "sleep"                               → :sleep
  """

  use GenServer

  # ── Client API ──

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Returns a list of {filename, category} tuples for all tracks."
  def list_tracks do
    GenServer.call(__MODULE__, :list_tracks)
  end

  @doc "Returns a shuffled list of track filenames for the given category."
  def playlist(category) when category in [:focus, :relax, :nap, :sleep] do
    GenServer.call(__MODULE__, {:playlist, category})
  end

  @doc "Returns the next track for a given category, cycling through the shuffled playlist."
  def next_track(category) do
    GenServer.call(__MODULE__, {:next_track, category})
  end

  @doc "Returns the previous track for a given category, cycling backwards through the playlist."
  def prev_track(category) do
    GenServer.call(__MODULE__, {:prev_track, category})
  end

  @doc "Returns all tracks categorized with display names."
  def list_catalog do
    GenServer.call(__MODULE__, :list_catalog)
  end

  @doc "Resets and reshuffles the playlist for a category."
  def reshuffle(category) do
    GenServer.cast(__MODULE__, {:reshuffle, category})
  end

  # ── Server Callbacks ──

  @impl true
  def init(_state) do
    tracks = scan_music_folder()
    playlists = build_playlists(tracks)

    state = %{
      tracks: tracks,
      playlists: playlists,
      # Track the current index per category for cycling
      indices: %{focus: 0, relax: 0, nap: 0, sleep: 0}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:list_tracks, _from, state) do
    {:reply, state.tracks, state}
  end

  @impl true
  def handle_call({:playlist, category}, _from, state) do
    tracks = Map.get(state.playlists, category, [])
    {:reply, tracks, state}
  end

  @impl true
  def handle_call({:next_track, category}, _from, state) do
    playlist = Map.get(state.playlists, category, [])

    if playlist == [] do
      # Fall back to focus tracks if category is empty
      fallback = Map.get(state.playlists, :focus, [])

      if fallback == [] do
        {:reply, nil, state}
      else
        idx = Map.get(state.indices, :focus, 0)
        track = Enum.at(fallback, rem(idx, length(fallback)))
        new_indices = Map.put(state.indices, :focus, idx + 1)
        {:reply, track, %{state | indices: new_indices}}
      end
    else
      idx = Map.get(state.indices, category, 0)
      track = Enum.at(playlist, rem(idx, length(playlist)))
      new_indices = Map.put(state.indices, category, idx + 1)
      {:reply, track, %{state | indices: new_indices}}
    end
  end

  @impl true
  def handle_call({:prev_track, category}, _from, state) do
    playlist = Map.get(state.playlists, category, [])

    if playlist == [] do
      fallback = Map.get(state.playlists, :focus, [])

      if fallback == [] do
        {:reply, nil, state}
      else
        len = length(fallback)
        idx = Map.get(state.indices, :focus, 0)
        new_idx = rem(idx - 1 + len, len)
        track = Enum.at(fallback, new_idx)
        new_indices = Map.put(state.indices, :focus, new_idx)
        {:reply, track, %{state | indices: new_indices}}
      end
    else
      len = length(playlist)
      idx = Map.get(state.indices, category, 0)
      new_idx = rem(idx - 1 + len, len)
      track = Enum.at(playlist, new_idx)
      new_indices = Map.put(state.indices, category, new_idx)
      {:reply, track, %{state | indices: new_indices}}
    end
  end

  @impl true
  def handle_call(:list_catalog, _from, state) do
    catalog =
      Enum.map(state.tracks, fn {filename, category} ->
        clean_name =
          filename
          |> String.replace(".mp3", "")
          |> String.replace(~r/[_\-]+/, " ")
          |> String.replace(~r/\(.*\)/, "")
          |> String.trim()

        %{
          filename: filename,
          name: clean_name,
          category: category
        }
      end)

    {:reply, catalog, state}
  end

  @impl true
  def handle_cast({:reshuffle, category}, state) do
    current = Map.get(state.playlists, category, [])
    reshuffled = Enum.shuffle(current)
    new_playlists = Map.put(state.playlists, category, reshuffled)
    new_indices = Map.put(state.indices, category, 0)
    {:noreply, %{state | playlists: new_playlists, indices: new_indices}}
  end

  # ── Private Helpers ──

  defp scan_music_folder do
    music_dir = music_folder_path()

    if File.dir?(music_dir) do
      music_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".mp3"))
      |> Enum.map(fn filename ->
        category = categorize(String.downcase(filename))
        {filename, category}
      end)
    else
      []
    end
  end

  defp music_folder_path do
    # In development, the music folder sits alongside the app
    # In production release, it would be in the release root
    cond do
      File.dir?(Path.join(File.cwd!(), "music_pomodoro")) ->
        Path.join(File.cwd!(), "music_pomodoro")

      File.dir?(Path.join(:code.priv_dir(:pomodoro_app) |> to_string(), "music_pomodoro")) ->
        Path.join(:code.priv_dir(:pomodoro_app) |> to_string(), "music_pomodoro")

      true ->
        Path.join(File.cwd!(), "music_pomodoro")
    end
  end

  defp categorize(filename) do
    cond do
      String.contains?(filename, "nap") -> :nap
      String.contains?(filename, "sleep") -> :sleep
      String.contains?(filename, "relax") and not String.contains?(filename, "focus") -> :relax
      String.contains?(filename, "focus") -> :focus
      String.contains?(filename, "piano") -> :focus
      String.contains?(filename, "moon_garden") -> :focus
      String.contains?(filename, "moon") -> :focus
      true -> :focus
    end
  end

  defp build_playlists(tracks) do
    grouped =
      tracks
      |> Enum.group_by(fn {_name, cat} -> cat end, fn {name, _cat} -> name end)

    %{
      focus: Enum.shuffle(Map.get(grouped, :focus, [])),
      relax: Enum.shuffle(Map.get(grouped, :relax, [])),
      nap: Enum.shuffle(Map.get(grouped, :nap, [])),
      sleep: Enum.shuffle(Map.get(grouped, :sleep, []))
    }
  end
end
