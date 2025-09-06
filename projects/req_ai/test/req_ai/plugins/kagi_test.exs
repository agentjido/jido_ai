defmodule ReqAI.Plugins.KagiTest do
  use ExUnit.Case, async: true

  alias ReqAI.Plugins.Kagi

  @moduletag :skip

  describe "attach/1" do
    test "attaches kagi_auth step to request" do
      req = Req.new() |> Kagi.attach()

      assert Enum.any?(req.request_steps, fn
               {:kagi_auth, _fun} -> true
               _ -> false
             end)
    end
  end

  describe "add_auth_header/1" do
    test "adds x-api-key header with :plain wrap strategy" do
      # Set up actual config for test
      Kagi.put(:anthropic_api_key, "sk-ant-123")

      provider_spec = %{id: :anthropic, auth: {:header, "x-api-key", :plain}}

      req =
        Req.new(url: "https://api.anthropic.com/v1/messages")
        |> Req.Request.put_private(:req_ai_provider_spec, provider_spec)

      result = Kagi.add_auth_header(req)

      assert Req.Request.get_header(result, "x-api-key") == ["sk-ant-123"]
    end

    test "adds Authorization header with :bearer wrap strategy" do
      Kagi.put(:openai_api_key, "sk-123")

      provider_spec = %{id: :openai, auth: {:header, "authorization", :bearer}}

      req =
        Req.new(url: "https://api.openai.com/v1/chat/completions")
        |> Req.Request.put_private(:req_ai_provider_spec, provider_spec)

      result = Kagi.add_auth_header(req)

      assert Req.Request.get_header(result, "authorization") == ["Bearer sk-123"]
    end

    test "applies custom wrap function" do
      Kagi.put(:custom_provider_api_key, "api-key-123")

      custom_wrapper = fn key -> "Custom #{key}" end
      provider_spec = %{id: :custom_provider, auth: {:header, "custom-auth", custom_wrapper}}

      req =
        Req.new(url: "https://api.custom.com/v1")
        |> Req.Request.put_private(:req_ai_provider_spec, provider_spec)

      result = Kagi.add_auth_header(req)

      assert Req.Request.get_header(result, "custom-auth") == ["Custom api-key-123"]
    end

    test "does nothing when provider spec is missing" do
      req = Req.new(url: "https://unknown.com/api")

      result = Kagi.add_auth_header(req)

      assert result == req
    end

    test "does nothing when API key is not found" do
      provider_spec = %{id: :nonexistent_provider, auth: {:header, "x-api-key", :plain}}

      req =
        Req.new(url: "https://api.anthropic.com/v1/messages")
        |> Req.Request.put_private(:req_ai_provider_spec, provider_spec)

      result = Kagi.add_auth_header(req)

      assert result == req
    end
  end
end
