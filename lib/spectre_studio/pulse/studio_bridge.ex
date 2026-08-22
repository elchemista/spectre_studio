defmodule SpectreStudio.Pulse.StudioBridge do
  @moduledoc """
  Studio-owned application operations transported by Pulse envelopes.

  Pulse carries and authenticates the envelope but deliberately does not own
  semantic cache, Skill runtime or Morph governance. A host that grants these
  scopes implements the corresponding payload handlers and remains responsible
  for subject resolution, authorization and every domain invariant.
  """

  alias SpectreStudio.Pulse.Connection

  @cache_examples "studio.semantic_cache.examples"
  @cache_verify "studio.semantic_cache.verify"
  @skill_mount "studio.skill.mount"
  @morph_propose "studio.morph.propose_skill"

  @type operation :: :cache_examples | :cache_verify | :skill_mount | :morph_propose

  @doc "Requests bounded semantic-cache review candidates for one Agent."
  @spec cache_examples(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def cache_examples(connection_id, agent_address) do
    query(connection_id, agent_address, @cache_examples, %{"source" => "online_learned"})
  end

  @doc "Requests verification and promotion of one quarantined cache example."
  @spec verify_cache_example(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def verify_cache_example(connection_id, agent_address, example_id)
      when is_binary(example_id) and example_id != "" do
    request(connection_id, agent_address, @cache_verify, %{"example_id" => example_id})
  end

  def verify_cache_example(_connection_id, _agent_address, _example_id),
    do: {:error, :invalid_example_id}

  @doc "Requests a host-governed runtime Skill mount for one Agent Instance."
  @spec mount_skill(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def mount_skill(connection_id, agent_address, attrs) when is_map(attrs) do
    request(connection_id, agent_address, @skill_mount, attrs)
  end

  def mount_skill(_connection_id, _agent_address, _attrs),
    do: {:error, :invalid_skill_mount}

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
  def operation(@cache_verify), do: :cache_verify
  def operation(@skill_mount), do: :skill_mount
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
