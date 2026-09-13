defmodule Jido.AI.Examples.Tools.AgentGuildPreflight do
  @moduledoc """
  Explicitly observes one caller-selected public HTTP(S) endpoint through Agent Guild.

  The selected URL is disclosed to the fixed Guild service, which actively probes it
  and may record the request. Supply a shareable public URL only. This action neither
  contacts that target directly nor attaches it to the agent for later execution.
  """

  use Jido.Action,
    name: "agent_guild_preflight",
    description:
      "Observe a selected public endpoint. Preserves failed and unknown checks; never authorizes delegation.",
    schema:
      Zoi.object(%{
        target: Zoi.string(description: "Explicitly selected shareable public HTTP(S) URL; no credentials.")
      })

  @doc "Returns bounded evidence or a fixed unavailable result, including on direct calls."
  @impl Jido.Action
  def run(params, _context), do: Jido.AI.Examples.Tools.AgentGuild.preflight(params)
end
