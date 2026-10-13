defmodule PomodoroApp.AnalyticsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PomodoroApp.Analytics` context.
  """

  @doc """
  Generate a session.
  """
  def session_fixture(attrs \\ %{}) do
    {:ok, session} =
      attrs
      |> Enum.into(%{
        duration: 42,
        phase: "some phase"
      })
      |> PomodoroApp.Analytics.create_session()

    session
  end
end
