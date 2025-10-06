defmodule Jido.AI.Features.PluginsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Features.Plugins
  alias Jido.AI.Model

  describe "supports?/1" do
    test "returns true for OpenAI models" do
      model = %Model{provider: :openai, model: "gpt-4"}
      assert Plugins.supports?(model)
    end

    test "returns true for Anthropic models" do
      model = %Model{provider: :anthropic, model: "claude-3-sonnet"}
      assert Plugins.supports?(model)
    end

    test "returns true for Google models" do
      model = %Model{provider: :google, model: "gemini-pro"}
      assert Plugins.supports?(model)
    end

    test "returns false for Cohere models" do
      model = %Model{provider: :cohere, model: "command-r"}
      refute Plugins.supports?(model)
    end

    test "returns false for local models" do
      model = %Model{provider: :ollama, model: "llama2"}
      refute Plugins.supports?(model)
    end

    test "returns false for Groq models" do
      model = %Model{provider: :groq, model: "mixtral-8x7b"}
      refute Plugins.supports?(model)
    end
  end

  describe "configure_plugin/2" do
    test "configures OpenAI GPT Action" do
      plugin = %{
        type: :action,
        name: "weather_api",
        description: "Get weather data",
        schema: %{
          type: "object",
          properties: %{
            location: %{type: "string"}
          }
        }
      }

      {:ok, configured} = Plugins.configure_plugin(plugin, :openai)

      assert configured["type"] == "function"
      assert configured["function"]["name"] == "weather_api"
      assert configured["function"]["description"] == "Get weather data"
      assert configured["function"]["parameters"][:type] == "object"
      assert configured["function"]["parameters"][:properties][:location][:type] == "string"
    end

    test "configures OpenAI action with minimal fields" do
      plugin = %{
        type: :action,
        name: "simple_action"
      }

      {:ok, configured} = Plugins.configure_plugin(plugin, :openai)

      assert configured["function"]["name"] == "simple_action"
      assert configured["function"]["description"] == ""
      assert configured["function"]["parameters"] == %{}
    end

    test "returns error for OpenAI action missing name field" do
      plugin = %{
        type: :action,
        description: "No name"
      }

      assert {:error, reason} = Plugins.configure_plugin(plugin, :openai)
      assert reason =~ "name is required"
    end

    test "configures Anthropic MCP server" do
      plugin = %{
        type: :mcp_server,
        name: "database",
        command: "npx",
        args: ["@modelcontextprotocol/server-postgres"],
        env: %{"DB_URL" => "postgresql://localhost"}
      }

      {:ok, configured} = Plugins.configure_plugin(plugin, :anthropic)

      assert configured["mcpServers"]["database"]["command"] == "npx"
      assert configured["mcpServers"]["database"]["args"] == ["@modelcontextprotocol/server-postgres"]
      assert configured["mcpServers"]["database"]["env"]["DB_URL"] == "postgresql://localhost"
    end

    test "configures Anthropic MCP server with minimal fields" do
      plugin = %{
        type: :mcp_server,
        name: "simple_server",
        command: "npx"  # Required and must be whitelisted
      }

      {:ok, configured} = Plugins.configure_plugin(plugin, :anthropic)

      assert configured["mcpServers"]["simple_server"]["command"] == "npx"
      assert configured["mcpServers"]["simple_server"]["args"] == []
      assert configured["mcpServers"]["simple_server"]["env"] == %{}
    end

    test "rejects MCP server with invalid command" do
      plugin = %{
        type: :mcp_server,
        name: "malicious",
        command: "rm"  # Not in whitelist
      }

      assert {:error, reason} = Plugins.configure_plugin(plugin, :anthropic)
      assert reason =~ "not allowed"
      assert reason =~ "rm"
    end

    test "rejects MCP server with missing command" do
      plugin = %{
        type: :mcp_server,
        name: "no_command"
      }

      assert {:error, reason} = Plugins.configure_plugin(plugin, :anthropic)
      assert reason =~ "command is required"
    end

    test "rejects MCP server with invalid name characters" do
      plugin = %{
        type: :mcp_server,
        name: "bad name with spaces",
        command: "npx"
      }

      assert {:error, reason} = Plugins.configure_plugin(plugin, :anthropic)
      assert reason =~ "Invalid plugin name"
    end

    test "rejects MCP server with forbidden environment variables" do
      plugin = %{
        type: :mcp_server,
        name: "leaky_server",
        command: "npx",
        env: %{"API_KEY" => "secret123"}
      }

      assert {:error, reason} = Plugins.configure_plugin(plugin, :anthropic)
      assert reason =~ "API_KEY"
      assert reason =~ "forbidden pattern"
    end

    test "allows MCP server with safe environment variables" do
      plugin = %{
        type: :mcp_server,
        name: "safe_server",
        command: "npx",
        env: %{"NODE_ENV" => "production", "LOG_LEVEL" => "info"}
      }

      assert {:ok, configured} = Plugins.configure_plugin(plugin, :anthropic)
      assert configured["mcpServers"]["safe_server"]["env"]["NODE_ENV"] == "production"
    end

    test "configures Google Gemini Extension" do
      plugin = %{
        type: :extension,
        name: "code_execution",
        description: "Execute Python code",
        parameters: %{timeout: 30}
      }

      {:ok, configured} = Plugins.configure_plugin(plugin, :google)

      assert configured["extension"]["name"] == "code_execution"
      assert configured["extension"]["description"] == "Execute Python code"
      assert configured["extension"]["parameters"][:timeout] == 30
    end

    test "configures Google extension with minimal fields" do
      plugin = %{
        type: :extension,
        name: "simple_extension"
      }

      {:ok, configured} = Plugins.configure_plugin(plugin, :google)

      assert configured["extension"]["name"] == "simple_extension"
      assert configured["extension"]["description"] == ""
      assert configured["extension"]["parameters"] == %{}
    end

    test "returns error for Google extension missing name field" do
      plugin = %{
        type: :extension,
        description: "No name"
      }

      assert {:error, reason} = Plugins.configure_plugin(plugin, :google)
      assert reason =~ "name is required"
    end

    test "returns error for unsupported provider" do
      plugin = %{type: :action, name: "test"}

      assert {:error, _reason} = Plugins.configure_plugin(plugin, :cohere)
    end

    test "returns error for mismatched plugin type and provider" do
      plugin = %{type: :action, name: "test"}

      assert {:error, _reason} = Plugins.configure_plugin(plugin, :anthropic)
    end

    test "returns error for plugin with empty name" do
      plugin = %{type: :action, name: ""}

      assert {:error, reason} = Plugins.configure_plugin(plugin, :openai)
      assert reason =~ "cannot be empty"
    end

    test "returns error for plugin with name too long" do
      long_name = String.duplicate("a", 129)
      plugin = %{type: :action, name: long_name}

      assert {:error, reason} = Plugins.configure_plugin(plugin, :openai)
      assert reason =~ "too long"
      assert reason =~ "128"
    end

    test "returns error for plugin with invalid characters in name" do
      plugin = %{type: :action, name: "invalid name!"}

      assert {:error, reason} = Plugins.configure_plugin(plugin, :openai)
      assert reason =~ "Invalid plugin name"
      assert reason =~ "alphanumeric"
    end

    test "returns error for MCP server with too many args" do
      plugin = %{
        type: :mcp_server,
        name: "test",
        command: "npx",
        args: Enum.map(1..51, fn i -> "arg#{i}" end)
      }

      assert {:error, reason} = Plugins.configure_plugin(plugin, :anthropic)
      assert reason =~ "Too many args"
      assert reason =~ "50"
    end

    test "returns error for MCP server with non-list args" do
      plugin = %{
        type: :mcp_server,
        name: "test",
        command: "npx",
        args: "not-a-list"
      }

      assert {:error, reason} = Plugins.configure_plugin(plugin, :anthropic)
      assert reason =~ "must be a list"
    end

    test "returns error for MCP server with non-string args" do
      plugin = %{
        type: :mcp_server,
        name: "test",
        command: "npx",
        args: ["valid", 123, "another"]
      }

      assert {:error, reason} = Plugins.configure_plugin(plugin, :anthropic)
      assert reason =~ "must be strings"
    end
  end

  describe "build_plugin_options/3" do
    setup do
      base_opts = %{temperature: 0.7, max_tokens: 500}
      {:ok, base_opts: base_opts}
    end

    test "builds options for OpenAI with single plugin", %{base_opts: base_opts} do
      plugins = [
        %{type: :action, name: "weather", description: "Get weather"}
      ]

      {:ok, opts} = Plugins.build_plugin_options(plugins, base_opts, :openai)

      assert opts.temperature == 0.7
      assert is_list(opts.tools)
      assert length(opts.tools) == 1
      assert Enum.at(opts.tools, 0)["type"] == "function"
    end

    test "builds options for OpenAI with multiple plugins", %{base_opts: base_opts} do
      plugins = [
        %{type: :action, name: "weather", description: "Get weather"},
        %{type: :action, name: "search", description: "Search web"}
      ]

      {:ok, opts} = Plugins.build_plugin_options(plugins, base_opts, :openai)

      assert length(opts.tools) == 2
    end

    test "preserves existing tools for OpenAI", %{base_opts: base_opts} do
      base_with_tools = Map.put(base_opts, :tools, [%{type: "function", function: %{name: "existing"}}])

      plugins = [
        %{type: :action, name: "new_plugin"}
      ]

      {:ok, opts} = Plugins.build_plugin_options(plugins, base_with_tools, :openai)

      assert length(opts.tools) == 2
    end

    test "builds options for Anthropic with MCP server", %{base_opts: base_opts} do
      plugins = [
        %{type: :mcp_server, name: "database", command: "npx"}
      ]

      {:ok, opts} = Plugins.build_plugin_options(plugins, base_opts, :anthropic)

      assert opts.temperature == 0.7
      assert Map.has_key?(opts, :mcp_config)
      assert is_list(opts.mcp_config)
    end

    test "builds options for Google with extensions", %{base_opts: base_opts} do
      plugins = [
        %{type: :extension, name: "code_execution"}
      ]

      {:ok, opts} = Plugins.build_plugin_options(plugins, base_opts, :google)

      assert opts.temperature == 0.7
      assert is_list(opts.tools)
      assert length(opts.tools) == 1
    end

    test "handles empty plugin list", %{base_opts: base_opts} do
      {:ok, opts} = Plugins.build_plugin_options([], base_opts, :openai)

      assert opts.tools == []
    end

    test "returns error for invalid plugin configuration", %{base_opts: base_opts} do
      plugins = [
        %{type: :action, name: "test"}  # Valid
      ]

      # Using unsupported provider
      assert {:error, _reason} = Plugins.build_plugin_options(plugins, base_opts, :cohere)
    end
  end

  describe "discover/1" do
    test "returns empty list for OpenAI (dynamic GPT Actions)" do
      assert Plugins.discover(:openai) == []
    end

    test "returns empty list for Anthropic (user-configured MCP)" do
      assert Plugins.discover(:anthropic) == []
    end

    test "returns built-in extensions for Google" do
      extensions = Plugins.discover(:google)

      assert "code_execution" in extensions
      assert "google_search" in extensions
    end

    test "returns empty list for unsupported provider" do
      assert Plugins.discover(:cohere) == []
      assert Plugins.discover(:ollama) == []
    end
  end

  describe "extract_results/2" do
    test "extracts plugin results from OpenAI response" do
      response = %{
        "tool_calls" => [
          %{
            "type" => "function",
            "function" => %{
              "name" => "weather_api",
              "arguments" => "{\"location\": \"San Francisco\"}"
            },
            "result" => %{"temperature" => 72}
          }
        ]
      }

      {:ok, results} = Plugins.extract_results(response, :openai)

      assert length(results) == 1
      result = Enum.at(results, 0)
      assert result.plugin == "weather_api"
      assert result.arguments == "{\"location\": \"San Francisco\"}"
      assert result.result == %{"temperature" => 72}
    end

    test "extracts multiple plugin results" do
      response = %{
        "tool_calls" => [
          %{
            "type" => "function",
            "function" => %{"name" => "plugin1", "arguments" => "{}"}
          },
          %{
            "type" => "function",
            "function" => %{"name" => "plugin2", "arguments" => "{}"}
          }
        ]
      }

      {:ok, results} = Plugins.extract_results(response, :openai)

      assert length(results) == 2
    end

    test "filters out non-function tool calls" do
      response = %{
        "tool_calls" => [
          %{
            "type" => "code_interpreter",
            "code_interpreter" => %{"input" => "print('test')"}
          },
          %{
            "type" => "function",
            "function" => %{"name" => "plugin", "arguments" => "{}"}
          }
        ]
      }

      {:ok, results} = Plugins.extract_results(response, :openai)

      assert length(results) == 1
      assert Enum.at(results, 0).plugin == "plugin"
    end

    test "handles missing result field" do
      response = %{
        "tool_calls" => [
          %{
            "type" => "function",
            "function" => %{"name" => "plugin", "arguments" => "{}"}
          }
        ]
      }

      {:ok, results} = Plugins.extract_results(response, :openai)

      assert length(results) == 1
      assert Enum.at(results, 0).result == nil
    end

    test "returns empty list for response without tool_calls" do
      response = %{"content" => "Regular response"}

      {:ok, results} = Plugins.extract_results(response, :openai)

      assert results == []
    end

    test "returns empty list for unsupported provider" do
      response = %{"content" => "Response"}

      {:ok, results} = Plugins.extract_results(response, :anthropic)

      assert results == []
    end
  end
end
