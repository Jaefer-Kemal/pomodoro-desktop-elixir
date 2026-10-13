defmodule PomodoroAppWeb.PageControllerTest do
  use PomodoroAppWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Pomodoro"
  end
end
