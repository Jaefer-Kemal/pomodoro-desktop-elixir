defmodule PomodoroApp.Release do
  @moduledoc """
  Used in production releases to run Ecto migrations.
  Call via: bin/pomodoro_app eval "PomodoroApp.Release.migrate()"
  """
  @app :pomodoro_app

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          priv_dir = :code.priv_dir(@app) |> to_string()
          seeds_file = Path.join([priv_dir, "repo", "seeds.exs"])

          if File.exists?(seeds_file) do
            Code.eval_file(seeds_file)
          end
        end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
