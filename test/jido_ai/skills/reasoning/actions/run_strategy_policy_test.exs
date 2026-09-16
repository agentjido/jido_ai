defmodule Jido.AI.Actions.Reasoning.RunStrategyPolicyTest do
  use Jido.AI.Test.CallableReasoningCase, async: false
  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias Jido.AI.Profile
  alias Jido.Action.Error.ExecutionFailureError

  defmodule Probe do
    use Jido.Action, name: "callable_probe", schema: Zoi.object(%{value: Zoi.string()})

    def run(params, context) do
      send(context.observer, {:probe_context, context})
      {:ok, params}
    end
  end

  defmodule Router do
    def route(_request, context) do
      if context.tenant_id == "review-team", do: {:ok, :review}, else: {:error, :wrong_tenant}
    end
  end

  defmodule Deny do
    def check(_, _), do: {:error, :host_policy_denied}
  end

  defmodule InertControl do
    def check(_, _), do: raise("Construction must not execute policy")
  end

  test "Adaptive tools receive only selected caller fields and fresh runtime context", %{jido: jido} do
    profile = tool_profile(%{max_iterations: 2, max_model_calls: 2, max_tool_calls: 1, timeout: 5_000})
    script = [tool_reply(), text_reply("Complete")]

    context = %{
      observer: self(),
      tenant_id: "review-team",
      hidden: "secret",
      jido_ai_events: :parent_events,
      jido_ai_request: :parent_request,
      state: %{parent_secret: true},
      signal: :parent_signal
    }

    assert {{:ok, payload}, requests, selection} =
             call(jido, profile, "Calculate with the probe tool", script, 2, context)

    assert payload.output == "Complete"
    assert selection.strategy == :react
    assert length(requests) == 2
    assert_receive {:probe_context, tool_context}
    assert tool_context.tenant_id == "review-team"
    refute Map.has_key?(tool_context, :hidden)
    refute Map.has_key?(tool_context, :jido_ai_callable_profile)
    refute tool_context[:jido_ai_request] == :parent_request
    refute tool_context[:jido_ai_events] == :parent_events
    refute tool_context[:signal] == :parent_signal
    refute tool_context[:state] == %{parent_secret: true}
  end

  test "explicit model-call and iteration limits bound Adaptive after selection", %{jido: jido} do
    profile = tool_profile(%{max_iterations: 1, max_model_calls: 1, max_tool_calls: 1, timeout: 5_000})

    assert {{:error, %ExecutionFailureError{details: %{reason: payload}}}, [_request], selection} =
             call(jido, profile, "Calculate with the probe tool", [tool_reply()], 1, %{observer: self()})

    assert selection.strategy == :react
    assert payload.strategy == :adaptive
    assert payload.status == :failure
    assert payload.usage.total_tokens == 15
    assert payload.diagnostics.snapshot_done
  end

  test "explicit tool limits reject an oversized batch before tools execute", %{jido: jido} do
    profile = tool_profile(%{max_iterations: 2, max_model_calls: 2, max_tool_calls: 1, timeout: 5_000})

    reply = %{
      reply:
        {:tools,
         [
           %{id: "one", name: "probe", arguments: %{value: "One"}},
           %{id: "two", name: "probe", arguments: %{value: "Two"}}
         ]}
    }

    assert {{:error, %ExecutionFailureError{details: %{reason: payload}}}, [_request], _} =
             call(jido, profile, "Calculate with the probe tool", [reply], 2, %{observer: self()})

    assert payload.status == :failure
    refute_received {:probe_context, _}
  end

  test "explicit ToT node and model-call limits remain effective", %{jido: jido} do
    profile =
      callable_profile(:tree_of_thoughts, %{
        reasoning: %{method: :tree_of_thoughts, options: %{max_nodes: 1}},
        controls: %{max_iterations: 1, max_model_calls: 1, max_tool_calls: 1, timeout: 5_000}
      })

    mock = start_supervised!({MockLLM, script: []})

    assert {:error, payload} =
             RunStrategy.run(%{prompt: "Choose a path"}, %{
               jido: jido,
               jido_ai_callable_profile: profile,
               ai: %{review: %{options: MockLLM.options(mock)}}
             })

    assert payload.output.tree.node_count == 1
    assert payload.output.diagnostics.cause == :max_nodes
    assert payload.output.termination.node_count == 1
    assert %{requests: [], unexpected: []} = MockLLM.report(mock)
    assert Jido.list_agents(jido) == []
  end

  test "Profile model routers keep host context and select a declared role", %{jido: jido} do
    profile =
      callable_profile(:chain_of_thought, %{
        models: %{entries: %{default: MockLLM.model(), review: MockLLM.model("gpt-4o")}, router: %{module: Router}},
        reasoning: %{method: :chain_of_thought, model: :default}
      })

    assert {{:ok, %{output: "Four"}}, [request], nil} =
             call(jido, profile, "Route this", script(:cot), 1, %{tenant_id: "review-team"})

    assert request.body["model"] == "gpt-4o"
  end

  test "input controls reject before model work", %{jido: jido} do
    profile = callable_profile(:chain_of_thought, %{controls: %{input: [Deny], timeout: 1_000}})
    mock = start_supervised!({MockLLM, script: []})

    assert {:error, _} =
             RunStrategy.run(%{prompt: "Denied"}, %{
               jido: jido,
               jido_ai_callable_profile: profile,
               ai: %{review: %{options: MockLLM.options(mock)}}
             })

    assert %{requests: [], unexpected: []} = MockLLM.report(mock)
    assert Jido.list_agents(jido) == []
  end

  test "static tool context cannot contain a callable binding or other reserved policy" do
    for key <- [:jido_ai_callable_profile, "jido_ai_callable_profile", :ai, :state] do
      assert {:error, _} =
               Profile.new(%{
                 id: :review,
                 reasoning: :adaptive,
                 result: %{into: :answer},
                 tool_context: %{key => %{}}
               })
    end
  end

  test "resolved refs and aliases remain inert when a Plugin is constructed" do
    profile =
      Profile.new!(
        %{
          id: :review,
          model: :host_alias,
          reasoning: :chain_of_thought,
          controls: %{input: [%{ref: "guard"}]},
          result: %{into: :answer}
        },
        registries: %{controls: %{"guard" => InertControl}}
      )

    assert profile.controls.input == [InertControl]
    assert profile.models.default.model == :host_alias

    assert {:ok, _} =
             Jido.Agent.new(%{
               name: "inert_callable",
               schema: Zoi.object(%{answer: Zoi.any()}),
               plugins: [{Jido.AI.Plugins.Reasoning.ChainOfThought, [profile: profile]}]
             })
  end

  defp tool_reply, do: %{reply: {:tools, [%{id: "probe-1", name: "probe", arguments: %{value: "Two"}}]}}

  defp tool_profile(controls) do
    callable_profile(:adaptive, %{
      reasoning: %{method: :adaptive, options: %{available_strategies: [:react]}},
      tools: [
        %{
          target: Probe,
          name: "probe",
          forward_context: [
            :observer,
            :tenant_id,
            :jido_ai_callable_profile,
            :jido_ai_request,
            :jido_ai_events,
            :state,
            :signal
          ]
        }
      ],
      controls: controls
    })
  end
end
