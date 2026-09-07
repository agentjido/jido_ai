defmodule Jido.AI.Authoring.RuntimeBoundaryTest do
  use ExUnit.Case, async: true

  defmodule StringKeyInstructions do
    use Jido.Action, name: "string_key_instructions", schema: Zoi.object(%{})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{"instructions" => "From a string key"}}
  end

  defmodule RawInstructions do
    use Jido.Action, name: "raw_instructions", schema: Zoi.object(%{})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, Jido.Action.Output.raw("From raw output")}
  end

  defmodule BlankInstructions do
    use Jido.Action, name: "blank_instructions", schema: Zoi.object(%{})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{instructions: "  "}}
  end

  defmodule InvalidInstructions do
    use Jido.Action, name: "invalid_instructions", schema: Zoi.object(%{})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{other: "value"}}
  end

  defmodule SelectRouter do
    def select(%{query: "review"}, _context), do: {:ok, "review"}
    def select(%{query: "unknown"}, _context), do: {:ok, :missing}
    def select(%{query: "invalid"}, _context), do: :invalid
    def select(_request, _context), do: {:error, :no_match}
  end

  defmodule RaisingRouter do
    def route(_request, _context), do: raise("router failed")
  end

  defp profile(attrs \\ []) do
    base = [id: :support, model: :capable, result: [into: :answer]]
    {:ok, profile} = Jido.AI.profile(Keyword.merge(base, attrs))
    profile
  end

  test "instruction sources keep fixed values and accept all Action result forms" do
    deadline = System.monotonic_time(:millisecond) + 1_000

    for instructions <- [nil, "Fixed"] do
      source = profile(instructions: instructions)
      assert {:ok, ^source} = Jido.AI.Instructions.resolve(source, %{}, %{}, deadline)
    end

    assert {:ok, resolved} =
             profile(instructions: StringKeyInstructions)
             |> Jido.AI.Instructions.resolve(%{}, %{}, deadline)

    assert resolved.instructions == "From a string key"

    assert {:ok, resolved} =
             profile(instructions: RawInstructions)
             |> Jido.AI.Instructions.resolve(%{}, %{}, deadline)

    assert resolved.instructions == "From raw output"
  end

  test "instruction resolution rejects invalid output and an expired deadline" do
    deadline = System.monotonic_time(:millisecond) + 1_000

    for action <- [BlankInstructions, InvalidInstructions] do
      assert {:error, %Jido.AI.Error.Validation.Invalid{field: "instructions"}} =
               profile(instructions: action)
               |> Jido.AI.Instructions.resolve(%{}, %{}, deadline)
    end

    assert {:error, %Jido.AI.Error.Validation.Invalid{field: "instructions"}} =
             profile(instructions: RawInstructions)
             |> Jido.AI.Instructions.resolve(%{}, %{}, System.monotonic_time(:millisecond) - 1)
  end

  test "model routers support select/2, string roles, fallback, and no router" do
    source = profile()
    assert {:ok, ^source} = Jido.AI.ModelRouter.select(source, %{query: "review"}, %{})

    routed =
      profile(
        models: %{answer: :capable, review: :fast},
        reasoning: [model: :answer],
        model_router: %{module: SelectRouter, fallback: :answer}
      )

    assert {:ok, selected} = Jido.AI.ModelRouter.select(routed, %{query: "review"}, %{})
    assert selected.reasoning.model == :review

    assert {:ok, fallback} = Jido.AI.ModelRouter.select(routed, %{query: "other"}, %{})
    assert fallback.reasoning.model == :answer
  end

  test "model routers reject bad results and use fallback after an exception" do
    without_fallback =
      profile(
        models: %{answer: :capable, review: :fast},
        reasoning: [model: :answer],
        model_router: %{module: SelectRouter}
      )

    for query <- ["unknown", "invalid"] do
      assert {:error, _} = Jido.AI.ModelRouter.select(without_fallback, %{query: query}, %{})
    end

    assert {:error, :no_match} = Jido.AI.ModelRouter.select(without_fallback, %{query: "other"}, %{})

    with_fallback =
      profile(model_router: %{module: RaisingRouter, fallback: :default})

    assert {:ok, fallback} = Jido.AI.ModelRouter.select(with_fallback, %{query: "any"}, %{})
    assert fallback.reasoning.model == :default

    without_fallback = profile(model_router: %{module: RaisingRouter})

    assert {:error, %RuntimeError{message: "router failed"}} =
             Jido.AI.ModelRouter.select(without_fallback, %{query: "any"}, %{})
  end
end
