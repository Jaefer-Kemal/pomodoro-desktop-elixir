import Config

# Always enable the server (required by Desktop/wxWebView)
config :pomodoro_app, PomodoroAppWeb.Endpoint, server: true

# Use port 4000 by default
config :pomodoro_app, PomodoroAppWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  config :pomodoro_app, PomodoroAppWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        ~r"priv/gettext/.*\.po$"E,
        ~r"lib/pomodoro_app_web/router\.ex$"E,
        ~r"lib/pomodoro_app_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # Store the SQLite DB in the user's AppData (Windows) or home dir (other)
  default_db =
    case :os.type() do
      {:win32, _} ->
        app_data = System.get_env("APPDATA") || System.user_home!()
        Path.join([app_data, "PomodoroTimer", "pomodoro.db"])

      _ ->
        Path.join([System.user_home!(), ".pomodoro_timer", "pomodoro.db"])
    end

  database_path = System.get_env("DATABASE_PATH", default_db)

  # Ensure the directory exists before Ecto tries to open the DB
  database_path |> Path.dirname() |> File.mkdir_p!()

  config :pomodoro_app, PomodoroApp.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # Auto-generate and persist a secret key so no env var is required
  secret_key_base =
    case System.get_env("SECRET_KEY_BASE") do
      nil ->
        key_file = database_path |> Path.dirname() |> Path.join("secret.key")

        case File.read(key_file) do
          {:ok, key} ->
            String.trim(key)

          _ ->
            key = :crypto.strong_rand_bytes(64) |> Base.encode64(padding: false)
            File.write!(key_file, key)
            key
        end

      key ->
        key
    end

  config :pomodoro_app, :dns_cluster_query, nil

  config :pomodoro_app, PomodoroAppWeb.Endpoint,
    url: [host: "localhost"],
    secret_key_base: secret_key_base
end
