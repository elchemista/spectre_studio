defmodule SpectreStudio.Pulse.StudioBridge do
  @moduledoc """
  Scoped Studio inspection operations transported by Pulse envelopes.

  Current Pulse terminates these requests at the authenticated connection
  boundary and projects Spectre-owned data without entering an Agent turn.
  Explicit manifest grants still decide which operations Studio may send.
  """

  alias SpectreStudio.Pulse.Connection

  @cache_examples "studio.semantic_cache.examples"
  @cache_update "studio.semantic_cache.update"
  @cache_verify "studio.semantic_cache.verify"
  @journal_turns "studio.journal.turns"
  @skills_list "studio.skills.list"
  @morph_propose "studio.morph.propose_skill"

  @type operation ::
          :cache_examples
          | :cache_update
          | :cache_verify
          | :journal_turns
          | :skills_list
          | :morph_propose

  @doc "Requests bounded semantic-cache review candidates for one Agent."
  @spec cache_examples(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def cache_examples(connection_id, agent_address) do
    query(connection_id, agent_address, @cache_examples, %{"source" => "online_learned"})
  end

  @doc "Requests an authorized text/category update for one mutable cache example."
  @spec update_cache_example(String.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def update_cache_example(connection_id, agent_address, example_id, attrs)
      when is_binary(example_id) and example_id != "" and is_map(attrs) do
    data =
      %{"example_id" => example_id}
      |> put_optional("text", Map.get(attrs, "text", Map.get(attrs, :text)))
      |> put_optional("label", Map.get(attrs, "label", Map.get(attrs, :label)))

    if map_size(data) > 1 do
      request(connection_id, agent_address, @cache_update, data)
    else
      {:error, :empty_cache_update}
    end
  end

  def update_cache_example(_connection_id, _agent_address, _example_id, _attrs),
    do: {:error, :invalid_cache_update}

  @doc "Requests verification and promotion of one quarantined cache example."
  @spec verify_cache_example(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def verify_cache_example(connection_id, agent_address, example_id)
      when is_binary(example_id) and example_id != "" do
    request(connection_id, agent_address, @cache_verify, %{"example_id" => example_id})
  end

  def verify_cache_example(_connection_id, _agent_address, _example_id),
    do: {:error, :invalid_example_id}

  @doc "Requests the bounded persisted turn journal for one conversation subject."
  @spec journal_turns(String.t(), String.t(), String.t(), pos_integer()) ::
          {:ok, map()} | {:error, term()}
  def journal_turns(connection_id, agent_address, subject, limit \\ 50)

  def journal_turns(connection_id, agent_address, subject, limit)
      when is_binary(subject) and subject != "" and is_integer(limit) and limit > 0 do
    query(connection_id, agent_address, @journal_turns, %{"subject" => subject, "limit" => limit})
  end

  def journal_turns(_connection_id, _agent_address, _subject, _limit),
    do: {:error, :invalid_journal_request}

  @doc "Requests the compiled and governed Skill inventory exposed by the host."
  @spec list_skills(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def list_skills(connection_id, agent_address) do
    query(connection_id, agent_address, @skills_list, %{})
  end

  @doc "Requests creation and evaluation of a governed Morph Skill proposal."
  @spec propose_morph_skill(String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def propose_morph_skill(connection_id, agent_address, attrs) when is_map(attrs) do
    request(connection_id, agent_address, @morph_propose, attrs)
  end

  def propose_morph_skill(_connection_id, _agent_address, _attrs),
    do: {:error, :invalid_morph_proposal}

  @doc "Returns the logical operation represented by a bridge payload type."
  @spec operation(String.t()) :: operation() | nil
  def operation(@cache_examples), do: :cache_examples
  def operation(@cache_update), do: :cache_update
  def operation(@cache_verify), do: :cache_verify
  def operation(@journal_turns), do: :journal_turns
  def operation(@skills_list), do: :skills_list
  def operation(@morph_propose), do: :morph_propose
  def operation(_type), do: nil

  @doc "Decodes a correlated result envelope without trusting arbitrary shapes."
  @spec response(map(), %{optional(String.t()) => operation()}) ::
          :unrelated | {:ok, String.t(), operation(), map()} | {:error, String.t(), term()}
  def response(envelope, pending) when is_map(envelope) and is_map(pending) do
    request_id = Map.get(envelope, "relates_to")

    case Map.fetch(pending, request_id) do
      {:ok, operation} -> decode_response(envelope, request_id, operation)
      :error -> :unrelated
    end
  end

  @spec query(String.t(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  defp query(connection_id, agent_address, payload_type, data) do
    Connection.send_envelope(connection_id,
      to: agent_address,
      act: :query,
      payload_type: payload_type,
      data: data
    )
  end

  @spec request(String.t(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  defp request(connection_id, agent_address, payload_type, data) do
    Connection.send_envelope(connection_id,
      to: agent_address,
      act: :request,
      payload_type: payload_type,
      data: data
    )
  end

  defp put_optional(data, _key, nil), do: data
  defp put_optional(data, key, value), do: Map.put(data, key, value)

  @spec decode_response(map(), String.t(), operation()) ::
          {:ok, String.t(), operation(), map()} | {:error, String.t(), term()}
  defp decode_response(envelope, request_id, operation) do
    type = get_in(envelope, ["payload", "type"])
    data = get_in(envelope, ["payload", "data"])

    cond do
      is_binary(type) and String.ends_with?(type, ".result") and is_map(data) ->
        {:ok, request_id, operation, data}

      is_binary(type) and String.ends_with?(type, ".error") ->
        {:error, request_id, if(is_map(data), do: data, else: :bridge_operation_failed)}

      true ->
        {:error, request_id, :invalid_bridge_response}
    end
  end
end
