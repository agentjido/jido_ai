defmodule Jido.AI.Authoring.FullSpecParityTest do
  use ExUnit.Case, async: true

  defmodule Search do
    use Jido.Action,
      name: "search_cases",
      description: "Search support cases",
      schema: Zoi.object(%{query: Zoi.string()})

    @impl Jido.Action
    def run(params, _context), do: {:ok, params}
  end

  defmodule Instructions do
    use Jido.Action, name: "support_instructions", schema: Zoi.object(%{query: Zoi.string()})

    @impl Jido.Action
    def run(%{query: query}, _context), do: {:ok, %{instructions: "Support: #{query}"}}
  end

  defmodule Repair do
    use Jido.Action, name: "repair_support_answer", schema: Zoi.object(%{})

    @impl Jido.Action
    def run(params, _context), do: {:ok, params}
  end

  defmodule ResolveCase do
    use Jido.Flow, name: "resolve_case"

    flow do
      step("search", action: Search, params: %{query: input(:query)})
      output(result("search"))
    end
  end

  defmodule Router do
    def route(_request, _context), do: {:ok, :answer}
  end

  defmodule Control do
    def check(_value, _context), do: :ok
  end

  defmodule Resource do
  end

  defmodule Catalog do
  end

  defmodule Skill do
  end

  defmodule ChildAgent do
  end

  defmodule FullAgent do
    use Jido.AI.Agent, name: "full_authoring_agent", description: "Full authoring fixture"

    alias Jido.AI.Authoring.FullSpecParityTest.{
      Catalog,
      ChildAgent,
      Control,
      Instructions,
      Repair,
      ResolveCase,
      Resource,
      Router,
      Search,
      Skill
    }

    agent do
      schema(
        Zoi.object(%{
          answer: Zoi.any() |> Zoi.default(nil),
          messages: Zoi.list(Zoi.any()) |> Zoi.default([])
        })
      )

      ai :support do
        instructions Instructions

        models do
          model :answer, :capable,
            temperature: 0.2,
            max_tokens: 2_000,
            timeout: 30_000,
            provider_options: %{seed: 7},
            metadata: %{tier: "primary"}

          model :review, :fast
          router Router, fallback: :answer
        end

        reasoning :react, model: :answer, tool_concurrency: 4

        tools do
          action Search,
            description: "Find cases",
            timeout: 7_000,
            max_retries: 2,
            retry_backoff: 25,
            forward_context: {:only, [:tenant_id]},
            idempotency: :unsafe_once,
            approval: %{policy: :human},
            metadata: %{group: "support"}

          flow ResolveCase, as: :resolve_case
          ash_resource Resource, actions: [:read, :update]

          mcp_tools endpoint: :github,
                    prefix: "github_",
                    tools: [:search_issues],
                    discover: false,
                    required: true,
                    timeout: 10_000

          browser :docs, mode: :read_only, allow: ["https://hexdocs.pm"]

          catalog Catalog,
            prefix: "support_",
            timeout: 1_500,
            max_calls: 12,
            max_parallel_calls: 8,
            require_read_only: true

          skill Skill
          load_path "priv/skills"

          subagent ChildAgent,
            as: :research_case,
            timeout: 30_000,
            forward_context: {:only, [:tenant_id]},
            result: :structured

          handoff ChildAgent,
            as: :billing_specialist,
            target: :auto,
            forward_context: :public
        end

        controls do
          max_iterations 8
          max_model_calls 12
          max_tool_calls 16
          timeout 60_000
          steering true
          idle_timeout 30_000
          tool_heartbeat 5_000
          input Control
          model Control
          operation Control, when: [name: :resolve_case, kind: :flow]
          output Control
        end

        result schema: Zoi.object(%{answer: Zoi.string()}),
               into: :answer,
               max_repairs: 1,
               on_validation_error: :repair,
               repair_action: Repair

        memory history: :messages

        observability do
          emit_telemetry true
          emit_signals true
          emit_llm_deltas false
          redact_tool_args true
        end

        metadata %{owner: "support", version: 1}
      end

      ai :summary do
        instructions "Summarize the case."
        model :fast
        result into: :answer
      end
    end

    routes do
      route "support.ask", ai: :support
      route "support.summary", ai: :summary
    end
  end

  @answer_schema Zoi.object(%{answer: Zoi.string()})

  defp registries do
    %{
      actions: %{
        "instructions" => Instructions,
        "repair" => Repair,
        "search" => Search
      },
      flows: %{"resolve_case" => ResolveCase},
      controls: %{"control" => Control},
      model_routers: %{"router" => Router},
      schemas: %{
        "answer" => @answer_schema,
        "agent_state" => FullAgent.definition().schema
      },
      ash_resources: %{"resource" => Resource},
      catalogs: %{"catalog" => Catalog},
      skills: %{"skill" => Skill},
      agents: %{"child" => ChildAgent}
    }
  end

  test "the complete DSL compiles every authoring section and tool source" do
    profile = FullAgent.ai_profile(:support)

    assert profile.instructions == Instructions
    assert Map.keys(profile.models) |> Enum.sort() == [:answer, :review]
    assert profile.models.answer.generation[:temperature] == 0.2
    assert profile.models.answer.generation[:max_tokens] == 2_000
    assert profile.models.answer.generation[:receive_timeout] == 30_000
    assert profile.model_router == %{module: Router, fallback: :answer}
    assert Enum.map(profile.tools, & &1.name) == ["search_cases", "resolve_case"]

    assert Enum.map(profile.tool_sources, & &1.kind) == [
             :ash_resource,
             :mcp_tools,
             :browser,
             :catalog,
             :skill,
             :load_path,
             :subagent,
             :handoff
           ]

    assert profile.controls.operation == [
             %{module: Control, when: %{"kind" => "flow", "name" => "resolve_case"}}
           ]

    assert Map.take(profile.controls, [:steering, :idle_timeout, :tool_heartbeat]) == %{
             steering: true,
             idle_timeout: 30_000,
             tool_heartbeat: 5_000
           }

    assert profile.memory == %{history: :messages}
    assert profile.result.into == :answer
    assert profile.result.repair_action == Repair
    assert profile.observability.emit_telemetry?
    assert profile.observability.emit_signals?
    refute profile.observability.emit_llm_deltas?
    assert profile.observability.redact_tool_args?
    assert Map.keys(FullAgent.ai_profiles()) |> Enum.sort() == [:summary, :support]
  end

  test "map, keyword builder, and typed struct inputs preserve the complete profile" do
    profile = FullAgent.ai_profile(:support)
    attrs = Map.from_struct(profile)

    assert {:ok, ^profile} = Jido.AI.Profile.new(attrs)
    assert {:ok, ^profile} = Jido.AI.Profile.new(Map.to_list(attrs))
    assert {:ok, ^profile} = Jido.AI.Profile.new(profile)
    assert {:ok, ^profile} = Jido.AI.profile(Map.to_list(attrs))
  end

  test "portable map, JSON, and YAML keep semantic parity for the complete profile" do
    profile = FullAgent.ai_profile(:support)

    for format <- [:map, :json, :yaml] do
      assert {:ok, encoded} = Jido.AI.export(profile, format, registries: registries())
      assert {:ok, imported} = Jido.AI.import(encoded, registries: registries())
      assert imported == profile
    end
  end

  test "portable Agent documents preserve profiles and AI routes" do
    assert {:ok, document} = Jido.AI.export(FullAgent, :map, registries: registries())
    assert document["agent"]["profiles"] |> Map.keys() |> Enum.sort() == ["summary", "support"]

    assert {:ok, imported} = Jido.AI.import(document, registries: registries())
    assert Jido.AI.Agent.profiles(imported) == FullAgent.ai_profiles()

    assert Enum.any?(imported.routes, fn route ->
             route.path == "support.ask" and
               route.target == {Jido.AI.Orchestration.Start, %{profile_id: :support}}
           end)
  end
end
