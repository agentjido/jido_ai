defmodule Jido.AI.Authoring.PortableTest do
  use ExUnit.Case, async: true

  defmodule Tool do
    use Jido.Action, name: "portable_tool", schema: Zoi.object(%{})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{ok: true}}
  end

  defmodule Instructions do
    use Jido.Action, name: "portable_instructions"

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{instructions: "Portable"}}
  end

  defmodule Control do
    def check(_value, _context), do: :ok
  end

  defmodule Router do
    def route(_request, _context), do: {:ok, :answer}
  end

  defmodule MultiAgent do
    use Jido.AI.Agent, name: "portable_multi_agent"

    agent do
      schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

      ai :first do
        model :capable
        result into: :answer
      end

      ai :second do
        model :fast
        result into: :answer
      end
    end

    routes do
      route "portable.first", ai: :first
      route "portable.second", ai: :second
    end
  end

  @registries %{
    actions: %{"instructions" => Instructions, "tool" => Tool},
    controls: %{"control" => Control},
    model_routers: %{"router" => Router},
    schemas: %{}
  }

  test "JSON and YAML imports normalize through Profile.new/2" do
    assert {:ok, profile} =
             Jido.AI.profile(
               id: :support,
               instructions: Instructions,
               models: %{
                 answer: %{
                   model: :capable,
                   temperature: 0.1,
                   max_tokens: 500,
                   timeout: 2_000
                 }
               },
               model_router: %{module: Router, fallback: :answer},
               tools: [Tool],
               controls: %{operation: [%{module: Control, when: [name: :portable_tool]}]},
               result: [into: :answer]
             )

    for format <- [:json, :yaml] do
      assert {:ok, encoded} = Jido.AI.export(profile, format, registries: @registries)
      assert {:ok, imported} = Jido.AI.import(encoded, registries: @registries)

      assert imported.id == profile.id
      assert imported.instructions == profile.instructions
      assert imported.models == profile.models
      assert imported.model_router == profile.model_router
      assert imported.tools == profile.tools
      assert imported.controls == profile.controls
      assert imported.result == profile.result
    end
  end

  test "unknown references and future versions fail without creating atoms" do
    unknown = "unknown_profile_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    document = %{
      "version" => 1,
      "profile" => %{
        "id" => unknown,
        "instructions" => %{"action" => "missing"},
        "result" => %{"into" => "answer"}
      }
    }

    assert {:error, _} = Jido.AI.import(document, registries: @registries)
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    assert {:error, _} = Jido.AI.import(%{"version" => 2, "profile" => %{}})
  end

  test "inspection redacts context and provider options and preflight makes no provider call" do
    assert {:ok, profile} =
             Jido.AI.profile(
               id: :support,
               instructions: "Help",
               models: %{answer: %{model: :capable, provider_options: %{api_key: "secret"}}},
               tool_context: %{credential: "secret"},
               result: [into: :answer]
             )

    assert {:ok, %{support: view}} = Jido.AI.inspect(profile)
    refute Map.has_key?(view, :tool_context)
    assert view.models.answer.provider_options == :redacted

    assert {:ok, plan} = Jido.AI.preflight(profile, %{query: "hello"}, profile: :support)
    assert is_binary(plan.model)
    assert plan.instructions == "Help"
  end

  test "public portable APIs return structured errors for invalid sources and documents" do
    assert {:error, _} = Jido.AI.inspect(:not_an_agent)
    assert {:error, _} = Jido.AI.inspect(%{})
    assert {:error, _} = Jido.AI.export(%{}, :json)
    assert {:error, _} = Jido.AI.export(%{}, :xml)
    assert {:error, _} = Jido.AI.import(:not_a_document)
    assert {:error, _} = Jido.AI.import("not: [valid: yaml")
    assert {:error, _} = Jido.AI.import(%{"version" => 1})

    assert {:ok, profile} =
             Jido.AI.profile(id: :support, instructions: Instructions, model: :capable, result: [into: :answer])

    assert {:error, _} = Jido.AI.export(profile, :json)
    assert {:error, _} = Jido.AI.preflight(profile, "hello", profile: :missing)
  end

  test "preflight requires one selected profile when an Agent declares several" do
    assert {:error, _} =
             Jido.AI.preflight(
               MultiAgent,
               %{query: "hello"}
             )
  end
end
