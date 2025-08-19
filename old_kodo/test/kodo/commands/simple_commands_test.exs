defmodule Kodo.Commands.SimpleCommandsTest do
  use ExUnit.Case, async: true

  alias Kodo.Commands.{Kill, Bg, Fg}

  describe "Kill command" do
    test "implements Kodo.Ports.Command behaviour" do
      behaviours = Kill.__info__(:attributes)[:behaviour] || []
      assert Kodo.Ports.Command in behaviours
    end

    test "has required callback functions" do
      assert Kill.name() == "kill"
      assert is_binary(Kill.description())
      assert is_binary(Kill.usage())
      assert Kill.meta() == [:builtin]
      assert function_exported?(Kill, :execute, 2)
    end

    test "handles invalid job ID" do
      context = %{session_pid: self()}
      assert {:error, _} = Kill.execute(["abc"], context)
    end

    test "handles missing arguments" do
      context = %{session_pid: self()}
      assert {:error, _} = Kill.execute([], context)
    end
  end

  describe "Bg command" do
    test "implements Kodo.Ports.Command behaviour" do
      behaviours = Bg.__info__(:attributes)[:behaviour] || []
      assert Kodo.Ports.Command in behaviours
    end

    test "has required callback functions" do
      assert Bg.name() == "bg"
      assert is_binary(Bg.description())
      assert is_binary(Bg.usage())
      assert Bg.meta() == [:builtin]
      assert function_exported?(Bg, :execute, 2)
    end

    test "handles invalid job ID" do
      context = %{session_pid: self()}
      assert {:error, _} = Bg.execute(["abc"], context)
    end
  end

  describe "Fg command" do
    test "implements Kodo.Ports.Command behaviour" do
      behaviours = Fg.__info__(:attributes)[:behaviour] || []
      assert Kodo.Ports.Command in behaviours
    end

    test "has required callback functions" do
      assert Fg.name() == "fg"
      assert is_binary(Fg.description())
      assert is_binary(Fg.usage())
      assert Fg.meta() == [:builtin]
      assert function_exported?(Fg, :execute, 2)
    end

    test "handles invalid job ID" do
      context = %{session_pid: self()}
      assert {:error, _} = Fg.execute(["abc"], context)
    end
  end
end
