defmodule Jido.AI.Error.ModelTest do
  use ExUnit.Case, async: true

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
end
