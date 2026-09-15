defmodule Jido.AI.Model.OptionsTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Model.Options
  alias Jido.AI.Reasoning.ReAct.Config

  test "provider options use the selected model without a reasoning config dependency" do
    merged = Options.merge([], %{provider_options: %{"verbosity" => :medium}}, "openai:gpt-4.1")
    assert merged[:provider_options] == [verbosity: :medium]
  end

  test "a request model change selects the new provider option schema" do
    merged =
      Options.merge(
        [max_tokens: 100],
        %{provider_options: %{"reasoning_token_budget" => 8192}},
        "anthropic:claude-sonnet-4-5"
      )

    assert merged[:provider_options] == [reasoning_token_budget: 8192]
    assert merged[:max_tokens] == 100
  end

  test "standalone Config uses the same normalization" do
    model = "openai:gpt-4.1"
    options = %{"max_tokens" => 123, "provider_options" => %{"verbosity" => :medium}}
    config = Config.new(model: model, llm_opts: options)
    assert config.llm.llm_opts == Options.normalize(options, model)
  end

  test "nil overrides preserve the base for any selected provider" do
    base = [max_tokens: 1024]
    assert Options.merge(base, nil, "openai:gpt-4.1") == base
    assert Options.merge(base, nil, "anthropic:claude-sonnet-4-5") == base
  end

  test "HTTP overrides merge without discarding unrelated options" do
    assert Options.merge_http_options([max_tokens: 10, req_http_options: [retry: false, receive_timeout: 10]],
             receive_timeout: 20
           ) == [max_tokens: 10, req_http_options: [retry: false, receive_timeout: 20]]
  end
end
