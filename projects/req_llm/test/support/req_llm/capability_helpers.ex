defmodule ReqLLM.Test.CapabilityHelpers do
  @moduledoc """
  Reusable test helpers and macros for capability testing.

  Provides common patterns used across capability test files to reduce duplication
  and improve maintainability.
  """

  @doc """
  Macro that generates behavior compliance tests for capability modules.

  ## Examples

      defmodule MyCapabilityTest do
        use ReqLLM.Test.CapabilityCase
        import ReqLLM.Test.CapabilityHelpers
        
        behaviour_tests(MyCapability)
      end
  """
  defmacro behaviour_tests(capability_module) do
    quote do
      describe "behavior compliance" do
        test "implements ReqLLM.Capability.Adapter behavior" do
          for {fun, arity} <- [id: 0, advertised?: 1, verify: 2] do
            assert function_exported?(unquote(capability_module), fun, arity),
                   "Expected #{unquote(capability_module)} to export #{fun}/#{arity}"
          end
        end

        test "id/0 returns correct capability atom" do
          id = unquote(capability_module).id()
          assert is_atom(id), "Expected id/0 to return an atom"

          # Convert module name to expected capability name
          expected_capability =
            unquote(capability_module)
            |> Module.split()
            |> List.last()
            |> Macro.underscore()
            |> String.to_atom()

          assert id == expected_capability,
                 "Expected #{inspect(expected_capability)}, got #{inspect(id)}"
        end
      end
    end
  end

  @doc """
  Macro that generates model_id format tests across providers.

  ## Examples

      model_id_tests(MyCapability, :generate_text!)
  """
  defmacro model_id_tests(capability_module, api_function) do
    quote do
      describe "model_id format" do
        @provider_cases [
          {"openai", "gpt-4", "openai:gpt-4"},
          {"anthropic", "claude-3-sonnet", "anthropic:claude-3-sonnet"},
          {"fake_provider", "test-model-v2", "fake_provider:test-model-v2"}
        ]

        test "generates correct provider:model format" do
          for {provider, model_name, expected_id} <- @provider_cases do
            model = test_model(provider, model_name)

            Mimic.stub(ReqLLM, unquote(api_function), fn _model, _message, _opts ->
              case unquote(capability_module) do
                ReqLLM.Capability.ToolCalling ->
                  {:ok, unquote(__MODULE__).stub_tool_calling_response()}

                _ ->
                  unquote(__MODULE__).stub_success_response(
                    unquote(api_function),
                    "Test response"
                  )
              end
            end)

            result = unquote(capability_module).verify(model, [])

            assert {:ok, response_data} = result,
                   "Expected success for #{provider}:#{model_name}"

            assert response_data.model_id == expected_id,
                   "Expected model_id '#{expected_id}', got '#{response_data.model_id}'"
          end
        end
      end
    end
  end

  @doc """
  Macro that generates timeout configuration tests.

  ## Examples

      timeout_tests(MyCapability, :generate_text!)
  """
  defmacro timeout_tests(capability_module, api_function) do
    quote do
      test "passes timeout configuration correctly" do
        model = test_model("openai", "gpt-4")
        custom_timeout = 15_000

        Mimic.stub(ReqLLM, unquote(api_function), fn _model, _message, opts ->
          provider_opts = Keyword.get(opts, :provider_options, %{})

          assert provider_opts.timeout == custom_timeout,
                 "Expected timeout #{custom_timeout}, got #{inspect(provider_opts.timeout)}"

          assert provider_opts.receive_timeout == custom_timeout,
                 "Expected receive_timeout #{custom_timeout}, got #{inspect(provider_opts.receive_timeout)}"

          case unquote(capability_module) do
            ReqLLM.Capability.ToolCalling ->
              {:ok, unquote(__MODULE__).stub_tool_calling_response()}

            _ ->
              unquote(__MODULE__).stub_success_response(unquote(api_function), "Test response")
          end
        end)

        result = unquote(capability_module).verify(model, timeout: custom_timeout)
        assert {:ok, _response_data} = result
      end
    end
  end

  @doc """
  Macro that generates error handling tests with multiple scenarios.

  ## Examples

      error_handling_tests(MyCapability, [
        {"empty response", {:ok, %{content: ""}}, ~r/Empty response/},
        {"api error", {:error, "Network timeout"}, ~r/Network timeout/}
      ])
  """
  defmacro error_handling_tests(capability_module, error_scenarios) do
    quote do
      describe "error handling" do
        test "handles various error cases appropriately" do
          for {description, mock_response, expected_error_pattern} <- unquote(error_scenarios) do
            model = test_model("openai", "gpt-4")

            api_function =
              case unquote(capability_module) do
                ReqLLM.Capability.StreamText -> :stream_text!
                _ -> :generate_text
              end

            Mimic.stub(ReqLLM, api_function, fn _model, _message, _opts ->
              mock_response
            end)

            result = unquote(capability_module).verify(model, [])

            assert {:error, error_message} = result,
                   "Expected error for case '#{description}'"

            assert error_message =~ expected_error_pattern,
                   "Error message '#{error_message}' should match pattern #{inspect(expected_error_pattern)} for case '#{description}'"
          end
        end
      end
    end
  end

  # Helper functions for stubs

  @doc false
  def __dummy_response__, do: {:ok, "Dummy test response"}

  @doc """
  Creates a stub that always returns a successful response with the given content.
  """
  def stub_success_response(api_function, content \\ "Test response") do
    case api_function do
      :stream_text! ->
        chunks = [ReqLLM.StreamChunk.text(content)]
        stream = Stream.map(chunks, & &1)
        {:ok, stream}

      :generate_text ->
        {:ok, %Req.Response{status: 200, body: content}}

      :generate_text! ->
        {:ok, content}
    end
  end

  @doc """
  Creates a stub for tool calling capability that returns proper tool calls.
  """
  def stub_tool_calling_response() do
    tool_calls = [%{name: "test_tool", arguments: %{param: "value"}}]

    %Req.Response{
      status: 200,
      body: %{tool_calls: tool_calls}
    }
  end

  @doc """
  Helper to create mock HTTP response for testing.
  """
  def create_mock_response(body_content, opts \\ []) do
    %Req.Response{
      status: Keyword.get(opts, :status, 200),
      headers: Keyword.get(opts, :headers, %{"content-type" => ["application/json"]}),
      body: body_content
    }
  end
end
