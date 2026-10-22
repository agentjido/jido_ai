defmodule Jido.AI.Reasoning.ReAct.ConfigEdgeTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct.Config

  test "exposes its schema and normalizes uncommon option forms" do
    assert %Zoi.Types.Struct{} = Config.schema()

    default = Config.new(:invalid)
    assert default.max_iterations > 0

    config =
      Config.new(%{
        model: :fast,
        temperature: 1,
        llm_timeout_ms: 25,
        llm_opts: %{12 => :ignored, "provider_options" => 17}
      })

    assert config.llm.temperature == 1.0
    assert config.llm.llm_opts == [provider_options: 17]
    assert Config.llm_opts(config)[:receive_timeout] == 25
    assert Config.tool_heartbeat_ms(%{config | tool_heartbeat_ms: :invalid}) == 0
  end

  test "rejects each invalid request transformer form" do
    assert_raise ArgumentError, ~r/module Jido.AI.NotLoadedTransformer is not loaded/, fn ->
      Config.new(model: :fast, request_transformer: Jido.AI.NotLoadedTransformer)
    end

    assert_raise ArgumentError, ~r/expected transform_request\/4 callback/, fn ->
      Config.new(model: :fast, request_transformer: String)
    end

    assert_raise ArgumentError, ~r/expected a module implementing transform_request\/4/, fn ->
      Config.new(model: :fast, request_transformer: "invalid")
    end
  end

  test "drops invalid option keys and handles non-list stored options" do
    config = Config.new(model: :fast)

    assert Jido.AI.Model.Options.merge([], %{12 => :ignored, provider_options: %{12 => :ignored}}, config.model) == [
             provider_options: []
           ]

    assert Jido.AI.Model.Options.merge([max_tokens: 10], :invalid, config.model) == [max_tokens: 10]

    malformed = %{config | llm: %{config.llm | llm_opts: :invalid}}
    assert Config.llm_opts(malformed)[:max_tokens] == config.llm.max_tokens
  end
end
