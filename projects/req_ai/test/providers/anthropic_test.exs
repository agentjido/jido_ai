defmodule ReqAI.Providers.AnthropicTest do
  use ReqAI.ProviderCase, module: ReqAI.Providers.Anthropic

  # Provider-specific tests beyond the standard ProviderCase tests
  describe "anthropic-specific behavior" do
    test "includes required Anthropic headers" do
      spec = @mod.spec()
      default_model = ReqAI.Provider.Utils.default_model(spec)
      messages = [%ReqAI.Message{role: :user, content: "Hello"}]

      assert {:ok, req} = @mod.build_request(messages, [], model: default_model)

      # Verify Anthropic-specific headers
      headers = req.headers
      assert headers["content-type"] == ["application/json"]
      assert headers["anthropic-version"] == ["2023-06-01"]
    end

    test "sets correct request structure" do
      spec = @mod.spec()
      default_model = ReqAI.Provider.Utils.default_model(spec)
      messages = [%ReqAI.Message{role: :user, content: "Hello"}]

      assert {:ok, req} = @mod.build_request(messages, [], model: default_model)

      json_body = Req.Request.get_option(req, :json)
      assert json_body != nil
      assert json_body.model == default_model
      assert json_body.max_tokens == 4096
      assert json_body.temperature == 1
      assert json_body.stream == false
      assert is_list(json_body.messages)
    end
  end
end
