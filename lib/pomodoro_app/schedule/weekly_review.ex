defmodule PomodoroApp.Schedule.WeeklyReview do
  use Ecto.Schema
  import Ecto.Changeset

  schema "weekly_reviews" do
    field :week_number, :integer
    field :week_label, :string
    field :concept_explained, :boolean, default: false
    field :problems_solved, :boolean, default: false
    field :erlang_code_run, :boolean, default: false
    field :csharp_progress, :boolean, default: false
    field :book_ideas_captured, :boolean, default: false
    field :next_monday_task_selected, :boolean, default: false
    field :next_task_notes, :string
    field :deliverable_completed, :boolean, default: false
    field :deliverable_notes, :string
    field :completed, :boolean, default: false
    field :reviewed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(weekly_review, attrs) do
    weekly_review
    |> cast(attrs, [
      :week_number,
      :week_label,
      :concept_explained,
      :problems_solved,
      :erlang_code_run,
      :csharp_progress,
      :book_ideas_captured,
      :next_monday_task_selected,
      :next_task_notes,
      :deliverable_completed,
      :deliverable_notes,
      :completed,
      :reviewed_at
    ])
    |> validate_required([:week_number, :week_label])
    |> unique_constraint(:week_number)
  end
end
