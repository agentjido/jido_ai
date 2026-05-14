defmodule Jido.AI.Skill.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skill.Diagnostics

  describe "new/0" do
    test "creates empty diagnostics" do
      diag = Diagnostics.new()

      assert diag.warnings == []
      assert diag.errors == []
      assert diag.timestamp
    end
  end

  describe "add_warning/2" do
    test "appends a warning to diagnostics" do
      diag = Diagnostics.new()
      warning = Diagnostics.Warning.new(:name_mismatch, "Name does not match directory")

      diag = Diagnostics.add_warning(diag, warning)

      assert length(diag.warnings) == 1
      assert hd(diag.warnings).type == :name_mismatch
    end

    test "accumulates multiple warnings in order" do
      diag = Diagnostics.new()
      w1 = Diagnostics.Warning.new(:name_mismatch, "A")
      w2 = Diagnostics.Warning.new(:truncated, "B")

      diag =
        diag
        |> Diagnostics.add_warning(w1)
        |> Diagnostics.add_warning(w2)

      assert length(diag.warnings) == 2
      assert Enum.at(diag.warnings, 0).type == :truncated
      assert Enum.at(diag.warnings, 1).type == :name_mismatch
    end
  end

  describe "add_error/2" do
    test "appends an error to diagnostics" do
      diag = Diagnostics.new()
      diag = Diagnostics.add_error(diag, %{type: :missing_required, field: :name})

      assert length(diag.errors) == 1
      assert hd(diag.errors).field == :name
    end
  end

  describe "has_warnings?/1" do
    test "returns false for empty diagnostics" do
      refute Diagnostics.has_warnings?(Diagnostics.new())
    end

    test "returns true after adding a warning" do
      diag =
        Diagnostics.new()
        |> Diagnostics.add_warning(Diagnostics.Warning.new(:test, "msg"))

      assert Diagnostics.has_warnings?(diag)
    end
  end

  describe "has_errors?/1" do
    test "returns false for empty diagnostics" do
      refute Diagnostics.has_errors?(Diagnostics.new())
    end

    test "returns true after adding an error" do
      diag =
        Diagnostics.new()
        |> Diagnostics.add_error(%{type: :fail})

      assert Diagnostics.has_errors?(diag)
    end
  end

  describe "warning_count/1 and error_count/1" do
    test "returns correct counts" do
      diag =
        Diagnostics.new()
        |> Diagnostics.add_warning(Diagnostics.Warning.new(:a, "1"))
        |> Diagnostics.add_warning(Diagnostics.Warning.new(:b, "2"))
        |> Diagnostics.add_error(%{type: :x})

      assert Diagnostics.warning_count(diag) == 2
      assert Diagnostics.error_count(diag) == 1
    end
  end

  describe "to_map/1" do
    test "serializes diagnostics to a map" do
      diag =
        Diagnostics.new()
        |> Diagnostics.add_warning(Diagnostics.Warning.new(:name_mismatch, "Names differ"))

      map = Diagnostics.to_map(diag)

      assert map.warning_count == 1
      assert map.error_count == 0
      assert length(map.warnings) == 1
      assert hd(map.warnings).type == :name_mismatch
      assert is_binary(hd(map.warnings).timestamp)
    end

    test "returns nil for nil input" do
      assert Diagnostics.to_map(nil) == nil
    end
  end

  describe "format/1" do
    test "formats empty diagnostics" do
      assert Diagnostics.format(Diagnostics.new()) == "No diagnostics"
    end

    test "formats diagnostics with warnings" do
      diag =
        Diagnostics.new()
        |> Diagnostics.add_warning(Diagnostics.Warning.new(:test, "message"))

      formatted = Diagnostics.format(diag)

      assert formatted =~ "Warnings (1)"
      assert formatted =~ "test: message"
    end
  end

  describe "Warning.new/3" do
    test "creates warning with defaults" do
      w = Diagnostics.Warning.new(:type_a, "msg")

      assert w.type == :type_a
      assert w.message == "msg"
      assert w.severity == :low
      assert w.timestamp
    end

    test "creates warning with custom severity" do
      w = Diagnostics.Warning.new(:type_b, "msg", severity: :high)

      assert w.severity == :high
    end
  end

  describe "Warning.to_map/1" do
    test "serializes warning" do
      w = Diagnostics.Warning.new(:x, "y")
      map = Diagnostics.Warning.to_map(w)

      assert map.type == :x
      assert map.message == "y"
      assert is_binary(map.timestamp)
    end
  end

  describe "Warning.format/1" do
    test "formats warning string" do
      w = Diagnostics.Warning.new(:name_mismatch, "Names differ")

      assert Diagnostics.Warning.format(w) == "[low] name_mismatch: Names differ"
    end
  end
end
