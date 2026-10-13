defmodule PomodoroApp.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions) do
      add :duration, :integer
      add :phase, :string

      timestamps(type: :utc_datetime)
    end
  end
end
