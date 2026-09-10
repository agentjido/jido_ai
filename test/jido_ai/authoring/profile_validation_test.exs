defmodule Jido.AI.Authoring.ProfileValidationTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Profile

  defmodule Action do
    use Jido.Action, name: "validation_action", schema: Zoi.object(%{})

    @impl Jido.Action
    def run(params, _context), do: {:ok, params}
  end

  defmodule Control do
    def check(_value, _context), do: :ok
  end

  defmodule InvalidControl do
  end

  defmodule Router do
    def route(_request, _context), do: {:ok, :answer}
  end

  defmodule SelectRouter do
    def select(_request, _context), do: {:ok, :answer}
  end

  defmodule Interceptor do
    def before_tool_call(tool, context), do: {:ok, tool, context}
  end

  defmodule NoCallbacks do
  end

  defp attrs(overrides \\ %{}) do
    Map.merge(%{id: :support, model: :capable, result: %{into: :answer}}, overrides)
  end

  test "minimal profiles resolve package defaults through the shared constructor" do
    assert {:ok, profile} = Profile.new(%{id: :support, result: %{into: :answer}})
    assert map_size(profile.models) == 1
    assert profile.reasoning.method == :react
    assert profile.reasoning.model == :default
    assert profile.tools == []
    assert profile.tool_sources == []
    assert profile.requests.mode == :turn
    assert profile.memory == %{history: nil}
    assert profile.controls.timeout == 60_000
  end

  test "new! and validate use the same Splode validation contract" do
    profile = Profile.new!(%{id: :support, result: %{into: :answer}})

    assert {:ok, ^profile} = Profile.validate(profile)

    assert_raise Jido.AI.Error.Validation.Invalid, fn ->
      Profile.new!(%{id: nil, result: %{into: :answer}})
    end
  end

  test "application model and instruction defaults apply only when the profile omits them" do
    previous = Application.get_env(:jido_ai, :agent_defaults)
    Application.put_env(:jido_ai, :agent_defaults, %{model: :fast, instructions: "Configured"})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:jido_ai, :agent_defaults, previous),
        else: Application.delete_env(:jido_ai, :agent_defaults)
    end)

    assert {:ok, defaulted} = Profile.new(%{id: :support, result: %{into: :answer}})
    assert defaulted.models.default.model == :fast
    assert defaulted.instructions == "Configured"

    assert {:ok, explicit} = Profile.new(attrs(%{model: :capable, instructions: "Explicit"}))
    assert explicit.models.default.model == :capable
    assert explicit.instructions == "Explicit"
  end

  test "model forms and portable enums normalize to one profile" do
    assert {:ok, profile} =
             Profile.new(
               attrs(%{
                 models: %{
                   "answer" => %{
                     "model" => "capable",
                     "temperature" => 0.3,
                     "max_tokens" => 100,
                     "timeout" => 2_000,
                     "provider_options" => %{"seed" => 3}
                   }
                 },
                 reasoning: %{"method" => "react", "model" => "answer"},
                 requests: %{"mode" => "session", "on_busy" => "reject", "steering" => true}
               })
             )

    assert profile.models.answer.model == :capable
    assert profile.models.answer.generation[:temperature] == 0.3
    assert profile.models.answer.provider_options == %{seed: 3}
    assert profile.reasoning.method == :react
    assert profile.requests.mode == :session
  end

  test "method-default control limits resolve from reasoning and repair policy" do
    assert {:ok, profile} =
             Profile.new(
               attrs(%{
                 controls: %{
                   max_iterations: :method_default,
                   max_model_calls: "method_default",
                   max_tool_calls: :method_default
                 },
                 result: %{into: :answer, max_repairs: 2}
               })
             )

    assert {:ok, resolved} = Profile.resolve_controls(profile)
    assert resolved.controls.max_iterations == 10
    assert resolved.controls.max_model_calls == 12
    assert resolved.controls.max_tool_calls == 16
  end

  test "all documented reasoning methods and exact model IDs survive portable authoring" do
    methods = %{
      react: %{},
      chain_of_thought: %{},
      chain_of_draft: %{},
      algorithm_of_thoughts: %{
        "profile" => "long",
        "search_style" => "bfs",
        "examples" => ["worked example"],
        "require_explicit_answer" => false
      },
      tree_of_thoughts: %{"traversal_strategy" => "dfs", "max_nodes" => 9},
      graph_of_thoughts: %{"aggregation_strategy" => "weighted", "max_nodes" => 8},
      trm: %{"max_supervision_steps" => 3, "act_threshold" => 0.75},
      adaptive: %{
        "available_strategies" => ["aot", "tot", "got", "trm"],
        "complexity_thresholds" => %{"simple" => 0.2, "complex" => 0.8},
        "strategy_override" => "aot",
        "method_options" => %{
          "aot" => %{"profile" => "short", "search_style" => "bfs"},
          "tot" => %{"traversal_strategy" => "bfs", "max_nodes" => 7},
          "got" => %{"aggregation_strategy" => "voting", "max_nodes" => 6},
          "trm" => %{"max_supervision_steps" => 2, "act_threshold" => 0.8}
        }
      }
    }

    for {method, options} <- methods do
      input =
        attrs(%{
          models: %{answer: "openai:gpt-4o-mini"},
          reasoning: %{method: Atom.to_string(method), model: "answer", options: options}
        })

      assert {:ok, profile} = Profile.new(input)
      assert profile.reasoning.method == method
      assert profile.models.answer.model == "openai:gpt-4o-mini"

      assert {:ok, json} = Jido.AI.export(profile, :json)
      assert {:ok, imported} = Jido.AI.import(json)
      assert imported == profile
    end
  end

  test "constructor rejects malformed profile, model, instruction, and option inputs" do
    invalid = [
      {attrs(%{unknown: true}), []},
      {:not_a_profile, []},
      {attrs(), :bad_options},
      {attrs(), [unknown: true]},
      {attrs(%{instructions: "  "}), []},
      {attrs(%{instructions: String}), []},
      {attrs(%{models: %{}}), []},
      {attrs(%{models: %{answer: "invalid"}, reasoning: %{model: :answer}}), []},
      {attrs(%{models: %{answer: %{model: :capable, temperature: :hot}}, reasoning: %{model: :answer}}), []},
      {attrs(%{models: %{answer: %{model: :capable, provider_options: ["bad"]}}, reasoning: %{model: :answer}}), []},
      {attrs(%{reasoning: :unknown}), []},
      {attrs(%{reasoning: %{method: :react, model: :missing}}), []}
    ]

    for {input, options} <- invalid do
      assert {:error, %Jido.AI.Error.Validation.Invalid{}} = Profile.new(input, options)
    end
  end

  test "constructor rejects invalid controls, requests, memory, and results" do
    invalid = [
      attrs(%{controls: %{timeout: 0}}),
      attrs(%{controls: %{max_iterations: 10_001}}),
      attrs(%{controls: %{input: [InvalidControl]}}),
      attrs(%{controls: %{input: [42]}}),
      attrs(%{controls: %{operation: [%{module: Control, when: ["bad"]}]}}),
      attrs(%{requests: %{mode: :turn, steering: true}}),
      attrs(%{requests: %{mode: :turn, idle_timeout: 10}}),
      attrs(%{requests: %{max_requests: 0}}),
      attrs(%{memory: %{history: "unregistered_profile_field"}}),
      attrs(%{result: nil}),
      attrs(%{result: %{into: :answer, max_repairs: 4}}),
      attrs(%{result: %{into: :answer, repair_action: String}})
    ]

    for input <- invalid do
      assert {:error, %Jido.AI.Error.Validation.Invalid{}} = Profile.new(input)
    end
  end

  test "constructor rejects invalid effect policy fields and values" do
    invalid = [
      attrs(%{effect_policy: %{mode: :deny_al}}),
      attrs(%{effect_policy: %{unknown: true}}),
      attrs(%{effect_policy: %{allow: ["Elixir.Jido.AI.UnknownEffect"]}}),
      attrs(%{effect_policy: %{constraints: %{unknown: %{}}}}),
      attrs(%{effect_policy: %{constraints: %{schedule: %{max_delay_ms: -1}}}}),
      attrs(%{effect_policy: %{constraints: %{emit: %{unknown: []}}}}),
      attrs(%{effect_policy: %{constraints: %{emit: %{allowed_signal_types: [" "]}}}}),
      attrs(%{effect_policy: %{constraints: %{emit: %{allowed_dispatches: [true]}}}})
    ]

    for input <- invalid do
      assert {:error, %Jido.AI.Error.Validation.Invalid{}} = Profile.new(input)
    end
  end

  test "constructor keeps valid effect policy settings" do
    assert {:ok, profile} =
             Profile.new(
               attrs(%{
                 effect_policy: %{
                   mode: "allow_list",
                   allow: [Jido.AI.Effects.State, Jido.Agent.StateOp.SetState],
                   constraints: %{
                     emit: %{allowed_signal_prefixes: ["ai."]},
                     schedule: %{}
                   }
                 }
               })
             )

    assert profile.effect_policy.mode == :allow_list

    assert profile.effect_policy.allow ==
             Enum.sort([Jido.AI.Effects.State, Jido.Agent.StateOp.SetState])

    assert profile.effect_policy.constraints.schedule == %{}
  end

  test "constructor enforces reasoning feature combinations" do
    assert {:error, _} = Profile.new(attrs(%{reasoning: :chain_of_thought, tools: [Action]}))

    assert {:error, _} =
             Profile.new(
               attrs(%{
                 reasoning: :tree_of_thoughts,
                 result: %{into: :answer, schema: Zoi.object(%{answer: Zoi.string()})}
               })
             )

    assert {:error, _} =
             Profile.new(
               attrs(%{
                 reasoning: :adaptive,
                 requests: %{mode: :session, steering: true}
               })
             )
  end

  test "portable references resolve without arbitrary module lookup" do
    registries = %{
      actions: %{"action" => Action},
      controls: %{"control" => Control},
      model_routers: %{"router" => Router},
      schemas: %{"answer" => Zoi.object(%{answer: Zoi.string()})}
    }

    input = %{
      "id" => "support",
      "instructions" => %{"action" => "action"},
      "models" => %{
        "entries" => %{"answer" => "capable"},
        "router" => %{"ref" => "router", "fallback" => "answer"}
      },
      "tools" => [%{"kind" => "action", "ref" => "action"}],
      "controls" => %{"input" => [%{"ref" => "control"}]},
      "result" => %{
        "schema" => %{"ref" => "answer"},
        "into" => "answer",
        "repair_action" => %{"ref" => "action"}
      }
    }

    assert {:ok, profile} = Profile.new(input, registries: registries)
    assert profile.instructions == Action
    assert profile.model_router == %{module: Router, fallback: :answer}
    assert hd(profile.tools).target == Action
    assert profile.controls.input == [Control]
    assert profile.result.repair_action == Action

    assert {:error, _} =
             put_in(input, ["tools"], [%{"kind" => "action", "ref" => "missing"}])
             |> Profile.new(registries: registries)
  end

  test "keyword profiles, sources, fields, and portable data use their public edge contracts" do
    assert {:ok, profile} =
             Profile.new(id: :support, model: :capable, result: [into: :answer])

    assert profile.id == :support
    assert {:error, _} = Profile.new(id: :support, id: :duplicate)

    assert {:ok, {sourced, [:primary]}} =
             Profile.source(%{
               id: :support,
               models: %{default: :capable},
               result: %{into: :answer},
               routes: [:primary]
             })

    assert sourced.id == :support
    assert {:ok, {^profile, []}} = Profile.source(profile)
    assert {:error, _} = Profile.source(%{id: :support, result: %{into: :answer}, unknown: true})

    assert {:ok, %{id: :support}} = Profile.fields(%{"id" => :support}, [:id], "profile")
    assert {:error, _} = Profile.fields(%{:id => :support, "id" => :other}, [:id], "profile")
    assert {:error, _} = Profile.fields(:invalid, [:id], "profile")

    assert Profile.portable_data(%{mode: :react, nested: [:cot, %{flag: true}]}) == %{
             "mode" => "react",
             "nested" => ["cot", %{"flag" => true}]
           }
  end

  test "constructor rejects additional malformed container and identifier forms" do
    invalid = [
      attrs(%{id: nil}),
      attrs(%{id: "not_a_registered_atom"}),
      attrs(%{models: :invalid}),
      attrs(%{tools: :invalid}),
      attrs(%{tool_sources: :invalid}),
      attrs(%{reasoning: [:not_keyword]}),
      attrs(%{reasoning: %{method: 1}}),
      attrs(%{reasoning: %{method: "not_supported"}}),
      attrs(%{reasoning: %{tool_concurrency: 0}}),
      attrs(%{reasoning: %{unknown: true}}),
      attrs(%{models: %{first: :fast, second: :capable}, reasoning: %{method: :react}}),
      attrs(%{models: %{first: :fast}, reasoning: %{method: :react, model: "missing"}}),
      attrs(%{requests: :invalid}),
      attrs(%{requests: %{mode: :invalid}}),
      attrs(%{requests: %{on_busy: :queue}}),
      attrs(%{requests: %{streaming: :yes}}),
      attrs(%{memory: :invalid}),
      attrs(%{observability: :invalid}),
      attrs(%{observability: %{emit_signals: :yes}}),
      attrs(%{tool_interceptor: "bad"}),
      attrs(%{tool_interceptor: NoCallbacks}),
      attrs(%{result: %{into: :answer, repair_action: "bad"}})
    ]

    for input <- invalid do
      assert {:error, %Jido.AI.Error.Validation.Invalid{}} = Profile.new(input)
    end
  end

  test "model options validate generation, provider, metadata, and router variants" do
    invalid = [
      attrs(%{models: %{answer: %{model: :capable, generation: %{temperature: 0.2}}}}),
      attrs(%{models: %{answer: %{model: :capable, max_tokens: 0}}}),
      attrs(%{models: %{answer: %{model: :capable, timeout: 0}}}),
      attrs(%{models: %{answer: %{model: :capable, metadata: URI.parse("https://example.com")}}}),
      attrs(%{models: %{answer: %{model: :capable, provider_options: %{"not_registered" => 1}}}}),
      attrs(%{models: %{entries: %{answer: :capable}, router: %{module: NoCallbacks}}}),
      attrs(%{models: %{entries: %{answer: :capable}, router: %{module: Router, fallback: :missing}}}),
      attrs(%{model_router: :invalid})
    ]

    for input <- invalid do
      assert {:error, %Jido.AI.Error.Validation.Invalid{}} = Profile.new(input)
    end

    assert {:ok, profile} =
             Profile.new(
               attrs(%{
                 models: %{
                   entries: %{
                     answer: %{
                       model: :capable,
                       generation: [top_p: 0.8],
                       provider_options: [seed: 7],
                       metadata: %{tier: :primary}
                     }
                   },
                   router: %{module: SelectRouter, fallback: :answer}
                 },
                 reasoning: %{model: :answer}
               })
             )

    assert profile.model_router == %{module: SelectRouter, fallback: :answer}
    assert profile.models.answer.generation == [top_p: 0.8, seed: 7]
    assert profile.models.answer.metadata == %{"tier" => "primary"}
  end

  test "output, observability, control, and effect-policy edge forms normalize" do
    schema = Zoi.object(%{answer: Zoi.string()})
    assert {:ok, nil} = Profile.output_contract(%{schema: nil})
    assert {:ok, nil} = Profile.output_contract(%{into: :answer})
    assert {:ok, contract} = Profile.output_contract(%{schema: schema, max_repairs: 1})
    assert contract.retries == 1

    assert {:ok, profile} =
             Profile.new(
               attrs(%{
                 tool_interceptor: Interceptor,
                 controls: [input: [[module: Control, when: [kind: :request]]]],
                 observability: %{
                   emit_telemetry: true,
                   emit_llm_deltas: false,
                   emit_signals: true,
                   redact_tool_args: false
                 },
                 effect_policy: %{
                   mode: :allow_list,
                   allow: MapSet.new([Jido.AI.Effects.State]),
                   deny: [],
                   constraints: %{
                     emit: %{allowed_dispatches: [:pid, "logger"]},
                     schedule: %{max_delay_ms: 0}
                   }
                 }
               })
             )

    assert profile.controls.input == [%{module: Control, when: %{"kind" => "request"}}]
    assert profile.observability.emit_telemetry?
    assert profile.observability.emit_signals?
    assert profile.effect_policy.allow == [Jido.AI.Effects.State]

    for effect_policy <- [
          :invalid,
          %{allow: :invalid},
          %{allow: [:not_a_module]},
          %{allow: [123]},
          %{constraints: :invalid},
          %{constraints: %{emit: :invalid}},
          %{constraints: %{schedule: :invalid}},
          %{constraints: %{emit: %{allowed_signal_types: :invalid}}},
          %{constraints: %{emit: %{allowed_dispatches: :invalid}}}
        ] do
      assert {:error, %Jido.AI.Error.Validation.Invalid{}} =
               Profile.new(attrs(%{effect_policy: effect_policy}))
    end
  end

  test "method-specific output and adaptive control limits report unsupported combinations" do
    schema = Zoi.object(%{answer: Zoi.string()})

    for method <- [:graph_of_thoughts, :trm] do
      assert {:error, %Jido.AI.Error.Validation.Invalid{}} =
               Profile.new(attrs(%{reasoning: method, result: %{into: :answer, schema: schema}}))
    end

    assert {:ok, adaptive} = Profile.new(attrs(%{reasoning: :adaptive}))
    assert {:error, %Jido.AI.Error.Validation.Invalid{}} = Profile.resolve_controls(adaptive)
  end
end
