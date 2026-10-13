defmodule PomodoroApp.Repo.Migrations.AddSubjectToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :subject, :string
      add :task_name, :string
    end
  end
end
