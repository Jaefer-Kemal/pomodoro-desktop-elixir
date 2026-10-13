defmodule PomodoroApp.Schedule do
  @moduledoc """
  The Schedule context managing study blocks, daily routines, and weekly review checklists.
  """

  import Ecto.Query, warn: false
  alias PomodoroApp.Repo
  alias PomodoroApp.Schedule.{StudyBlock, WeeklyReview}

  # Plan reference start: October 14, 2026
  @plan_start_date ~D[2026-10-14]

  # ── Study Blocks ──

  def list_study_blocks do
    StudyBlock
    |> order_by([b], [asc: b.day_of_week, asc: b.start_time])
    |> Repo.all()
  end

  def list_study_blocks_for_day(day_of_week) when is_integer(day_of_week) do
    StudyBlock
    |> where([b], b.day_of_week == ^day_of_week)
    |> order_by([b], asc: b.start_time)
    |> Repo.all()
  end

  def get_study_block!(id), do: Repo.get!(StudyBlock, id)

  def create_study_block(attrs \\ %{}) do
    %StudyBlock{}
    |> StudyBlock.changeset(attrs)
    |> Repo.insert()
  end

  def update_study_block(%StudyBlock{} = block, attrs) do
    block
    |> StudyBlock.changeset(attrs)
    |> Repo.update()
  end

  def delete_study_block(%StudyBlock{} = block) do
    Repo.delete(block)
  end

  @doc """
  Returns current OS local {Date, Time} using system clock.
  """
  def local_date_and_time do
    {{y, m, d}, {h, min, s}} = :calendar.local_time()
    {Date.new!(y, m, d), Time.new!(h, min, s)}
  end

  @doc """
  Finds the active study block and next upcoming block for the given day and time.
  """
  def get_current_and_next_block(day_of_week, %Time{} = current_time) do
    blocks = list_study_blocks_for_day(day_of_week)

    current =
      Enum.find(blocks, fn b ->
        Time.compare(current_time, b.start_time) in [:gt, :eq] and
          Time.compare(current_time, b.end_time) == :lt
      end)

    upcoming =
      Enum.find(blocks, fn b ->
        Time.compare(b.start_time, current_time) == :gt
      end)

    {current, upcoming}
  end

  def get_current_and_next_block do
    {local_date, local_time} = local_date_and_time()
    day_of_week = Date.day_of_week(local_date)
    get_current_and_next_block(day_of_week, local_time)
  end

  # ── Weekly Reviews ──

  def list_weekly_reviews do
    WeeklyReview
    |> order_by([r], asc: r.week_number)
    |> Repo.all()
  end

  def get_weekly_review!(id), do: Repo.get!(WeeklyReview, id)

  def get_weekly_review_by_week(week_number) do
    Repo.get_by(WeeklyReview, week_number: week_number)
  end

  def update_weekly_review(%WeeklyReview{} = review, attrs) do
    changeset = WeeklyReview.changeset(review, attrs)

    # Check if all 6 items are completed to auto-mark completed
    current_attrs = Ecto.Changeset.apply_changes(changeset)

    all_done =
      current_attrs.concept_explained &&
        current_attrs.problems_solved &&
        current_attrs.erlang_code_run &&
        current_attrs.csharp_progress &&
        current_attrs.book_ideas_captured &&
        current_attrs.next_monday_task_selected

    changeset =
      if all_done do
        changeset
        |> Ecto.Changeset.put_change(:completed, true)
        |> Ecto.Changeset.put_change(:reviewed_at, DateTime.utc_now())
      else
        changeset
      end

    Repo.update(changeset)
  end

  def toggle_review_field(%WeeklyReview{} = review, field_name) when is_atom(field_name) do
    current_val = Map.get(review, field_name, false)
    update_weekly_review(review, %{field_name => not current_val})
  end

  @doc """
  Calculates the current week (1-8) of the 8-week roadmap based on plan start date.
  Clamped between 1 and 8.
  """
  def current_week_number do
    {today, _} = local_date_and_time()
    diff_days = Date.diff(today, @plan_start_date)

    cond do
      diff_days < 0 -> 1
      diff_days >= 56 -> 8
      true -> div(diff_days, 7) + 1
    end
  end

  def day_name(day_of_week) do
    case day_of_week do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
      _ -> "Day #{day_of_week}"
    end
  end

  def day_short(day_of_week) do
    case day_of_week do
      1 -> "Mon"
      2 -> "Tue"
      3 -> "Wed"
      4 -> "Thu"
      5 -> "Fri"
      6 -> "Sat"
      7 -> "Sun"
      _ -> "#{day_of_week}"
    end
  end
end
