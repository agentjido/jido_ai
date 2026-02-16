defmodule Jido.AI.Namespaces do
  @moduledoc """
  Canonical signal, action-spec, and telemetry namespace helpers for Jido.AI 2.0-beta.

  This module centralizes all runtime namespace strings to avoid scattering and
  drift during breaking-change migrations.
  """

  # Strategy query signals
  @react_query "ai.react.query"
  @cot_query "ai.cot.query"
  @tot_query "ai.tot.query"
  @got_query "ai.got.query"
  @trm_query "ai.trm.query"
  @adaptive_query "ai.adaptive.query"

  # ReAct control signals
  @react_cancel "ai.react.cancel"
  @react_register_tool "ai.react.register_tool"
  @react_unregister_tool "ai.react.unregister_tool"
  @react_set_tool_context "ai.react.set_tool_context"

  # Shared lifecycle signals
  @llm_request "ai.llm.request"
  @llm_response "ai.llm.response"
  @llm_delta "ai.llm.delta"
  @llm_error "ai.llm.error"
  @llm_cancelled "ai.llm.cancelled"

  @tool_call "ai.tool.call"
  @tool_result "ai.tool.result"
  @tool_error "ai.tool.error"

  @embed_request "ai.embed.request"
  @embed_result "ai.embed.result"
  @embed_error "ai.embed.error"

  @usage "ai.usage"

  @request_started "ai.request.started"
  @request_completed "ai.request.completed"
  @request_failed "ai.request.failed"
  @request_error "ai.request.error"

  @react_step "ai.react.step"

  @doc "Returns the ReAct query signal namespace."
  @spec react_query() :: String.t()
  def react_query, do: @react_query

  @doc "Returns the Chain-of-Thought query signal namespace."
  @spec cot_query() :: String.t()
  def cot_query, do: @cot_query

  @doc "Returns the Tree-of-Thoughts query signal namespace."
  @spec tot_query() :: String.t()
  def tot_query, do: @tot_query

  @doc "Returns the Graph-of-Thoughts query signal namespace."
  @spec got_query() :: String.t()
  def got_query, do: @got_query

  @doc "Returns the TRM query signal namespace."
  @spec trm_query() :: String.t()
  def trm_query, do: @trm_query

  @doc "Returns the Adaptive query signal namespace."
  @spec adaptive_query() :: String.t()
  def adaptive_query, do: @adaptive_query

  @doc "Returns the ReAct cancel control signal namespace."
  @spec react_cancel() :: String.t()
  def react_cancel, do: @react_cancel

  @doc "Returns the ReAct register-tool control signal namespace."
  @spec react_register_tool() :: String.t()
  def react_register_tool, do: @react_register_tool

  @doc "Returns the ReAct unregister-tool control signal namespace."
  @spec react_unregister_tool() :: String.t()
  def react_unregister_tool, do: @react_unregister_tool

  @doc "Returns the ReAct set-tool-context control signal namespace."
  @spec react_set_tool_context() :: String.t()
  def react_set_tool_context, do: @react_set_tool_context

  @doc "Returns the LLM request signal namespace."
  @spec llm_request() :: String.t()
  def llm_request, do: @llm_request

  @doc "Returns the LLM response signal namespace."
  @spec llm_response() :: String.t()
  def llm_response, do: @llm_response

  @doc "Returns the LLM delta signal namespace."
  @spec llm_delta() :: String.t()
  def llm_delta, do: @llm_delta

  @doc "Returns the LLM error signal namespace."
  @spec llm_error() :: String.t()
  def llm_error, do: @llm_error

  @doc "Returns the LLM cancelled signal namespace."
  @spec llm_cancelled() :: String.t()
  def llm_cancelled, do: @llm_cancelled

  @doc "Returns the tool call signal namespace."
  @spec tool_call() :: String.t()
  def tool_call, do: @tool_call

  @doc "Returns the tool result signal namespace."
  @spec tool_result() :: String.t()
  def tool_result, do: @tool_result

  @doc "Returns the tool error signal namespace."
  @spec tool_error() :: String.t()
  def tool_error, do: @tool_error

  @doc "Returns the embedding request signal namespace."
  @spec embed_request() :: String.t()
  def embed_request, do: @embed_request

  @doc "Returns the embedding result signal namespace."
  @spec embed_result() :: String.t()
  def embed_result, do: @embed_result

  @doc "Returns the embedding error signal namespace."
  @spec embed_error() :: String.t()
  def embed_error, do: @embed_error

  @doc "Returns the usage signal namespace."
  @spec usage() :: String.t()
  def usage, do: @usage

  @doc "Returns the request-started signal namespace."
  @spec request_started() :: String.t()
  def request_started, do: @request_started

  @doc "Returns the request-completed signal namespace."
  @spec request_completed() :: String.t()
  def request_completed, do: @request_completed

  @doc "Returns the request-failed signal namespace."
  @spec request_failed() :: String.t()
  def request_failed, do: @request_failed

  @doc "Returns the request-error signal namespace."
  @spec request_error() :: String.t()
  def request_error, do: @request_error

  @doc "Returns the ReAct step signal namespace."
  @spec react_step() :: String.t()
  def react_step, do: @react_step

  @doc "Returns all canonical signal namespaces as a flat list."
  @spec all_signals() :: [String.t()]
  def all_signals do
    [
      @react_query,
      @cot_query,
      @tot_query,
      @got_query,
      @trm_query,
      @adaptive_query,
      @react_cancel,
      @react_register_tool,
      @react_unregister_tool,
      @react_set_tool_context,
      @llm_request,
      @llm_response,
      @llm_delta,
      @llm_error,
      @llm_cancelled,
      @tool_call,
      @tool_result,
      @tool_error,
      @embed_request,
      @embed_result,
      @embed_error,
      @usage,
      @request_started,
      @request_completed,
      @request_failed,
      @request_error,
      @react_step
    ]
  end
end
