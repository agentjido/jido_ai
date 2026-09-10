defmodule Jido.AITest do
  use ExUnit.Case, async: false

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI
  alias Jido.AI.Context
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct

  doctest Jido.AI

  defp create_react_agent(opts) do
    %Jido.Agent{
      id: "jido-ai-test-agent",
      name: "jido-ai-test-agent",
      state: %{},
      schema: Zoi.object(%{}),
      module: Jido.Agent
    }
    |> then(fn agent ->
      {agent, []} = ReAct.init(agent, %{strategy_opts: Keyword.merge([tools: []], opts)})
      agent
    end)
  end

  defp with_model_aliases(aliases, fun) do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, aliases)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:jido_ai, :model_aliases)
      else
        Application.put_env(:jido_ai, :model_aliases, original)
      end
    end)

    fun.()
  end

  describe "model_aliases/0 and resolve_model/1" do
    test "loads package configuration defaults" do
      assert is_binary(AI.resolve_model(:fast))
    end

    test "merges configured aliases over defaults" do
      with_model_aliases(%{fast: "openai:gpt-4o-mini", custom: "openai:gpt-4.1"}, fn ->
        assert AI.resolve_model(:fast) == "openai:gpt-4o-mini"
        assert AI.resolve_model(:custom) == "openai:gpt-4.1"
      end)
    end

    test "configured aliases can resolve to inline model specs" do
      inline_model = %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"}

      with_model_aliases(%{capable: inline_model}, fn ->
        assert AI.resolve_model(:capable) == inline_model
      end)
    end
  end

  describe "struct-level strategy helpers" do
    @describetag :legacy_v2

    test "get_strategy_context prefers run_context while a request is active" do
      agent = create_react_agent(system_prompt: "Prompt")

      base_context =
        Context.new(system_prompt: "Prompt")
        |> Context.append_user("old")

      run_context = Context.append_user(base_context, "new")

      agent =
        agent
        |> StratState.get(%{})
        |> Map.put(:context, base_context)
        |> Map.put(:run_context, run_context)
        |> then(&StratState.put(agent, &1))

      assert AI.get_strategy_context(agent) == run_context
    end

    test "update_context_entries only updates run_context while active" do
      agent = create_react_agent(system_prompt: "Prompt")

      base_context =
        Context.new(system_prompt: "Prompt")
        |> Context.append_user("old")

      run_context = Context.append_user(base_context, "new")
      active_entries = [hd(run_context.entries)]

      agent =
        agent
        |> StratState.get(%{})
        |> Map.put(:context, base_context)
        |> Map.put(:run_context, run_context)
        |> then(&StratState.put(agent, &1))

      agent = AI.update_context_entries(agent, active_entries)
      state = StratState.get(agent, %{})

      assert state.run_context.entries == active_entries
      assert state.context.entries == base_context.entries
    end

    test "update_context_entries updates materialized context when idle" do
      agent = create_react_agent(system_prompt: "Prompt")

      context =
        Context.new(system_prompt: "Prompt")
        |> Context.append_user("old")
        |> Context.append_assistant("reply")

      kept_entries = [hd(context.entries)]

      agent =
        agent
        |> StratState.get(%{})
        |> Map.put(:context, context)
        |> Map.put(:run_context, nil)
        |> then(&StratState.put(agent, &1))

      agent = AI.update_context_entries(agent, kept_entries)
      state = StratState.get(agent, %{})

      assert state.context.entries == kept_entries
      assert state.run_context == nil
    end
  end
end
