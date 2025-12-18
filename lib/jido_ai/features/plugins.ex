defmodule Jido.AI.Features.Plugins do
  @moduledoc """
  Model-specific plugin and extension support.

  Enables integration with provider-specific plugin systems including
  OpenAI GPT Actions, Anthropic MCP, and Google Gemini Extensions.

  ## Supported Plugin Systems

  - **OpenAI**: GPT Actions (custom API integrations)
  - **Anthropic**: Model Context Protocol (MCP) servers
  - **Google**: Gemini Extensions (code execution, search, etc.)

  ## Security

  **⚠️  IMPORTANT SECURITY NOTICE ⚠️**

  Plugin configurations are validated with multiple security controls:

  - **Command Whitelist**: MCP servers can only execute approved commands (npx, node, python3, python)
  - **Plugin Name Validation**: Names must contain only alphanumeric characters, hyphens, and underscores
  - **Environment Variable Filtering**: Blocks environment variables containing secrets/credentials patterns
  - **Logging**: Security violations are logged for monitoring

  Never accept plugin configurations from untrusted sources without additional validation.

  ## Plugin Configuration

  Plugins are configured as maps with provider-specific schemas:

      # OpenAI GPT Action
      %{
        type: :action,
        name: "weather_api",
        description: "Get weather data",
        schema: %{...},  # JSON Schema
        authentication: %{type: "api_key", ...}
      }

      # Anthropic MCP (security validated)
      %{
        type: :mcp_server,
        name: "database",
        command: "npx",  # Must be in whitelist: npx, node, python3, python
        args: ["@modelcontextprotocol/server-postgres"],
        env: %{"NODE_ENV" => "production"}  # No API_KEY, SECRET, etc. allowed
      }

  ## Usage

      # Check plugin support
      Plugins.supports?(model)

      # Configure plugin (with security validation)
      {:ok, config} = Plugins.configure_plugin(plugin_def, :openai)

      # Build plugin-enabled options
      {:ok, opts} = Plugins.build_plugin_options(plugins, base_opts, :openai)
  """

  alias Jido.AI.Model
  require Logger

  @type plugin_type :: :action | :mcp_server | :extension
  @type plugin :: map()

  # Security: Whitelist of allowed MCP server commands
  # Only these commands can be executed for MCP servers
  @allowed_mcp_commands ["npx", "node", "python3", "python"]

  # Security: Forbidden patterns in environment variable names
  # Prevents leaking secrets through MCP server environments
  @forbidden_env_patterns ~r/(KEY|SECRET|TOKEN|PASSWORD|AUTH|CREDENTIAL)/i

  # Security: Valid plugin name pattern
  # Prevents injection attacks through plugin names
  @valid_plugin_name ~r/^[a-zA-Z0-9_-]+$/

  # Validation limits
  @max_plugin_name_length 128
  @max_args_count 50

  @doc """
  Check if a model supports plugins.

  ## Parameters
    - model: Jido.AI.Model struct

  ## Returns
    Boolean indicating plugin support

  ## Examples

      iex> Plugins.supports?(model)
      true  # For OpenAI, Anthropic, Google
  """
  @spec supports?(Model.t()) :: boolean()
  def supports?(%Model{provider: provider}) do
    provider in [:openai, :anthropic, :google]
  end

  @doc """
  Configure a plugin for a specific provider.

  Validates and transforms plugin configuration into provider-specific format.

  ## Parameters
    - plugin: Plugin configuration map
    - provider: Provider atom

  ## Returns
    - `{:ok, configured_plugin}` on success
    - `{:error, reason}` on failure

  ## Examples

      iex> plugin = %{type: :action, name: "api", schema: %{...}}
      iex> Plugins.configure_plugin(plugin, :openai)
      {:ok, %{...}}
  """
  @spec configure_plugin(plugin(), atom()) :: {:ok, map()} | {:error, term()}
  def configure_plugin(%{type: :action} = plugin, :openai) do
    # OpenAI GPT Actions format
    with {:ok, name} <- validate_plugin_name(plugin) do
      configured = %{
        "type" => "function",
        "function" => %{
          "name" => name,
          "description" => Map.get(plugin, :description, ""),
          "parameters" => Map.get(plugin, :schema, %{})
        }
      }

      {:ok, configured}
    end
  end

  def configure_plugin(%{type: :mcp_server} = plugin, :anthropic) do
    # Anthropic MCP server configuration with security validation
    with {:ok, name} <- validate_plugin_name(plugin),
         {:ok, command} <- validate_mcp_command(plugin),
         {:ok, args} <- validate_args(plugin),
         {:ok, env} <- validate_environment(plugin) do
      configured = %{
        "mcpServers" => %{
          name => %{
            "command" => command,
            "args" => args,
            "env" => env
          }
        }
      }

      {:ok, configured}
    end
  end

  def configure_plugin(%{type: :extension} = plugin, :google) do
    # Google Gemini Extensions
    with {:ok, name} <- validate_plugin_name(plugin) do
      configured = %{
        "extension" => %{
          "name" => name,
          "description" => Map.get(plugin, :description, ""),
          "parameters" => Map.get(plugin, :parameters, %{})
        }
      }

      {:ok, configured}
    end
  end

  def configure_plugin(_plugin, provider) do
    {:error, "Plugin configuration not supported for provider: #{provider}"}
  end

  @doc """
  Build options with plugins enabled.

  Adds provider-specific plugin configurations to the options map.

  ## Parameters
    - plugins: List of plugin configuration maps
    - base_opts: Base options map
    - provider: Provider atom

  ## Returns
    - `{:ok, enhanced_opts}` with plugins configured
    - `{:error, reason}` on failure

  ## Examples

      iex> Plugins.build_plugin_options([plugin], opts, :openai)
      {:ok, %{...tools: [...]}}
  """
  @spec build_plugin_options([plugin()], map(), atom()) :: {:ok, map()} | {:error, term()}
  def build_plugin_options(plugins, base_opts, provider) when is_list(plugins) do
    case configure_plugins_for_provider(plugins, provider) do
      {:ok, configured} ->
        opts =
          case provider do
            :openai ->
              # Add to tools array
              existing_tools = Map.get(base_opts, :tools, [])
              Map.put(base_opts, :tools, existing_tools ++ configured)

            :anthropic ->
              # MCP configuration goes in separate config
              Map.put(base_opts, :mcp_config, configured)

            :google ->
              # Extensions go in tools
              existing_tools = Map.get(base_opts, :tools, [])
              Map.put(base_opts, :tools, existing_tools ++ configured)
          end

        {:ok, opts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Discover available plugins for a provider.

  Returns list of built-in plugins supported by the provider.

  ## Parameters
    - provider: Provider atom

  ## Returns
    List of plugin names

  ## Examples

      iex> Plugins.discover(:google)
      ["code_execution", "google_search"]
  """
  @spec discover(atom()) :: [String.t()]
  def discover(:openai) do
    # OpenAI has dynamic GPT Actions, no built-in list
    []
  end

  def discover(:anthropic) do
    # Anthropic MCP servers are user-configured
    []
  end

  def discover(:google) do
    # Google Gemini has built-in extensions
    ["code_execution", "google_search"]
  end

  def discover(_provider), do: []

  @doc """
  Extract plugin execution results from response.

  Parses plugin/tool execution outputs from provider responses.

  ## Parameters
    - response: Raw response from provider
    - provider: Provider atom

  ## Returns
    - `{:ok, [results]}` with plugin execution results
    - `{:ok, []}` if no plugins were executed

  ## Examples

      iex> Plugins.extract_results(response, :openai)
      {:ok, [%{plugin: "weather_api", result: %{...}}]}
  """
  @spec extract_results(map(), atom()) :: {:ok, [map()]}
  def extract_results(%{"tool_calls" => tool_calls}, :openai) when is_list(tool_calls) do
    results =
      tool_calls
      |> Enum.filter(fn call -> Map.get(call, "type") == "function" end)
      |> Enum.map(fn call ->
        %{
          plugin: get_in(call, ["function", "name"]),
          arguments: get_in(call, ["function", "arguments"]),
          result: Map.get(call, "result")
        }
      end)

    {:ok, results}
  end

  def extract_results(_response, _provider) do
    {:ok, []}
  end

  # Private helpers

  # Security validation functions

  defp validate_plugin_name(plugin) do
    case Map.fetch(plugin, :name) do
      {:ok, name} when is_binary(name) ->
        cond do
          String.length(name) == 0 ->
            {:error, "Plugin name cannot be empty"}

          String.length(name) > @max_plugin_name_length ->
            {:error,
             "Plugin name too long: maximum is #{@max_plugin_name_length} characters, got #{String.length(name)}"}

          not Regex.match?(@valid_plugin_name, name) ->
            {:error,
             "Invalid plugin name: '#{name}'. Must contain only alphanumeric characters, hyphens, and underscores"}

          true ->
            {:ok, name}
        end

      {:ok, _} ->
        {:error, "Plugin name must be a string"}

      :error ->
        {:error, "Plugin name is required"}
    end
  end

  defp validate_mcp_command(plugin) do
    command = Map.get(plugin, :command, "")

    cond do
      command == "" ->
        {:error, "MCP server command is required"}

      command not in @allowed_mcp_commands ->
        Logger.warning("Blocked MCP command: #{command}")

        {:error,
         "Command '#{command}' not allowed. Permitted commands: #{inspect(@allowed_mcp_commands)}"}

      true ->
        {:ok, command}
    end
  end

  defp validate_environment(plugin) do
    env = Map.get(plugin, :env, %{})

    if is_map(env) do
      # Check for forbidden environment variable names
      forbidden =
        Enum.find(env, fn {key, _value} ->
          is_binary(key) and Regex.match?(@forbidden_env_patterns, key)
        end)

      case forbidden do
        {key, _} ->
          Logger.warning("Blocked forbidden environment variable: #{key}")

          {:error,
           "Environment variable '#{key}' contains forbidden pattern (secrets/credentials not allowed)"}

        nil ->
          {:ok, env}
      end
    else
      {:error, "Environment must be a map"}
    end
  end

  defp validate_args(plugin) do
    args = Map.get(plugin, :args, [])

    cond do
      not is_list(args) ->
        {:error, "Plugin args must be a list"}

      length(args) > @max_args_count ->
        {:error, "Too many args: maximum is #{@max_args_count}, got #{length(args)}"}

      not Enum.all?(args, &is_binary/1) ->
        {:error, "All args must be strings"}

      true ->
        {:ok, args}
    end
  end

  defp configure_plugins_for_provider(plugins, provider) do
    results =
      Enum.reduce_while(plugins, [], fn plugin, acc ->
        case configure_plugin(plugin, provider) do
          {:ok, configured} -> {:cont, [configured | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case results do
      {:error, reason} -> {:error, reason}
      configured_list -> {:ok, Enum.reverse(configured_list)}
    end
  end
end
