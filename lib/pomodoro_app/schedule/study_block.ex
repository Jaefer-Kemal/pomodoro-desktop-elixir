defmodule PomodoroApp.Schedule.StudyBlock do
  use Ecto.Schema
  import Ecto.Changeset

  schema "study_blocks" do
    field :subject, :string
    field :title, :string
    field :day_of_week, :integer
    field :start_time, :time
    field :end_time, :time
    field :description, :string
    field :color, :string, default: "#6366f1"
    field :icon, :string, default: "book"
    field :is_rest_block, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(study_block, attrs) do
    study_block
    |> cast(attrs, [
      :subject,
      :title,
      :day_of_week,
      :start_time,
      :end_time,
      :description,
      :color,
      :icon,
      :is_rest_block
    ])
    |> validate_required([:subject, :title, :day_of_week, :start_time, :end_time])
    |> validate_inclusion(:day_of_week, 1..7)
  end
end
