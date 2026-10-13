defmodule PomodoroAppWeb.MenuBar do
  @moduledoc """
  This module defines the System Tray (Taskbar) icon and the right-click menu
  for our native window.
  """

  # We use Desktop.Menu to give us macros for building native menus
  use Desktop.Menu

  @impl true
  def render(assigns) do
    # --------------------------------------------------------
    # Building the Native Menu
    # --------------------------------------------------------
    # The ~H is a sigil provided by Phoenix/Desktop to build 
    # the native menu structure, exactly like HTML in LiveView.
    ~H"""
    <menu>
      <!-- This item allows us to restore the window from the tray -->
      <item name="show" onclick="show_window">Show Pomodoro</item>

      <hr />

      <!-- This item completely exits the application -->
      <item name="quit" onclick="quit_app">Quit</item>
    </menu>
    """
  end

  # --------------------------------------------------------
  # Required Callbacks
  # --------------------------------------------------------

  @impl true
  def mount(menu) do
    # Mount is called when the menu starts. We return {:ok, menu}
    {:ok, menu}
  end

  # --------------------------------------------------------
  # Handling Menu Clicks
  # --------------------------------------------------------
  # When the user clicks a menu item with an `onclick` attribute, 
  # Desktop.Menu calls `handle_event/2`.

  @impl true
  def handle_event(<<"show_window">>, menu) do
    # When "show_window" is clicked, we find our main window and show it
    Desktop.Window.show(PomodoroAppWindow)
    {:noreply, menu}
  end

  @impl true
  def handle_event(<<"quit_app">>, menu) do
    # When "quit_app" is clicked, we cleanly stop the Erlang VM
    System.stop()
    {:noreply, menu}
  end

  @impl true
  def handle_event(_unknown, menu) do
    {:noreply, menu}
  end

  @impl true
  def handle_info(_msg, menu) do
    {:noreply, menu}
  end
end
