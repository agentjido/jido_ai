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
end
