defmodule Sparq.PatternMatchingTest do
  use ExUnit.Case

  alias Sparq.Core

  test "bind tuple pattern" do
    ast = [
      {:bind, [], [{:tuple, [], [:x, :y]}, [1, 2], :let]},
      {:var, [], :x},
      {:var, [], :y}
    ]

    assert {:ok, 2, _ctx} = Core.execute(ast)
    # Last expression is :y => 2
  end

  test "bind list pattern" do
    ast = [
      {:bind, [], [[:a, :b, :c], [10, 20, 30], :let]},
      {:var, [], :c}
    ]

    assert {:ok, 30, _ctx} = Core.execute(ast)
  end

  test "mismatch pattern raises error" do
    ast = [
      {:bind, [], [{:tuple, [:x, :y]}, [1, 2], :let]}
    ]

    assert {:error, error, _} = Core.execute(ast)
    assert error.type == :match_error
  end

  test "re-binding let variable" do
    ast = [
      {:bind, [], [:x, 1, :let]},
      {:bind, [], [:x, 2, :let]},
      {:var, [], :x}
    ]

    assert {:ok, 2, _ctx} = Core.execute(ast)
  end

  test "cannot re-declare const in same scope" do
    ast = [
      {:bind, [], [:x, 42, :const]},
      {:bind, [], [:x, 99, :const]}
    ]

    assert {:error, err, _} = Core.execute(ast)
    assert err.type == :binding_error
  end
end
