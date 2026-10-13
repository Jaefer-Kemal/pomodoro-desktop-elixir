import Config

# Use the pre-built asset manifest for production
config :pomodoro_app, PomodoroAppWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

# Reduce log noise in production
config :logger, level: :info
