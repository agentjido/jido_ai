defmodule Jido.AI.Authoring.AgentDSLTest do
  use ExUnit.Case, async: true

  defmodule Search do
    use Jido.Action,
      name: "search_cases",
      description: "Search support cases",
      schema: Zoi.object(%{query: Zoi.string()})

    @impl Jido.Action
    def run(%{query: query}, _context), do: {:ok, %{query: query}}
  end

  defmodule Instructions do
    use Jido.Action, name: "support_instructions"

    @impl Jido.Action
    def run(%{query: query}, context),
      do: {:ok, %{instructions: "#{context.tenant}: #{query}"}}
  end

  defmodule Router do
    def route(%{query: "fast"}, _context), do: {:ok, :fast}
    def route(_request, _context), do: {:error, :no_match}
  end

  defmodule Control do
    def check(value, context) do
      send(context.test_pid, {:checked, value.name})
      :ok
    end
  end

  defmodule CanonicalAgent do
    use Jido.AI.Agent, name: "canonical_support"
    alias Jido.AI.Authoring.AgentDSLTest.{Control, Router, Search}

    agent do
      schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

      ai :support do
        instructions "Help the operator."

        models do
          model :answer, :capable, temperature: 0.2
          model :fast, :fast
          router Router, fallback: :answer
        end

        reasoning :react, model: :answer

        tools do
          action Search

          action :case_link, %{case_id: case_id},
            description: "Build a case link",
            schema: Zoi.object(%{case_id: Zoi.string()}),
            output_schema: Zoi.object(%{url: Zoi.string()}),
            context: context do
            {:ok, %{url: "#{context.base_url}/#{case_id}"}}
          end
        end

        controls do
          operation Control, when: [name: :search_cases]
        end

        result into: :answer
      end
    end

    routes do
      route "support.ask", ai: :support
    end
  end

  defmodule ExtensionAgent do
    use Jido.Agent, name: "extension_support", extensions: [Jido.AI.DSL]

    agent do
      schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

      ai :support do
        instructions "Help the operator."
        model :capable
        result into: :answer
      end
    end

    routes do
      route "support.ask", ai: :support
    end
  end

  test "the preferred DSL lowers to normal Agent profiles and routes" do
    profile = CanonicalAgent.ai_profile(:support)

    assert %Jido.AI.Profile{} = profile
    assert profile.reasoning.method == :react
    assert profile.reasoning.model == :answer
    assert profile.models.answer.generation[:temperature] == 0.2
    assert Enum.map(profile.tools, & &1.name) == ["search_cases", "case_link"]
    assert [%{module: Control, when: %{"name" => "search_cases"}}] = profile.controls.operation

    assert Enum.any?(CanonicalAgent.routes(), fn route ->
             route.path == "support.ask" and
               route.target == {Jido.AI.Runtime.Run, %{profile_id: :support}}
           end)
  end

  test "the explicit core extension has the same canonical defaults" do
    profile = ExtensionAgent.ai_profile(:support)

    assert profile.models.default.model == :capable

    assert profile.reasoning == %{
             method: :react,
             model: :default,
             tool_concurrency: 4,
             effect_policy: %{}
           }
  end

  test "canonical use rejects extension module attributes with a compile error" do
    module = Module.concat(__MODULE__, "AttributeExtensions#{System.unique_integer([:positive])}")

    assert_raise CompileError, ~r/extensions must be an inline compile-time list/, fn ->
      Code.compile_string("""
      defmodule #{inspect(module)} do
        @extensions []
        use Jido.AI.Agent, name: "attribute_extensions_agent", extensions: @extensions
      end
      """)
    end
  end

  test "the builder and dynamic instruction Action use the canonical constructor" do
    assert {:ok, profile} =
             Jido.AI.profile(
               id: :support,
               instructions: Instructions,
               model: :capable,
               result: [into: :answer]
             )

    deadline = System.monotonic_time(:millisecond) + 1_000

    assert {:ok, resolved} =
             Jido.AI.Instructions.resolve(
               profile,
               %{query: "refund"},
               %{tenant: "acme"},
               deadline
             )

    assert resolved.instructions == "acme: refund"
  end

  test "model routers select declared roles and use the declared fallback" do
    profile = CanonicalAgent.ai_profile(:support)

    assert {:ok, routed} = Jido.AI.ModelRouter.select(profile, %{query: "fast"}, %{})
    assert routed.reasoning.model == :fast

    assert {:ok, fallback} = Jido.AI.ModelRouter.select(profile, %{query: "other"}, %{})
    assert fallback.reasoning.model == :answer
  end

  test "conditional operation controls use stable tool metadata" do
    profile = CanonicalAgent.ai_profile(:support)
    deadline = System.monotonic_time(:millisecond) + 1_000
    search = Enum.find(profile.tools, &(&1.name == "search_cases"))
    inline = Enum.find(profile.tools, &(&1.name == "case_link"))

    assert :ok =
             Jido.AI.Control.check(
               profile,
               :operation,
               %{name: inline.name, tool: inline},
               %{test_pid: self()},
               deadline
             )

    refute_received {:checked, _}

    assert :ok =
             Jido.AI.Control.check(
               profile,
               :operation,
               %{name: search.name, tool: search},
               %{test_pid: self()},
               deadline
             )

    assert_receive {:checked, "search_cases"}
  end

  test "compiled inline Actions use registry references in portable formats" do
    profile = CanonicalAgent.ai_profile(:support)
    inline = Enum.find(profile.tools, &(&1.name == "case_link"))

    registries = %{
      actions: %{"search" => Search, "case_link" => inline.target},
      controls: %{"control" => Control},
      model_routers: %{"router" => Router},
      schemas: %{}
    }

    assert {:ok, json} = Jido.AI.export(profile, :json, registries: registries)
    assert {:ok, imported} = Jido.AI.import(json, registries: registries)
    assert imported == profile
  end
end
