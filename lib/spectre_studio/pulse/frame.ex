defmodule SpectreStudio.Pulse.Frame do
  @moduledoc """
  The Pulse connection wire format, encoded and decoded by Studio itself.

  Studio deliberately does not depend on `spectre_pulse` to build these frames.
  Pulse is the server side of this conversation and it carries the whole Spectre
  runtime with it; an observer that compiles the observed system into itself can
  only ever talk to hosts running its own version. The frames are small, stable
  and versioned, so Studio speaks them directly and stays able to connect to a
  host whose Spectre differs from anything Studio was built against.

  Two planes travel over one socket:

    * connection control — `%{"pulse" => "connection", "version" => 1, ...}`,
      covering the manifest, receipts, errors and runtime monitoring;
    * ordinary Pulse envelopes addressed to an Agent.

  Reference: `spectre_pulse/docs/STUDIO_MONITORING.md` and
  `Spectre.Pulse.Phoenix.Frame`.
  """

  @protocol_version 1

  @monitor_kinds [:runtime, :operations]

  @type decoded ::
          {:manifest, map()}
          | {:receipt, map()}
          | {:error, map()}
          | {:monitor, :runtime | :operations, String.t(), map()}
          | {:envelope, map()}
          | {:unknown, map()}

  @doc "The connection protocol version Studio speaks."
  @spec protocol_version() :: pos_integer()
  def protocol_version, do: @protocol_version

  @doc """
  Decodes one text frame.

  Returns `{:error, :malformed}` rather than raising: a peer is free to send
  anything, and a control center must survive it.
  """
  @spec decode(binary()) :: {:ok, decoded()} | {:error, :malformed | :unsupported_version}
  def decode(frame) when is_binary(frame) do
    case Jason.decode(frame) do
      {:ok, value} when is_map(value) -> classify(value)
      _other -> {:error, :malformed}
    end
  end

  defp classify(%{"pulse" => "connection", "version" => version})
       when version != @protocol_version,
       do: {:error, :unsupported_version}

  defp classify(%{"pulse" => "connection", "type" => "manifest"} = value),
    do: {:ok, {:manifest, value}}

  defp classify(%{"pulse" => "connection", "type" => "receipt"} = value),
    do: {:ok, {:receipt, Map.get(value, "receipt", %{})}}

  defp classify(%{"pulse" => "connection", "type" => "error"} = value),
    do: {:ok, {:error, Map.get(value, "error", %{})}}

  defp classify(%{"pulse" => "connection", "type" => "agent.runtime.monitor." <> event} = value),
    do: {:ok, {:monitor, :runtime, event, value}}

  defp classify(
         %{"pulse" => "connection", "type" => "agent.operations.monitor." <> event} = value
       ),
       do: {:ok, {:monitor, :operations, event, value}}

  defp classify(%{"pulse" => "connection"} = value),
    do: {:ok, {:unknown, value}}

  defp classify(%{"payload" => _payload} = value),
    do: {:ok, {:envelope, value}}

  defp classify(value), do: {:ok, {:unknown, value}}

  @doc """
  Builds a `monitor.enable` frame.

  Studio generates `request_id` to correlate the reply. It never generates
  `subscription_id`: that is the server's, and inventing one locally would create
  a key that identifies nothing.
  """
  @spec monitor_enable(keyword()) :: {:ok, binary()} | {:error, term()}
  def monitor_enable(opts), do: monitor_enable(:runtime, opts)

  @doc "Builds an enable frame for OTP runtime or Work/Vigil monitoring."
  @spec monitor_enable(:runtime | :operations, keyword()) ::
          {:ok, binary()} | {:error, term()}
  def monitor_enable(kind, opts) when kind in @monitor_kinds and is_list(opts) do
    with {:ok, request_id} <- required_binary(opts, :request_id),
         {:ok, agent_address} <- required_binary(opts, :agent_address),
         {:ok, subject} <- required_binary(opts, :subject) do
      %{
        "pulse" => "connection",
        "version" => @protocol_version,
        "type" => monitor_type(kind, "enable"),
        "request_id" => request_id,
        "agent_address" => agent_address,
        "subject" => subject
      }
      |> put_present("interval_ms", Keyword.get(opts, :interval_ms))
      |> put_present("duration_ms", Keyword.get(opts, :duration_ms))
      |> put_monitor_options(kind, opts)
      |> encode()
    end
  end

  def monitor_enable(_kind, _opts), do: {:error, :invalid_monitor_kind}

  @doc "Builds a `monitor.disable` frame for a server-issued subscription id."
  @spec monitor_disable(String.t()) :: {:ok, binary()} | {:error, term()}
  def monitor_disable(subscription_id), do: monitor_disable(:runtime, subscription_id)

  @doc "Builds a disable frame for a typed server-issued subscription id."
  @spec monitor_disable(:runtime | :operations, String.t()) ::
          {:ok, binary()} | {:error, term()}
  def monitor_disable(kind, subscription_id)
      when kind in @monitor_kinds and is_binary(subscription_id) and subscription_id != "" do
    encode(%{
      "pulse" => "connection",
      "version" => @protocol_version,
      "type" => monitor_type(kind, "disable"),
      "subscription_id" => subscription_id
    })
  end

  def monitor_disable(_kind, _subscription_id), do: {:error, :invalid_monitor_subscription}

  @doc """
  Builds an ordinary Pulse envelope.

  Validated here, before the network, so a malformed message is reported to the
  operator as their own input error instead of coming back as a remote rejection.
  """
  @spec envelope(keyword()) :: {:ok, binary(), map()} | {:error, term()}
  def envelope(opts) do
    with {:ok, act} <- validate_act(Keyword.get(opts, :act)),
         {:ok, to} <- validate_address(Keyword.get(opts, :to)),
         {:ok, from} <- validate_address(Keyword.get(opts, :from)),
         {:ok, type} <- validate_payload_type(Keyword.get(opts, :payload_type)),
         {:ok, data} <- validate_data(Keyword.get(opts, :data, %{})) do
      envelope =
        %{
          "version" => @protocol_version,
          "id" => Keyword.get_lazy(opts, :id, &uuid7/0),
          "from" => from,
          "to" => to,
          "act" => act,
          "payload" => %{"type" => type, "data" => data},
          "metadata" => Keyword.get(opts, :metadata, %{})
        }
        |> put_present("relates_to", Keyword.get(opts, :relates_to))

      case encode(envelope) do
        {:ok, frame} -> {:ok, frame, envelope}
        error -> error
      end
    end
  end

  defp validate_act(act) when act in ["inform", "query", "request"], do: {:ok, act}
  defp validate_act(act) when act in [:inform, :query, :request], do: {:ok, Atom.to_string(act)}
  defp validate_act(_other), do: {:error, :invalid_act}

  defp validate_address("spectre://" <> rest = address) when byte_size(rest) > 0,
    do: {:ok, address}

  defp validate_address(_other), do: {:error, :invalid_address}

  defp validate_payload_type(type) when is_binary(type) and byte_size(type) > 0, do: {:ok, type}
  defp validate_payload_type(_other), do: {:error, :invalid_payload_type}

  defp validate_data(data) when is_map(data), do: {:ok, data}
  defp validate_data(_other), do: {:error, :invalid_payload_data}

  @doc "Encodes a map as a JSON frame."
  @spec encode(map()) :: {:ok, binary()} | {:error, term()}
  def encode(value) when is_map(value) do
    case Jason.encode(value) do
      {:ok, frame} -> {:ok, frame}
      {:error, _reason} -> {:error, :encoding_failed}
    end
  end

  @doc """
  Generates a UUIDv7, matching the identifier shape Spectre uses for envelopes.
  """
  @spec uuid7() :: String.t()
  def uuid7 do
    unix_ms = System.system_time(:millisecond)
    <<rand_a::12, rand_b::62, _rest::bits>> = :crypto.strong_rand_bytes(10)

    <<unix_ms::48, 7::4, rand_a::12, 2::2, rand_b::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  defp format_uuid(<<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>>),
    do: "#{a}-#{b}-#{c}-#{d}-#{e}"

  @spec put_monitor_options(map(), :runtime | :operations, keyword()) :: map()
  defp put_monitor_options(frame, :runtime, opts) do
    put_present(frame, "fields", Keyword.get(opts, :fields))
  end

  defp put_monitor_options(frame, :operations, opts) do
    frame
    |> put_present("kinds", Keyword.get(opts, :kinds))
    |> put_present("include_terminal", Keyword.get(opts, :include_terminal))
  end

  @spec monitor_type(:runtime | :operations, String.t()) :: String.t()
  defp monitor_type(kind, action), do: "agent.#{kind}.monitor.#{action}"

  @spec required_binary(keyword(), atom()) :: {:ok, String.t()} | {:error, term()}
  defp required_binary(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_monitor_field, key}}
    end
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, _key, []), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
