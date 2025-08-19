defmodule Sparq.Handlers.IO do
  @moduledoc """
  Handles IO operations in the Sparq language.
  This includes printing and other IO-related functionality.
  """

  use Sparq.Handlers.Behaviour
  alias Sparq.Context

  @impl true
  def handle(:print, _meta, [msg], ctx) do
    {msg, Context.add_event(ctx, :frame_entry, msg)}
  end

  @impl true
  def validate(:print, args) when length(args) != 1, do: {:error, :invalid_arity}
  def validate(:print, _args), do: :ok
end
