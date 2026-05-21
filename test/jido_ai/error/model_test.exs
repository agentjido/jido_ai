defmodule Jido.AI.Error.ModelTest do
  use ExUnit.Case, async: true

  alias Jido.Action.Error, as: ActionError
  alias Jido.AI.Error

  test "unknown error formats wrapped payload" do
    assert Error.Unknown.message(%Error.Unknown{error: {:bad_state, %{step: 2}}}) ==
             "Unknown error: {:bad_state, %{step: 2}}"
  end

  describe "api errors" do
    test "rate limit message precedence" do
      assert Error.API.RateLimit.message(%Error.API.RateLimit{message: "Too many requests"}) ==
               "Too many requests"

      assert Error.API.RateLimit.message(%Error.API.RateLimit{retry_after: 30}) ==
               "Rate limit exceeded, retry after 30 seconds"

      assert Error.API.RateLimit.message(%Error.API.RateLimit{}) == "Rate limit exceeded"
    end

    test "auth message fallback" do
      assert Error.API.Auth.message(%Error.API.Auth{message: "Invalid token"}) == "Invalid token"
      assert Error.API.Auth.message(%Error.API.Auth{}) == "Authentication failed"
    end

    test "request message variants" do
      assert Error.API.Request.message(%Error.API.Request{message: "socket closed"}) == "socket closed"
      assert Error.API.Request.message(%Error.API.Request{kind: :timeout}) == "Request timed out"
      assert Error.API.Request.message(%Error.API.Request{kind: :network}) == "Network error"

      assert Error.API.Request.message(%Error.API.Request{kind: :provider, status: 503}) ==
               "Provider error (503)"

      assert Error.API.Request.message(%Error.API.Request{kind: :provider}) == "Provider error"
      assert Error.API.Request.message(%Error.API.Request{}) == "Request failed"
    end
  end

  describe "validation errors" do
    test "invalid message variants" do
      assert Error.Validation.Invalid.message(%Error.Validation.Invalid{message: "prompt required"}) ==
               "prompt required"

      assert Error.Validation.Invalid.message(%Error.Validation.Invalid{field: "prompt"}) ==
               "Invalid field: prompt"

      assert Error.Validation.Invalid.message(%Error.Validation.Invalid{}) == "Validation error"
    end
  end

  describe "runtime envelope normalization" do
    test "passes through ok and error tuples and wraps invalid values" do
      assert Error.normalize_result({:ok, 1}) == {:ok, 1, []}

      assert Error.normalize_result({:error, %{code: :x, message: "boom"}}) ==
               {:error, %{type: :x, message: "boom", details: %{}, retryable?: false}, []}

      assert {:error, envelope, []} = Error.normalize_result(:bad, :invalid_result, "Bad result")
      assert envelope.type == :invalid_result
      assert envelope.retryable? == false
    end

    test "normalizes structs and retryable aliases into the canonical envelope" do
      input = %{code: :timeout, message: "timed out", details: %{timeout_ms: 100}, retryable: true}

      assert Error.normalize(input) == %{
               type: :timeout,
               message: "timed out",
               details: %{timeout_ms: 100},
               retryable?: true
             }
    end

    test "normalizes non-binary messages and preserves transient retry hints" do
      input = %{type: :execution_error, message: :transient_error, details: %{}}

      assert Error.normalize(input) == %{
               type: :execution_error,
               message: "transient_error",
               details: %{},
               retryable?: true
             }
    end

    test "normalizes Jido.Action error structs through Jido.Error.to_map/1" do
      error = ActionError.execution_error("boom", %{step: :list, retry: false})

      assert Error.normalize(error) == %{
               type: :execution_error,
               message: "boom",
               details: %{step: :list, retry: false},
               retryable?: false
             }
    end

    test "normalizes supervisor failures without changing the public envelope shape" do
      assert Error.normalize(
               %{
                 type: :supervisor,
                 message: "Failed to start LLM task",
                 details: %{reason: ":noproc"},
                 retryable?: true
               },
               :llm_error,
               "LLM request failed"
             ) == %{
               type: :supervisor,
               message: "Failed to start LLM task",
               details: %{reason: ":noproc"},
               retryable?: true
             }
    end

    test "normalizes plain exceptions with caller fallback type and details" do
      envelope = Error.normalize(RuntimeError.exception("boom"), :execution_error, "Tool execution failed")

      assert envelope.type == :execution_error
      assert envelope.message == "boom"
      assert envelope.details.message == "boom"
      assert envelope.retryable? == false
    end

    test "normalizes timeout atoms and timeout detail tuples as retryable" do
      assert Error.normalize(:timeout) == %{
               type: :timeout,
               message: "Tool execution timed out",
               details: %{},
               retryable?: true
             }

      assert Error.normalize({:timeout, %{timeout_ms: 50}}) == %{
               type: :timeout,
               message: "Tool execution timed out",
               details: %{timeout_ms: 50},
               retryable?: true
             }
    end

    test "normalizes details into JSON-safe values" do
      envelope =
        Error.normalize(%{
          type: :execution_error,
          message: "boom",
          details: %{
            pid: self(),
            ref: make_ref(),
            tuple: {:error, :bad},
            nested: %{inner: {:ok, :value}}
          }
        })

      assert is_binary(envelope.details.pid)
      assert is_binary(envelope.details.ref)
      assert is_binary(envelope.details.tuple)
      assert is_binary(envelope.details.nested.inner)
      assert Jason.encode!(envelope)
    end

    test "error_envelope/4 sanitizes direct details payloads" do
      envelope =
        Error.error_envelope(:execution_error, "boom", %{
          pid: self(),
          ref: make_ref(),
          tuple: {:error, :bad},
          map_key: %{1 => :one}
        })

      assert is_binary(envelope.details.pid)
      assert is_binary(envelope.details.ref)
      assert is_binary(envelope.details.tuple)
      assert envelope.details.map_key["1"] == :one
      assert Jason.encode!(envelope)
    end

    test "to_map/1 serializes any error as the canonical envelope" do
      assert Error.to_map({:validation, %{field: :query}}) == %{
               type: :validation,
               message: "Tool validation failed",
               details: %{details: %{field: :query}},
               retryable?: false
             }
    end
  end

  describe "retryable?/1" do
    test "uses canonical retryable flags first" do
      assert Error.retryable?(%{type: :execution_error, retryable?: true})
      refute Error.retryable?(%{type: :timeout, retryable?: false})
    end

    test "handles tuple results and conservative fallback types" do
      assert Error.retryable?({:error, %{type: :timeout}, []})
      assert Error.retryable?(:transient)
      assert Error.retryable?(%{type: :execution_error, message: :transient_error, details: %{}})
      refute Error.retryable?({:error, %{type: :execution_error}, []})
      refute Error.retryable?({:ok, :done, []})
    end
  end
end
