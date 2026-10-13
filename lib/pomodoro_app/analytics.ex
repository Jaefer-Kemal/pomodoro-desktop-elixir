defmodule PomodoroApp.Analytics do
  @moduledoc """
  The Analytics context providing rich tracking for study sessions,
  subject breakdowns, streaks, and focus metrics.
  """

  import Ecto.Query, warn: false
  alias PomodoroApp.Repo
  alias PomodoroApp.Analytics.Session

  @doc """
  Returns all sessions.
  """
  def list_sessions do
    Session
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets completed focus sessions count today (UTC).
  """
  def get_completed_sessions_today do
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    Session
    |> where([s], s.phase == "focus" and s.inserted_at >= ^today_start)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Gets total focus minutes completed today.
  """
  def get_focus_minutes_today do
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    seconds =
      Session
      |> where([s], s.phase == "focus" and s.inserted_at >= ^today_start)
      |> Repo.aggregate(:sum, :duration) || 0

    div(seconds, 60)
  end

  @doc """
  Gets focus minutes completed this week (starting Monday).
  """
  def get_focus_minutes_this_week do
    today = Date.utc_today()
    days_from_monday = Date.day_of_week(today) - 1
    monday = Date.add(today, -days_from_monday)
    week_start = DateTime.new!(monday, ~T[00:00:00], "Etc/UTC")

    seconds =
      Session
      |> where([s], s.phase == "focus" and s.inserted_at >= ^week_start)
      |> Repo.aggregate(:sum, :duration) || 0

    div(seconds, 60)
  end

  @doc """
  Calculates the current study streak in consecutive days (at least 1 focus session per day).
  """
  def calculate_streak do
    # Fetch distinct dates of focus sessions in descending order
    dates =
      Session
      |> where([s], s.phase == "focus")
      |> select([s], fragment("date(?)", s.inserted_at))
      |> distinct(true)
      |> order_by([s], desc: fragment("date(?)", s.inserted_at))
      |> Repo.all()
      |> Enum.map(&Date.from_iso8601!/1)

    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    cond do
      dates == [] ->
        0

      hd(dates) != today and hd(dates) != yesterday ->
        # Streak broken
        0

      true ->
        # Count consecutive days backwards
        dates
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.reduce_while(1, fn [curr, prev_day], count ->
          if Date.diff(curr, prev_day) == 1 do
            {:cont, count + 1}
          else
            {:halt, count}
          end
        end)
    end
  end

  @doc """
  Subject breakdown for this week (subject name, minutes, session count, percentage of total).
  """
  def subject_breakdown_this_week do
    today = Date.utc_today()
    days_from_monday = Date.day_of_week(today) - 1
    monday = Date.add(today, -days_from_monday)
    week_start = DateTime.new!(monday, ~T[00:00:00], "Etc/UTC")

    query =
      from s in Session,
        where: s.phase == "focus" and s.inserted_at >= ^week_start,
        group_by: s.subject,
        select: %{
          subject: coalesce(s.subject, "General Focus"),
          total_seconds: sum(s.duration),
          sessions_count: count(s.id)
        }

    results = Repo.all(query)
    total_sec = Enum.reduce(results, 0, fn r, acc -> acc + (r.total_seconds || 0) end)

    results
    |> Enum.map(fn r ->
      sec = r.total_seconds || 0
      pct = if total_sec > 0, do: round(sec / total_sec * 100), else: 0

      %{
        subject: r.subject,
        minutes: div(sec, 60),
        sessions_count: r.sessions_count,
        percentage: pct
      }
    end)
    |> Enum.sort_by(& &1.minutes, :desc)
  end

  @doc """
  Daily session counts for each day of the current week (Monday=1 through Sunday=7).
  Returns map %{1 => count, 2 => count, ..., 7 => count}.
  """
  def daily_activity_this_week do
    today = Date.utc_today()
    days_from_monday = Date.day_of_week(today) - 1
    monday = Date.add(today, -days_from_monday)

    0..6
    |> Enum.map(fn offset ->
      date = Date.add(monday, offset)
      start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

      count =
        Session
        |> where([s], s.phase == "focus" and s.inserted_at >= ^start_dt and s.inserted_at <= ^end_dt)
        |> Repo.aggregate(:count, :id)

      # day_of_week: 1 = Mon .. 7 = Sun
      {offset + 1, %{date: date, count: count}}
    end)
    |> Map.new()
  end

  def get_session!(id), do: Repo.get!(Session, id)

  def create_session(attrs) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  def update_session(%Session{} = session, attrs) do
    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  def delete_session(%Session{} = session) do
    Repo.delete(session)
  end

  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
  end
end
