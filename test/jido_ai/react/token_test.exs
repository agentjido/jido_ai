defmodule Jido.AI.ReAct.TokenTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ReAct.{Config, State, Token}

  test "issues and decodes checkpoint tokens" do
    config =
      Config.new(%{
        model: :capable,
        tools: %{},
        token_secret: "secret-a"
      })

    state = State.new("hello", config.system_prompt, request_id: "req_1", run_id: "run_1")

    token = Token.issue(state, config)
    assert is_binary(token)
    assert String.starts_with?(token, "rt1.")

    assert {:ok, payload} = Token.decode(token, config)
    assert payload.v == 1
    assert payload.iss == "jido_ai/react"
    assert payload.run_id == "run_1"
    assert payload.request_id == "req_1"
  end

  test "rejects tampered tokens" do
    config = Config.new(%{model: :capable, tools: %{}, token_secret: "secret-a"})
    state = State.new("hello", nil, request_id: "req_2", run_id: "run_2")
    token = Token.issue(state, config)

    tampered = token <> "x"
    assert {:error, :invalid_token_signature} = Token.decode(tampered, config)
  end

  test "rejects config fingerprint mismatches" do
    config_a = Config.new(%{model: :capable, tools: %{}, token_secret: "secret-a"})
    config_b = Config.new(%{model: :fast, tools: %{}, token_secret: "secret-a"})

    state = State.new("hello", nil, request_id: "req_3", run_id: "run_3")
    token = Token.issue(state, config_a)

    assert {:error, :token_config_mismatch} = Token.decode(token, config_b)
  end

  test "rejects expired tokens" do
    config = Config.new(%{model: :capable, tools: %{}, token_secret: "secret-a", token_ttl_ms: 1})
    state = State.new("hello", nil, request_id: "req_4", run_id: "run_4")
    token = Token.issue(state, config)

    Process.sleep(10)

    assert {:error, :token_expired} = Token.decode(token, config)
  end
end
