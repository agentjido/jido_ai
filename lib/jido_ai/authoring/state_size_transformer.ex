defmodule Jido.AI.DSL.StateSizeTransformer do
  @moduledoc false
  use Spark.Dsl.Transformer
  import Spark.Dsl.Transformer, only: [get_persisted: 2, get_option: 3, set_option: 4]

  # Apply the wrapper option to the author's chosen metadata form before core
  # lowers the definition. Explicit keyword/block conflicts remain conflicts.
  def transform(dsl) do
    module = get_persisted(dsl, :module)
    limit = Module.get_attribute(module, :jido_ai_max_state_size)

    if is_nil(limit) do
      {:ok, dsl}
    else
      opts = Module.get_attribute(module, :jido_agent_options)
      metadata = get_option(dsl, [:agent], :metadata)
      key = Jido.AI.Authoring.state_size_key()

      if is_map(metadata) and not Keyword.has_key?(opts, :metadata) do
        {:ok, set_option(dsl, [:agent], :metadata, Map.put(metadata, key, limit))}
      else
        opts = Keyword.update(opts, :metadata, %{key => limit}, &Map.put(&1, key, limit))
        Module.put_attribute(module, :jido_agent_options, opts)
        {:ok, dsl}
      end
    end
  end
end
