defmodule PomodoroAppWeb.PageController do
  use PomodoroAppWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
