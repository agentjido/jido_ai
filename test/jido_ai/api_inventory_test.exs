Code.require_file("../../scripts/support/api_inventory.exs", __DIR__)

defmodule Jido.AI.APIInventoryTest do
  use ExUnit.Case, async: true

  test "the declared-source inventory matches every current production file" do
    expected = JidoAI.APIInventory.build() |> Jason.encode!() |> Jason.decode!()
    actual = "docs/v3-spike/api-inventory.json" |> File.read!() |> Jason.decode!()
    assert actual == expected, "Run mix run scripts/api_inventory.exs to reconcile the inventory"
  end

  test "nested modules, guarded clauses, default arities and quoted exports retain their scopes" do
    source = ~S"""
    defmodule Outer do
      @moduledoc false
      defmodule Inner do
        def call(value, opts \\ [])
        def call(value, opts) when is_list(opts), do: {value, opts}
      end
      defmacro __using__(_) do
        quote do
          def generated(value), do: value
        end
      end
      defp hidden, do: :ok
    end
    """

    items = JidoAI.APIInventory.declarations(source)
    assert Enum.any?(items, &match?(%{kind: "defmodule", name: "Outer.Inner"}, &1))
    assert Enum.any?(items, &match?(%{name: "call", module: "Outer.Inner", arities: [1, 2], clause_lines: [4, 5]}, &1))
    assert Enum.any?(items, &match?(%{name: "generated", module: "Outer", quoted: true, arities: [1]}, &1))
    assert Enum.any?(items, &match?(%{name: "moduledoc", status: "hidden"}, &1))
    refute Enum.any?(items, &(Map.get(&1, :name) == "hidden"))
  end

  test "protocol implementations retain a distinct declaration scope" do
    items =
      JidoAI.APIInventory.declarations(
        "defimpl Inspect, for: Example do\n def inspect(value, opts), do: {value, opts}\nend"
      )

    assert [%{kind: "defimpl", source: scope}, %{kind: "def", module: owner, arities: [2]}] = items
    assert scope == owner
    assert scope =~ "Inspect"
    assert scope =~ "Example"
  end

  test "current contract maps link to existing source and evidence" do
    for name <- ["public-api-map.md", "feature-map.md"] do
      path = Path.join("docs/v3-spike", name)

      for [_, target] <- Regex.scan(~r/\[[^\]]*\]\(([^)]+)\)/, File.read!(path)),
          not String.starts_with?(target, ["https:", "http:", "#"]) do
        target = target |> String.split("#", parts: 2) |> hd()
        assert File.exists?(Path.expand(target, Path.dirname(path))), "Broken link in #{path}: #{target}"
      end
    end
  end
end
