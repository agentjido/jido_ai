defmodule ReqAI.Response.ParserTest do
  use ExUnit.Case, async: true

  alias ReqAI.Response.Parser

  describe "extract_text/1" do
    test "extracts simple text content from OpenAI response" do
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{"content" => "Hello world!"}}
          ]
        }
      }

      assert {:ok, "Hello world!"} = Parser.extract_text(response)
    end

    test "extracts text with reasoning from OpenAI response" do
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{
              "content" => "Hello world!",
              "reasoning" => "The user greeted me, so I should respond politely."
            }}
          ]
        }
      }

      expected = "🧠 **Reasoning:**\nThe user greeted me, so I should respond politely.\n\n**Response:**\nHello world!"
      assert {:ok, ^expected} = Parser.extract_text(response)
    end

    test "extracts simple text content from Anthropic response" do
      response = %Req.Response{
        status: 200,
        body: %{
          "content" => [
            %{"type" => "text", "text" => "Hello world!"}
          ]
        }
      }

      assert {:ok, "Hello world!"} = Parser.extract_text(response)
    end

    test "extracts text with thinking from Anthropic response" do
      response = %Req.Response{
        status: 200,
        body: %{
          "content" => [
            %{"type" => "thinking", "thinking" => "The user greeted me, so I should respond politely."},
            %{"type" => "text", "text" => "Hello world!"}
          ]
        }
      }

      expected = "🧠 **Thinking:**\nThe user greeted me, so I should respond politely.\n\n**Response:**\nHello world!"
      assert {:ok, ^expected} = Parser.extract_text(response)
    end

    test "handles empty reasoning/thinking" do
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{
              "content" => "Hello world!",
              "reasoning" => ""
            }}
          ]
        }
      }

      assert {:ok, "Hello world!"} = Parser.extract_text(response)
    end

    test "handles error responses" do
      response = %Req.Response{
        status: 400,
        body: %{
          "error" => %{
            "message" => "Invalid request",
            "type" => "invalid_request_error"
          }
        }
      }

      assert {:error, %ReqAI.Error.API.Request{}} = Parser.extract_text(response)
    end
  end

  describe "extract_object/1" do
    test "extracts JSON object from response" do
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{"content" => ~s({"name": "John", "age": 30})}}
          ]
        }
      }

      assert {:ok, %{"name" => "John", "age" => 30}} = Parser.extract_object(response)
    end

    test "handles invalid JSON in response" do
      response = %Req.Response{
        status: 200,
        body: %{
          "choices" => [
            %{"message" => %{"content" => "not json"}}
          ]
        }
      }

      assert {:error, %ReqAI.Error.API.Request{}} = Parser.extract_object(response)
    end
  end
end
