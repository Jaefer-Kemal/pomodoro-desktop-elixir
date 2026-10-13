defmodule PomodoroApp.AnalyticsTest do
  use PomodoroApp.DataCase

  alias PomodoroApp.Analytics

  describe "sessions" do
    alias PomodoroApp.Analytics.Session

    import PomodoroApp.AnalyticsFixtures

    @invalid_attrs %{phase: nil, duration: nil}

    test "list_sessions/0 returns all sessions" do
      session = session_fixture()
      assert Analytics.list_sessions() == [session]
    end

    test "get_session!/1 returns the session with given id" do
      session = session_fixture()
      assert Analytics.get_session!(session.id) == session
    end

    test "create_session/1 with valid data creates a session" do
      valid_attrs = %{phase: "some phase", duration: 42}

      assert {:ok, %Session{} = session} = Analytics.create_session(valid_attrs)
      assert session.phase == "some phase"
      assert session.duration == 42
    end

    test "create_session/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Analytics.create_session(@invalid_attrs)
    end

    test "update_session/2 with valid data updates the session" do
      session = session_fixture()
      update_attrs = %{phase: "some updated phase", duration: 43}

      assert {:ok, %Session{} = session} = Analytics.update_session(session, update_attrs)
      assert session.phase == "some updated phase"
      assert session.duration == 43
    end

    test "update_session/2 with invalid data returns error changeset" do
      session = session_fixture()
      assert {:error, %Ecto.Changeset{}} = Analytics.update_session(session, @invalid_attrs)
      assert session == Analytics.get_session!(session.id)
    end

    test "delete_session/1 deletes the session" do
      session = session_fixture()
      assert {:ok, %Session{}} = Analytics.delete_session(session)
      assert_raise Ecto.NoResultsError, fn -> Analytics.get_session!(session.id) end
    end

    test "change_session/1 returns a session changeset" do
      session = session_fixture()
      assert %Ecto.Changeset{} = Analytics.change_session(session)
    end
  end
end
