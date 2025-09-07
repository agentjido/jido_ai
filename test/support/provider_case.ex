defmodule ReqLLM.ProviderCase do
  @moduledoc """
  Test case template for provider adapters.

  Generates standard tests for provider compliance while allowing customization.
  Uses Req.Test for deterministic HTTP stubbing.

  ## Usage

      defmodule ReqLLM.Providers.AnthropicTest do
        use ReqLLM.ProviderCase, module: ReqLLM.Providers.Anthropic
        
        # Optional: skip standard tests
        # @skip [:generate_text_error_path]
        
        # Add provider-specific tests
        test "anthropic specific behavior" do
          # ...
        end
      end

  """

  use ExUnit.CaseTemplate
  import Req.Test
  import ReqLLM.Test.Fixture

  using opts do
    quote do
      import Req.Test
      import ReqLLM.Test.Fixture

      alias ReqLLM.{Model, Error}

      @mod unquote(opts[:module] || raise("module: provider module required"))

      setup do
        # Start Req.Test for this test process
        :ok
      end

      describe "spec/0" do
        test "returns correct id and base_url" do
          spec = @mod.spec()
          assert is_atom(spec.id)
          assert is_binary(spec.base_url)
          assert is_map(spec.models)
        end
      end

      describe "build_request/3" do
        test "returns {:ok, %Req.Request{}}" do
          spec = @mod.spec()
          default_model = ReqLLM.Provider.Utils.default_model(spec)
          messages = [%ReqLLM.Message{role: :user, content: "Hello"}]

          assert {:ok, %Req.Request{method: :post} = req} =
                   @mod.build_request(messages, [], model: default_model)

          assert String.starts_with?(to_string(req.url), spec.base_url)
          # Request should have JSON body or body content
          assert req.body != nil or Req.Request.get_option(req, :json) != nil
        end

        test "handles provider options" do
          spec = @mod.spec()
          default_model = ReqLLM.Provider.Utils.default_model(spec)
          messages = [%ReqLLM.Message{role: :user, content: "Hello"}]

          assert {:ok, %Req.Request{}} =
                   @mod.build_request(messages, [temperature: 0.5], model: default_model)
        end
      end

      describe "parse_response/2" do
        test "parses successful response" do
          spec = @mod.spec()

          response = %Req.Response{
            status: 200,
            body: json!(spec.id, "success.json")
          }

          assert {:ok, text} = @mod.parse_response(response, [], stream?: false)
          assert is_binary(text)
        end

        test "handles error response" do
          spec = @mod.spec()

          response = %Req.Response{
            status: 400,
            body: json!(spec.id, "error.json")
          }

          assert {:error, %Error.API.Response{}} =
                   @mod.parse_response(response, [], stream?: false)
        end
      end

      # Note: Integration tests would require more complex Req.Test setup
      # For now, focus on unit testing build_request and parse_response directly

      # Allow the caller to inject extra behavior or skip tests
      @before_compile ReqLLM.ProviderCase
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      # This hook allows providers to customize or skip tests if needed
      # Implementation can be added later if required
    end
  end
end
