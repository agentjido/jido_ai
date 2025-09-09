# defmodule ReqLLM.Capability.GenerateTextTest do
#   use ExUnit.Case, async: false
#   use Mimic

#   alias ReqLLM.Capability.GenerateText

#   setup :verify_on_exit!
#   setup :set_mimic_global

#   describe "id/0" do
#     test "returns generate_text atom" do
#       assert GenerateText.id() == :generate_text
#     end
#   end

#   describe "advertised?/1" do
#     test "returns true for any model" do
#       model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}
#       assert GenerateText.advertised?(model) == true
#     end
#   end

#   describe "verify/2" do
#     test "returns :ok with response details on successful generation" do
#       model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}

#       response_body = "Hello there! How can I help you?"
#       mock_response = %Req.Response{body: response_body}

#       ReqLLM
#       |> expect(:generate_text, fn model_spec, message, opts ->
#         assert model_spec == "openai:gpt-4"
#         assert message == "Hello!"
#         assert opts[:provider_options][:timeout] == 10_000
#         {:ok, mock_response}
#       end)

#       {:ok, result} = GenerateText.verify(model, [])

#       assert result.model_id == "openai:gpt-4"
#       assert result.response_length == String.length(response_body)
#       assert result.response_preview == String.slice(response_body, 0, 50)
#     end

#     test "uses custom timeout from options" do
#       model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}

#       ReqLLM
#       |> expect(:generate_text, fn _model_spec, _message, opts ->
#         assert opts[:provider_options][:timeout] == 30_000
#         assert opts[:provider_options][:receive_timeout] == 30_000
#         {:ok, %Req.Response{body: "Response"}}
#       end)

#       {:ok, _result} = GenerateText.verify(model, timeout: 30_000)
#     end

#     test "returns :error when response is empty" do
#       model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}

#       ReqLLM
#       |> expect(:generate_text, fn _model_spec, _message, _opts ->
#         {:ok, %Req.Response{body: "   "}}
#       end)

#       {:error, reason} = GenerateText.verify(model, [])
#       assert reason == "Empty response"
#     end

#     test "returns :error when ReqLLM.generate_text fails" do
#       model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}

#       ReqLLM
#       |> expect(:generate_text, fn _model_spec, _message, _opts ->
#         {:error, "API timeout"}
#       end)

#       {:error, reason} = GenerateText.verify(model, [])
#       assert reason == "API timeout"
#     end

#     test "handles long responses correctly" do
#       model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}
#       long_response = String.duplicate("Hello world! ", 50)

#       ReqLLM
#       |> expect(:generate_text, fn _model_spec, _message, _opts ->
#         {:ok, %Req.Response{body: long_response}}
#       end)

#       {:ok, result} = GenerateText.verify(model, [])

#       assert result.response_length == String.length(long_response)
#       assert result.response_preview == String.slice(long_response, 0, 50)
#       assert String.length(result.response_preview) == 50
#     end

#     test "handles response with only whitespace" do
#       model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}

#       ReqLLM
#       |> expect(:generate_text, fn _model_spec, _message, _opts ->
#         {:ok, %Req.Response{body: "\n\t  \r\n"}}
#       end)

#       {:error, reason} = GenerateText.verify(model, [])
#       assert reason == "Empty response"
#     end
#   end
# end
