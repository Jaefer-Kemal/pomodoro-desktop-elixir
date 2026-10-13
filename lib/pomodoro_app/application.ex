defmodule PomodoroApp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PomodoroAppWeb.Telemetry,
      PomodoroApp.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:pomodoro_app, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:pomodoro_app, :dns_cluster_query) || :ignore},

      # --------------------------------------------------------
      # Music Catalog (scans music_pomodoro/ folder)
      # --------------------------------------------------------
      PomodoroApp.Music,

      # --------------------------------------------------------
      # Our Pomodoro Timer (GenServer)
      # --------------------------------------------------------
      # We add our custom Timer process here so it boots up exactly
      # when the application starts, constantly running in the background.
      PomodoroApp.Timer,

      # --------------------------------------------------------
      # Phoenix PubSub (Publish/Subscribe)
      # --------------------------------------------------------
      # This allows different parts of our app to talk to each other.
      # For example, our Timer (GenServer) will broadcast "tick" 
      # events here, and our UI will subscribe to listen for them.
      {Phoenix.PubSub, name: PomodoroApp.PubSub},

      # --------------------------------------------------------
      # The Phoenix Web Server
      # --------------------------------------------------------
      # This starts the actual local web server that serves our UI.
      PomodoroAppWeb.Endpoint,

      # --------------------------------------------------------
      # The Native Desktop Window
      # --------------------------------------------------------
      # We start this AFTER the endpoint, because the window needs 
      # to load the local URL that the endpoint provides.
      {Desktop.Window,
       [
         app: :pomodoro_app,
         id: PomodoroAppWindow,
         title: "Pomodoro App",
         # Setting a window size suitable for executive dashboard with responsive collapse to compact widget
         size: {860, 680},
         min_size: {400, 620},
         icon: "static/images/pomodoro.png",
         taskbar_icon: "static/images/pomodoro.png",

         # wxNO_BORDER (2097152) + wxCLIP_CHILDREN (4194304) = 6291456
         style: 6_291_456,

         # We instruct the window to load our local Phoenix server URL
         url: &PomodoroAppWeb.Endpoint.url/0,

         # System Tray Menu: this creates a taskbar icon and allows 
         # the app to run in the background when you click X
         icon_menu: PomodoroAppWeb.MenuBar
       ]}
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PomodoroApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PomodoroAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
