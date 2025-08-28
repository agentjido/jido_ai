defmodule Jido.AI.Middleware do
  @moduledoc """
  Middleware infrastructure for AI request/response pipeline processing.

  Provides a composable middleware system that allows intercepting and modifying
  AI requests and responses. Middleware can be used for logging, caching, rate limiting,
  token counting, cost tracking, and other cross-cutting concerns.

  ## Usage

      # Define a middleware
      defmodule MyMiddleware do
        @behaviour Jido.AI.Middleware

        @impl true
        def call(context, next) do
          # Process request phase
          context = log_request(context)

          # Call next middleware
          context = next.(context)

          # Process response phase
          log_response(context)
        end
      end

      # Build and run pipeline
      middlewares = [LoggingMiddleware, TokenCountingMiddleware]
      result = Middleware.run(middlewares, context, &actual_api_call/1)

  ## Context Flow

  The middleware pipeline operates on a `Context` struct that flows through each middleware:

  1. Context starts in `:request` phase with request data
  2. Each middleware can modify the context and call `next.(context)`
  3. The final function (actual API call) switches context to `:response` phase
  4. Context flows back through middleware chain in reverse order
  5. Each middleware can process the response phase

  ## Middleware Behaviour

  Middleware modules must implement the `Jido.AI.Middleware` behaviour:

      @callback call(Context.t(), (Context.t() -> Context.t())) :: Context.t()

  The `call/2` function receives:
  - `context` - Current context with request/response data
  - `next` - Function to call the next middleware in the chain
  """

  alias Jido.AI.Middleware.Context
  alias Jido.AI.Middleware.CostCalculator
  alias Jido.AI.Middleware.UsageExtraction

  @doc """
  Middleware behaviour callback.

  Processes the context and calls the next middleware in the pipeline.
  Should return the (potentially modified) context.

  ## Parameters

    * `context` - The current context flowing through the pipeline
    * `next` - Function to call the next middleware: `(Context.t() -> Context.t())`

  ## Returns

  The context after processing, potentially with modifications.
  """
  @callback call(Context.t(), (Context.t() -> Context.t())) :: Context.t()

  @doc """
  Runs a middleware pipeline with the given context and final function.

  Composes a chain of middleware functions and executes them in order,
  with the final function being called at the end of the request phase.

  ## Parameters

    * `middlewares` - List of middleware modules implementing the behaviour
    * `context` - Initial context for the pipeline
    * `final_fun` - Function called at the end of the request phase, should return context in response phase

  ## Examples

      middlewares = [LoggingMiddleware, CachingMiddleware]
      context = Context.new(:request, model, body, opts)

      result_context = Middleware.run(middlewares, context, fn ctx ->
        # This function does the actual API call
        response_body = make_api_call(ctx.body)
        ctx
        |> Context.put_phase(:response)
        |> Context.put_body(response_body)
      end)

  ## Returns

  The final context after all middleware have processed both request and response phases.
  """
  @spec run([module()], Context.t(), (Context.t() -> Context.t())) :: Context.t()
  def run(middlewares, context, final_fun) when is_list(middlewares) and is_function(final_fun, 1) do
    # Build the middleware chain by folding from right to left
    # This creates a nested function structure where each middleware wraps the next
    chain_fun =
      middlewares
      |> Enum.reverse()
      |> Enum.reduce(final_fun, fn middleware_module, next_fun ->
        fn ctx -> middleware_module.call(ctx, next_fun) end
      end)

    # Execute the complete chain
    chain_fun.(context)
  end

  @doc """
  Convenience function to run a single middleware with a context and next function.

  Useful for testing individual middleware or simple single-middleware scenarios.

  ## Examples

      context = Context.new(:request, model, body, opts)
      
      result = Middleware.run_one(MyMiddleware, context, fn ctx ->
        # Do something with context
        Context.put_meta(ctx, :processed, true)
      end)
  """
  @spec run_one(module(), Context.t(), (Context.t() -> Context.t())) :: Context.t()
  def run_one(middleware_module, context, next_fun) do
    middleware_module.call(context, next_fun)
  end

  @doc """
  Validates that all modules in the list implement the Middleware behaviour.

  ## Examples

      iex> Middleware.validate_middlewares([ValidMiddleware])
      :ok

      iex> Middleware.validate_middlewares([InvalidModule])
      {:error, "InvalidModule does not implement Jido.AI.Middleware behaviour"}

  ## Returns

    * `:ok` if all modules are valid
    * `{:error, reason}` if any module is invalid
  """
  @spec validate_middlewares([module()]) :: :ok | {:error, String.t()}
  def validate_middlewares(middlewares) when is_list(middlewares) do
    case Enum.find(middlewares, &(not implements_behaviour?(&1))) do
      nil ->
        :ok

      invalid_module ->
        {:error, "#{invalid_module} does not implement Jido.AI.Middleware behaviour"}
    end
  end

  @doc """
  Returns the default middleware pipeline configuration.

  The default pipeline includes core middlewares for usage extraction and cost calculation.
  This provides a standard set of middlewares that work well for most use cases.

  ## Returns

  List of middleware modules in execution order.

  ## Examples

      iex> Middleware.default_pipeline()
      [
        Jido.AI.Middleware.UsageExtraction,
        Jido.AI.Middleware.CostCalculator
      ]
  """
  @spec default_pipeline() :: [
          CostCalculator | UsageExtraction,
          ...
        ]
  def default_pipeline do
    [
      UsageExtraction,
      CostCalculator
    ]
  end

  @doc """
  Returns a customized middleware pipeline for a specific provider.

  Allows provider-specific customization of the middleware pipeline while
  maintaining a consistent base set of middlewares.

  ## Parameters

    * `provider` - The provider atom (e.g., `:openai`, `:anthropic`, `:google`)
    * `opts` - Optional customization options

  ## Options

    * `:additional` - List of additional middlewares to prepend to the default pipeline
    * `:override` - Complete middleware list to use instead of default pipeline

  ## Examples

      # Use default pipeline for OpenAI
      iex> Middleware.provider_pipeline(:openai)
      [
        Jido.AI.Middleware.UsageExtraction,
        Jido.AI.Middleware.CostCalculator
      ]

      # Add custom middleware for specific provider
      iex> Middleware.provider_pipeline(:custom, additional: [CustomMiddleware])
      [
        CustomMiddleware,
        Jido.AI.Middleware.UsageExtraction,
        Jido.AI.Middleware.CostCalculator
      ]

      # Override entire pipeline
      iex> Middleware.provider_pipeline(:test, override: [TestMiddleware])
      [TestMiddleware]
  """
  @spec provider_pipeline(atom(), keyword()) :: [module()]
  def provider_pipeline(provider, opts \\ []) do
    cond do
      override = Keyword.get(opts, :override) ->
        override

      additional = Keyword.get(opts, :additional) ->
        additional ++ default_pipeline()

      true ->
        # Check for provider-specific config from Application environment
        case get_provider_config(provider) do
          nil -> default_pipeline()
          config -> Keyword.get(config, :middlewares, default_pipeline())
        end
    end
  end

  @doc """
  Runs a middleware pipeline with proper error handling and validation.

  Enhanced version of `run/3` that includes validation, error handling,
  and optional performance monitoring.

  ## Parameters

    * `middlewares` - List of middleware modules
    * `context` - Initial context for the pipeline
    * `final_fun` - Function called at the end of the request phase
    * `opts` - Optional configuration

  ## Options

    * `:validate` - Whether to validate middlewares before running (default: true)
    * `:monitor` - Whether to add performance monitoring (default: false)

  ## Returns

    * `{:ok, context}` - Success with final context
    * `{:error, reason}` - Error during pipeline execution

  ## Examples

      result = Middleware.run_safe(middlewares, context, &api_call/1)
      case result do
        {:ok, final_context} -> handle_success(final_context)
        {:error, reason} -> handle_error(reason)
      end
  """
  @spec run_safe([module()], Context.t(), (Context.t() -> Context.t()), keyword()) ::
          {:ok, Context.t()} | {:error, any()}
  def run_safe(middlewares, context, final_fun, opts \\ []) do
    validate? = Keyword.get(opts, :validate, true)
    monitor? = Keyword.get(opts, :monitor, false)

    with :ok <- if(validate?, do: validate_middlewares(middlewares), else: :ok) do
      try do
        # Add monitoring middleware if requested
        middlewares = if monitor?, do: [MonitoringMiddleware | middlewares], else: middlewares

        result_context = run(middlewares, context, final_fun)
        {:ok, result_context}
      rescue
        exception ->
          {:error, {:middleware_exception, exception, __STACKTRACE__}}
      catch
        :throw, value ->
          {:error, {:middleware_throw, value}}

        :exit, reason ->
          {:error, {:middleware_exit, reason}}
      end
    end
  end

  @doc """
  Loads middleware configuration from Application environment.

  Checks the Application environment for middleware configuration under the
  `:jido_ai` application key.

  ## Examples

      # In config/config.exs
      config :jido_ai, :middlewares, %{
        default: [
          Jido.AI.Middleware.UsageExtraction,
          Jido.AI.Middleware.CostCalculator
        ],
        providers: %{
          openai: [
            Jido.AI.Middleware.RateLimiting,
            Jido.AI.Middleware.UsageExtraction,
            Jido.AI.Middleware.CostCalculator
          ]
        }
      }

      iex> Middleware.load_config()
      %{
        default: [...],
        providers: %{openai: [...]}
      }
  """
  @spec load_config() :: map()
  def load_config do
    Application.get_env(:jido_ai, :middlewares, %{})
  end

  # Private helper to get provider-specific configuration
  @spec get_provider_config(atom()) :: keyword() | nil
  defp get_provider_config(provider) do
    config = load_config()

    config
    |> Map.get(:providers, %{})
    |> Map.get(provider)
  end

  # Private helper to check if a module implements the Middleware behaviour
  @spec implements_behaviour?(module()) :: boolean()
  defp implements_behaviour?(module) do
    behaviours =
      try do
        module.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()
      rescue
        _ -> []
      end

    __MODULE__ in behaviours
  end
end
