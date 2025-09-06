defmodule ReqAI.ProviderAuthIntegrationTest do
  use ExUnit.Case, async: true

  alias ReqAI.Providers.Anthropic

  @moduletag :skip

  describe "Provider auth integration" do
    test "provider macro injects spec and attaches Kagi plugin" do
      # Set up API key
      Kagi.put(:anthropic_api_key, "sk-ant-test-key")

      # Create a simple request using the provider's build_request
      {:ok, request} = Anthropic.build_request("Hello", [], [])

      # Verify that the request doesn't have auth headers yet
      refute Req.Request.get_header(request, "x-api-key") == ["sk-ant-test-key"]

      # Now send the request through the provider's send_request method
      # This should inject the provider spec and attach the Kagi plugin
      # We'll mock the actual HTTP call to avoid real network requests

      # Get the spec from the provider
      spec = Anthropic.spec()

      # Verify the spec has the right auth configuration
      assert spec.id == :anthropic
      assert spec.auth == {:header, "x-api-key", :plain}

      # Test the flow by manually injecting spec and applying the plugin
      request_with_spec = Req.Request.put_private(request, :req_ai_provider_spec, spec)
      request_with_auth = ReqAI.Plugins.Kagi.attach(request_with_spec)

      # Manually trigger the auth injection step
      final_request = ReqAI.Plugins.Kagi.add_auth_header(request_with_auth)

      # Verify auth header was added
      assert Req.Request.get_header(final_request, "x-api-key") == ["sk-ant-test-key"]
    end

    test "provider works with :bearer auth strategy" do
      # Create a test provider spec with bearer auth
      Kagi.put(:test_provider_api_key, "test-api-key")

      provider_spec = %{id: :test_provider, auth: {:header, "authorization", :bearer}}

      request =
        Req.new(url: "https://api.test.com")
        |> Req.Request.put_private(:req_ai_provider_spec, provider_spec)
        |> ReqAI.Plugins.Kagi.attach()

      final_request = ReqAI.Plugins.Kagi.add_auth_header(request)

      assert Req.Request.get_header(final_request, "authorization") == ["Bearer test-api-key"]
    end

    test "provider works with custom wrap function" do
      Kagi.put(:custom_provider_api_key, "custom-key")

      custom_wrapper = fn key -> "Token #{key}" end
      provider_spec = %{id: :custom_provider, auth: {:header, "x-custom-auth", custom_wrapper}}

      request =
        Req.new(url: "https://api.custom.com")
        |> Req.Request.put_private(:req_ai_provider_spec, provider_spec)
        |> ReqAI.Plugins.Kagi.attach()

      final_request = ReqAI.Plugins.Kagi.add_auth_header(request)

      assert Req.Request.get_header(final_request, "x-custom-auth") == ["Token custom-key"]
    end
  end
end
