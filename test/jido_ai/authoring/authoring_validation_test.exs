defmodule Jido.AI.Authoring.AuthoringValidationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{Authoring, Profile}

  defmodule RoutedAgent do
    use Jido.AI.Agent, name: "authoring_routed_agent"

    agent do
      schema Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)})

      ai :support do
        model :capable

        requests do
          mode :session
        end

        result into: :answer
      end
    end

    routes do
      route "support.ask", ai: :support, defaults: %{channel: "web"}
    end
  end

  defp profile(overrides \\ %{}) do
    attrs = Map.merge(%{id: :support, model: :capable, result: %{into: :answer}}, overrides)
    {:ok, profile} = Profile.new(attrs)
    profile
  end

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "authoring_validation",
        schema: Zoi.object(%{answer: Zoi.any() |> Zoi.default(nil)}),
        routes: []
      },
      overrides
    )
  end

  test "request binding and method inspection use normal Agent routes" do
    agent = RoutedAgent.definition()
    signal = Jido.Signal.new!("support.ask", %{query: "help"}, source: "/test")

    assert Authoring.request_binding(agent, signal) == %{
             id: :support,
             mode: :session,
             input: %{channel: "web", profile_id: :support, query: "help"}
           }

    assert Authoring.request_method(agent, signal) == :react
    assert Authoring.request_binding(agent, Jido.Signal.new!("unknown", %{}, source: "/test")) == nil
    assert Authoring.request_binding(%{}, signal) == nil
    assert Authoring.request_method(%{}, signal) == :unknown
  end

  test "lower/2 validates neutral definitions, profile IDs, state fields, and routes" do
    support = profile()
    duplicate = %{support | metadata: %{"duplicate" => true}}

    assert {:error, _} = Authoring.lower(attrs(), [support, duplicate])

    assert {:error, _} =
             Authoring.lower(
               attrs(%{schema: Zoi.object(%{other: Zoi.any()})}),
               [support]
             )

    history = profile(%{memory: %{history: :answer}})
    assert {:error, _} = Authoring.lower(attrs(), [history])

    assert {:error, _} =
             Authoring.lower(
               attrs(%{routes: [{"unknown.ai", Authoring.ai(:missing), []}]}),
               [support]
             )

    assert {:error, _} =
             Authoring.lower(
               attrs(%{
                 routes: [
                   {"support.ask", Authoring.ai(:support), []},
                   {"support.ask", Authoring.ai(:support), []}
                 ]
               }),
               [support]
             )
  end

  test "lower/2 rejects initialized Agents and non-field schemas" do
    assert {:ok, initialized} = Jido.Agent.instantiate(RoutedAgent, [])
    assert {:error, _} = Authoring.lower(initialized, [profile()])

    assert {:error, _} =
             Authoring.lower(
               attrs(%{schema: Zoi.any()}),
               [profile()]
             )
  end

  test "reasoning_flow/1 builds an executable normal Flow" do
    assert {:ok, flow} = Authoring.reasoning_flow(profile())
    assert %Jido.Flow{name: "ai_support"} = flow
    assert {:ok, ^flow} = Jido.Flow.validate_executable(flow)
  end
end
