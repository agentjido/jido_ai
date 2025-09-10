defmodule ReqLLM.Test.Fixtures do
  @moduledoc """
  Common test fixtures and result helpers for ReqLLM testing.

  Provides standardized fixtures for testing capabilities, models, and responses
  without requiring network calls or actual AI model interactions.
  """

  @doc """
  Creates a successful test result with standard structure.

  ## Examples

      iex> result = ReqLLM.Test.Fixtures.passed_result("test_capability")
      iex> assert result.status == :passed
      iex> assert result.capability == :test_capability

  """
  @spec passed_result(atom() | String.t(), map()) :: ReqLLM.Capability.Result.t()
  def passed_result(capability, metadata \\ %{}) do
    %ReqLLM.Capability.Result{
      model: "test:fixture-model",
      capability: normalize_capability(capability),
      status: :passed,
      latency_ms: Enum.random(10..50),
      details: Map.merge(%{test: "success"}, metadata)
    }
  end

  @doc """
  Creates a failed test result with standard error structure.

  ## Examples

      iex> result = ReqLLM.Test.Fixtures.failed_result("test_capability", "test failure")
      iex> assert result.status == :failed
      iex> assert result.error == "test failure"

  """
  @spec failed_result(atom() | String.t(), String.t(), map()) :: ReqLLM.Capability.Result.t()
  def failed_result(capability, error_message \\ "test failure", metadata \\ %{}) do
    %ReqLLM.Capability.Result{
      model: "test:fixture-model",
      capability: normalize_capability(capability),
      status: :failed,
      latency_ms: Enum.random(5..25),
      details: Map.merge(%{error: error_message}, metadata)
    }
  end

  @doc """
  Creates a mixed set of test results for testing result aggregation.

  ## Examples

      iex> results = ReqLLM.Test.Fixtures.mixed_results(3, 2)
      iex> assert length(results) == 5
      iex> passed = Enum.count(results, &(&1.status == :passed))
      iex> failed = Enum.count(results, &(&1.status == :failed))
      iex> assert passed == 3
      iex> assert failed == 2

  """
  @spec mixed_results(non_neg_integer(), non_neg_integer()) :: [ReqLLM.Capability.Result.t()]
  def mixed_results(passed_count \\ 2, failed_count \\ 1) do
    passed =
      1..passed_count
      |> Enum.map(fn i -> passed_result("capability_#{i}") end)

    failed =
      1..failed_count
      |> Enum.map(fn i -> failed_result("failing_capability_#{i}") end)

    Enum.shuffle(passed ++ failed)
  end

  @doc """
  Creates a standard test model with configurable capabilities.

  ## Examples

      iex> model = ReqLLM.Test.Fixtures.test_model("openai", "gpt-4")
      iex> assert model.provider == :openai
      iex> assert model.model == "gpt-4"

  """
  @spec test_model(String.t() | atom(), String.t(), keyword()) :: ReqLLM.Model.t()
  def test_model(provider, model, opts \\ []) do
    capabilities =
      Keyword.get(opts, :capabilities, %{
        reasoning?: false,
        tool_call?: true,
        supports_temperature?: true
      })

    ReqLLM.Model.new(
      normalize_provider(provider),
      model,
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens, 1000),
      capabilities: capabilities,
      limit: %{
        context: Keyword.get(opts, :context_length, 8192),
        output: Keyword.get(opts, :max_tokens, 1000)
      },
      cost: %{input: 0.03, output: 0.06},
      modalities: %{input: [:text], output: [:text]}
    )
  end

  @doc """
  Creates a mock HTTP response for testing provider interactions.

  ## Examples

      iex> response = ReqLLM.Test.Fixtures.mock_http_response(%{content: "Hello"})
      iex> assert response.status == 200
      iex> assert response.body.content == "Hello"

  """
  @spec mock_http_response(map(), keyword()) :: Req.Response.t()
  def mock_http_response(body_content, opts \\ []) do
    %Req.Response{
      status: Keyword.get(opts, :status, 200),
      headers: Keyword.get(opts, :headers, %{"content-type" => ["application/json"]}),
      body: body_content
    }
  end

  @doc """
  Creates a standard chat completion response fixture.

  ## Examples

      iex> response = ReqLLM.Test.Fixtures.chat_completion_response("Hello, world!")
      iex> assert response.body.choices |> List.first() |> get_in(["message", "content"]) == "Hello, world!"

  """
  @spec chat_completion_response(String.t(), keyword()) :: Req.Response.t()
  def chat_completion_response(content, opts \\ []) do
    body = %{
      "id" => "chatcmpl-test123",
      "object" => "chat.completion",
      "created" => System.system_time(:second),
      "model" => Keyword.get(opts, :model, "gpt-4"),
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => content
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => Keyword.get(opts, :prompt_tokens, 10),
        "completion_tokens" => Keyword.get(opts, :completion_tokens, 20),
        "total_tokens" => Keyword.get(opts, :total_tokens, 30)
      }
    }

    mock_http_response(body, opts)
  end

  @doc """
  Creates an embedding response fixture for testing embed capabilities.

  ## Examples

      iex> response = ReqLLM.Test.Fixtures.embedding_response()
      iex> embedding = response.body.data |> List.first() |> Map.get("embedding")
      iex> assert length(embedding) == 1536

  """
  @spec embedding_response(keyword()) :: Req.Response.t()
  def embedding_response(opts \\ []) do
    dimensions = Keyword.get(opts, :dimensions, 1536)

    body = %{
      "object" => "list",
      "data" => [
        %{
          "object" => "embedding",
          "index" => 0,
          "embedding" => 1..dimensions |> Enum.map(fn _ -> :rand.uniform() * 2 - 1 end)
        }
      ],
      "model" => Keyword.get(opts, :model, "text-embedding-ada-002"),
      "usage" => %{
        "prompt_tokens" => Keyword.get(opts, :prompt_tokens, 5),
        "total_tokens" => Keyword.get(opts, :total_tokens, 5)
      }
    }

    mock_http_response(body, opts)
  end

  # Helper functions

  defp normalize_capability(capability) when is_atom(capability), do: capability
  defp normalize_capability(capability) when is_binary(capability), do: String.to_atom(capability)

  defp normalize_provider(provider) when is_atom(provider), do: provider
  defp normalize_provider(provider) when is_binary(provider), do: String.to_atom(provider)
end
