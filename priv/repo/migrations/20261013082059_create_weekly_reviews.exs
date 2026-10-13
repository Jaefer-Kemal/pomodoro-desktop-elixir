defmodule PomodoroApp.Repo.Migrations.CreateWeeklyReviews do
  use Ecto.Migration

  def change do
    create table(:weekly_reviews) do
      add :week_number, :integer, null: false
      add :week_label, :string, null: false
      add :concept_explained, :boolean, default: false
      add :problems_solved, :boolean, default: false
      add :erlang_code_run, :boolean, default: false
      add :csharp_progress, :boolean, default: false
      add :book_ideas_captured, :boolean, default: false
      add :next_monday_task_selected, :boolean, default: false
      add :next_task_notes, :text
      add :deliverable_completed, :boolean, default: false
      add :deliverable_notes, :text
      add :completed, :boolean, default: false
      add :reviewed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:weekly_reviews, [:week_number])
  end
end
