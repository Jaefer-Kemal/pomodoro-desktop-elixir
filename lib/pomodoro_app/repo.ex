defmodule PomodoroApp.Repo do
  use Ecto.Repo,
    otp_app: :pomodoro_app,
    adapter: Ecto.Adapters.SQLite3
end
