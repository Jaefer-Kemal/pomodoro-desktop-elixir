defmodule PomodoroApp.Analytics.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sessions" do
    field :duration, :integer
    field :phase, :string
    field :subject, :string
    field :task_name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:duration, :phase, :subject, :task_name])
    |> validate_required([:duration, :phase])
  end
end
