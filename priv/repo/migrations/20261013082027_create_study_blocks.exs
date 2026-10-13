defmodule PomodoroApp.Repo.Migrations.CreateStudyBlocks do
  use Ecto.Migration

  def change do
    create table(:study_blocks) do
      add :subject, :string, null: false
      add :title, :string, null: false
      add :day_of_week, :integer, null: false
      add :start_time, :time, null: false
      add :end_time, :time, null: false
      add :description, :text
      add :color, :string, default: "#6366f1"
      add :icon, :string, default: "book"
      add :is_rest_block, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:study_blocks, [:day_of_week])
  end
end
