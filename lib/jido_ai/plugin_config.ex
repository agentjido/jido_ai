defmodule Jido.AI.PluginConfig do
  @moduledoc false
  def validate!(opts, supported, label) do
    unless Keyword.keyword?(opts) and length(opts) == length(Enum.uniq_by(opts, &elem(&1, 0))) and
             Keyword.keys(opts) -- supported == [],
           do: raise(ArgumentError, "#{label} options must be unique supported keyword entries")

    :ok
  end
end
