defmodule Jido.AI.Live.ToolRoundTest do
  use Jido.AI.Test.LiveCase, async: false

  alias JidoAI.Examples.ToolFlow.Agent, as: ToolAgent

  defmodule FetchCode do
    use Jido.Action,
      name: "fetch_code",
      description: "Fetch the private code required by the redeem_code tool",
      schema: Zoi.object(%{label: Zoi.string()})

    @impl Jido.Action
    def run(%{label: "alpha"}, context) do
      Elixir.Agent.update(context.audit, &[{:fetch, "alpha"} | &1])
      {:ok, %{code: "violet-731"}}
    end
  end

  defmodule RedeemCode do
    use Jido.Action,
      name: "redeem_code",
      description: "Redeem the private code returned by the fetch_code tool",
      schema: Zoi.object(%{code: Zoi.string()})

    @impl Jido.Action
    def run(%{code: "violet-731"}, context) do
      Elixir.Agent.update(context.audit, &[{:redeem, "violet-731"} | &1])
      {:ok, %{receipt: "receipt-omega"}}
    end

    def run(%{code: code}, context) do
      Elixir.Agent.update(context.audit, &[{:rejected, code} | &1])
      {:error, :invalid_code}
    end
  end

  defmodule MultiStepAgent do
    use Jido.AI.Agent, name: "live_multi_step_tool_agent"

    alias Jido.AI.Live.ToolRoundTest.{FetchCode, RedeemCode}

    ai do
      model :fast

      instructions """
      For a receipt request, first call fetch_code with label alpha. Then call
      redeem_code with the exact code returned by fetch_code. Include the
      receipt from redeem_code in the final answer. Do not invent either value.
      """

      tools do
        action FetchCode
        action RedeemCode
      end

      controls do
        timeout 30_000
        max_iterations 4
        max_model_calls 5
        max_tool_calls 4
      end
    end
  end

  test "a real model completes one Action tool round" do
    {:ok, counter} = Elixir.Agent.start_link(fn -> 0 end)
    input = "Call the multiply tool with left 6 and right 7. Use its result in your answer."
    options = live_options(max_tokens: 64, jido_context: %{counter: counter})

    {result, _trace} =
      capture_live(ToolAgent, input, "action_tool_round", options, fn ->
        Jido.AI.generate(ToolAgent, input, options)
      end)

    assert {:ok, text} = result
    assert String.contains?(text, "42")
    assert Elixir.Agent.get(counter, & &1) >= 1
  end

  test "a real model completes two dependent Action tool rounds" do
    {:ok, audit} = Elixir.Agent.start_link(fn -> [] end)
    input = "Get and redeem the code for label alpha. Return the receipt."
    options = live_options(max_tokens: 96, jido_context: %{audit: audit})

    {result, _trace} =
      capture_live(MultiStepAgent, input, "dependent_tool_rounds", options, fn ->
        Jido.AI.generate(MultiStepAgent, input, options)
      end)

    assert {:ok, text} = result
    assert String.contains?(text, "receipt-omega")

    events = audit |> Elixir.Agent.get(& &1) |> Enum.reverse()
    fetch_index = Enum.find_index(events, &(&1 == {:fetch, "alpha"}))
    redeem_index = Enum.find_index(events, &(&1 == {:redeem, "violet-731"}))

    assert is_integer(fetch_index)
    assert is_integer(redeem_index)
    assert fetch_index < redeem_index
  end
end
