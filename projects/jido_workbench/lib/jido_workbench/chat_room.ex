# defmodule JidoWorkbench.ChatRoom do
#   use Jido.Chat.Room
#   alias Jido.Chat.{Room, Participant}
#   require Logger

#   @agent_id Application.compile_env!(:jido_workbench, [:agent_jido, :room_id])
#   @room_id Application.compile_env!(:jido_workbench, [:agent_jido, :room_id])

#   def start_link(opts) do
#     room_opts = [
#       bus_name: Keyword.fetch!(opts, :bus_name),
#       room_id: @room_id,
#       registry: Jido.Chat.Registry,
#       module: __MODULE__
#     ]

#     case Room.start_link(room_opts) do
#       {:ok, pid} ->
#         with {:ok, jido} <- Participant.new(@agent_id, :agent, display_name: "Agent Jido"),
#              _ <- Room.add_participant(pid, jido),
#              {:ok, _} <- Room.post_message(pid, "Hello, I'm Jido, what's your name?", "jido") do
#           {:ok, pid}
#         else
#           error ->
#             Logger.error("Failed to initialize room: #{inspect(error)}")
#             error
#         end

#       error ->
#         error
#     end
#   end

#   def handle_join(_room, participant) do
#     Logger.debug("Participant joining: #{inspect(participant)}")
#     {:ok, participant}
#   end

#   def handle_leave(_room, participant) do
#     Logger.debug("Participant leaving: #{inspect(participant)}")
#     {:ok, participant}
#   end

#   def handle_message(_room, message) do
#     Logger.debug("Message received: #{inspect(message)}")
#     {:ok, message}
#   end
# end
