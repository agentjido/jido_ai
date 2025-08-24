defmodule Jido.Tools.AI do
  @moduledoc """
  A collection of AI-powered actions for text generation, streaming, and object creation.

  This module provides a set of AI actions:
  - GenerateText: Generate text responses from prompts
  - StreamText: Stream text responses for real-time output
  - GenerateObject: Generate structured objects based on schemas
  - StreamObject: Stream object generation with incremental updates
  """

  alias Jido.Action

  defmodule GenerateText do
    @moduledoc false
    use Action,
      name: "generate_text",
      description: "Generates text response from a prompt using AI",
      schema: [
        prompt: [
          type: :string,
          required: true,
          doc: "The prompt to generate text from"
        ],
        model: [
          type: :any,
          default: "openai:gpt-4o",
          doc: "The AI model specification (string, tuple, or Model struct)"
        ],
        max_tokens: [
          type: :pos_integer,
          doc: "Maximum number of tokens to generate (overrides model default)"
        ],
        temperature: [
          type: :float,
          doc: "Temperature for randomness (0.0-2.0, overrides model default)"
        ],
        system_prompt: [
          type: :string,
          doc: "Optional system prompt to set context"
        ]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
    def run(%{prompt: prompt, model: model_spec} = params, _ctx) do
      with {:ok, model} <- Jido.AI.model(model_spec),
           {:ok, response} <- Jido.AI.generate_text(model, prompt, build_opts(params)) do
        {:ok, Map.put(params, :response, response)}
      end
    end

    defp build_opts(params) do
      opts = []
      
      opts = if params[:system_prompt], do: Keyword.put(opts, :system_prompt, params[:system_prompt]), else: opts
      opts = if params[:max_tokens], do: Keyword.put(opts, :max_tokens, params[:max_tokens]), else: opts
      opts = if params[:temperature], do: Keyword.put(opts, :temperature, params[:temperature]), else: opts
      
      opts
    end
  end

  defmodule StreamText do
    @moduledoc false
    use Action,
      name: "stream_text",
      description: "Streams text response from a prompt using AI",
      schema: [
        prompt: [
          type: :string,
          required: true,
          doc: "The prompt to generate text from"
        ],
        model: [
          type: :any,
          default: "openai:gpt-4o",
          doc: "The AI model specification (string, tuple, or Model struct)"
        ],
        max_tokens: [
          type: :pos_integer,
          doc: "Maximum number of tokens to generate (overrides model default)"
        ],
        temperature: [
          type: :float,
          doc: "Temperature for randomness (0.0-2.0, overrides model default)"
        ],
        system_prompt: [
          type: :string,
          doc: "Optional system prompt to set context"
        ],
        callback: [
          type: :any,
          doc: "Callback function for handling stream chunks"
        ]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
    def run(%{prompt: prompt, model: model_spec} = params, _ctx) do
      with {:ok, model} <- Jido.AI.model(model_spec),
           {:ok, stream} <- Jido.AI.stream_text(model, prompt, build_opts(params)) do
        
        response = handle_stream(stream, params[:callback])
        {:ok, Map.put(params, :response, response)}
      end
    end

    defp build_opts(params) do
      opts = []
      
      opts = if params[:system_prompt], do: Keyword.put(opts, :system_prompt, params[:system_prompt]), else: opts
      opts = if params[:max_tokens], do: Keyword.put(opts, :max_tokens, params[:max_tokens]), else: opts
      opts = if params[:temperature], do: Keyword.put(opts, :temperature, params[:temperature]), else: opts
      
      opts
    end

    defp handle_stream(stream, callback) do
      # TODO: Implement stream handling
      # For now, collect all chunks
      Enum.reduce(stream, "", fn chunk, acc ->
        if callback, do: callback.(chunk)
        acc <> chunk
      end)
    end
  end

  defmodule GenerateObject do
    @moduledoc false
    use Action,
      name: "generate_object",
      description: "Generates structured object from a prompt using AI",
      schema: [
        prompt: [
          type: :string,
          required: true,
          doc: "The prompt to generate object from"
        ],
        schema: [
          type: :any,
          required: true,
          doc: "NimbleOptions schema or JSON schema defining the expected object structure"
        ],
        model: [
          type: :any,
          default: "openai:gpt-4o",
          doc: "The AI model specification (string, tuple, or Model struct)"
        ],
        max_tokens: [
          type: :pos_integer,
          doc: "Maximum number of tokens to generate (overrides model default)"
        ],
        temperature: [
          type: :float,
          doc: "Temperature for randomness (0.0-2.0, overrides model default)"
        ],
        system_prompt: [
          type: :string,
          doc: "Optional system prompt to set context"
        ]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
    def run(%{prompt: prompt, schema: schema, model: model_spec} = params, _ctx) do
      with {:ok, model} <- Jido.AI.model(model_spec),
           {:ok, object} <- Jido.AI.generate_object(model, prompt, schema, build_opts(params)) do
        {:ok, Map.put(params, :object, object)}
      end
    end

    defp build_opts(params) do
      opts = []
      
      opts = if params[:system_prompt], do: Keyword.put(opts, :system_prompt, params[:system_prompt]), else: opts
      opts = if params[:max_tokens], do: Keyword.put(opts, :max_tokens, params[:max_tokens]), else: opts
      opts = if params[:temperature], do: Keyword.put(opts, :temperature, params[:temperature]), else: opts
      
      opts
    end
  end

  defmodule StreamObject do
    @moduledoc false
    use Action,
      name: "stream_object",
      description: "Streams structured object generation from a prompt using AI",
      schema: [
        prompt: [
          type: :string,
          required: true,
          doc: "The prompt to generate object from"
        ],
        schema: [
          type: :any,
          required: true,
          doc: "NimbleOptions schema or JSON schema defining the expected object structure"
        ],
        model: [
          type: :any,
          default: "openai:gpt-4o",
          doc: "The AI model specification (string, tuple, or Model struct)"
        ],
        max_tokens: [
          type: :pos_integer,
          doc: "Maximum number of tokens to generate (overrides model default)"
        ],
        temperature: [
          type: :float,
          doc: "Temperature for randomness (0.0-2.0, overrides model default)"
        ],
        system_prompt: [
          type: :string,
          doc: "Optional system prompt to set context"
        ],
        callback: [
          type: :any,
          doc: "Callback function for handling stream updates"
        ]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
    def run(%{prompt: prompt, schema: schema, model: model_spec} = params, _ctx) do
      with {:ok, model} <- Jido.AI.model(model_spec),
           {:ok, stream} <- Jido.AI.stream_object(model, prompt, schema, build_opts(params)) do
        
        object = handle_stream(stream, params[:callback])
        {:ok, Map.put(params, :object, object)}
      end
    end

    defp build_opts(params) do
      opts = []
      
      opts = if params[:system_prompt], do: Keyword.put(opts, :system_prompt, params[:system_prompt]), else: opts
      opts = if params[:max_tokens], do: Keyword.put(opts, :max_tokens, params[:max_tokens]), else: opts
      opts = if params[:temperature], do: Keyword.put(opts, :temperature, params[:temperature]), else: opts
      
      opts
    end

    defp handle_stream(stream, callback) do
      # TODO: Implement stream handling for objects
      # For now, collect final object
      Enum.reduce(stream, %{}, fn update, acc ->
        if callback, do: callback.(update)
        Map.merge(acc, update)
      end)
    end
  end
end
