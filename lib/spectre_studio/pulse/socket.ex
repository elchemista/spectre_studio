defmodule SpectreStudio.Pulse.Socket do
  @moduledoc """
  A WebSocket client for one Pulse endpoint.

  Pulse is explicitly the server half of this protocol — `Spectre.Pulse.Transports.WebSocket`
  states that Pulse does not own connection processes — so the client is Studio's
  to bring. This process owns exactly one socket and nothing else: it opens the
  connection, performs the upgrade, answers pings, and forwards decoded text
  frames to its owner. All protocol meaning lives in
  `SpectreStudio.Pulse.Connection`.

  Messages sent to the owner:

      {:pulse_socket, socket_pid, :open}
      {:pulse_socket, socket_pid, {:frame, text}}
      {:pulse_socket, socket_pid, {:closed, reason}}

  The socket never reconnects by itself. Reconnection is a policy decision with
  backoff and user-visible state, and it belongs to the connection process.
  """

  use GenServer, restart: :temporary

  @handshake_timeout 15_000

  defstruct [
    :owner,
    :uri,
    :headers,
    :transport_opts,
    :conn,
    :request_ref,
    :websocket,
    :status,
    :handshake_status,
    :handshake_headers,
    pending_data: []
  ]

  @doc """
  Starts a socket, unlinked from its owner.

  Deliberately not linked: a transport failure must degrade the connection, not
  take the process that owns its state, its manifest and its subscriptions down
  with it. The socket monitors its owner instead, so it still stops when the
  connection goes away.

  Options: `:owner`, `:url`, `:token`, `:verify_tls`.
  """
  @spec start(keyword()) :: GenServer.on_start()
  def start(opts), do: GenServer.start(__MODULE__, opts)

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Sends one text frame."
  @spec send_text(pid(), binary()) :: :ok | {:error, term()}
  def send_text(pid, text) when is_binary(text) do
    GenServer.call(pid, {:send_text, text}, 5_000)
  catch
    :exit, _reason -> {:error, :socket_unavailable}
  end

  @doc "Closes the socket politely, then stops."
  @spec close(pid()) :: :ok
  def close(pid) do
    GenServer.stop(pid, :normal, 1_000)
  catch
    :exit, _reason -> :ok
  end

  @impl GenServer
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    url = Keyword.fetch!(opts, :url)

    case parse_url(url, Keyword.get(opts, :token)) do
      {:ok, uri} ->
        state = %__MODULE__{
          owner: owner,
          uri: uri,
          headers: Keyword.get(opts, :headers, []),
          transport_opts: transport_opts(uri.scheme, Keyword.get(opts, :verify_tls, true)),
          status: :connecting
        }

        Process.monitor(owner)
        {:ok, state, {:continue, :connect}}

      {:error, reason} ->
        {:stop, {:shutdown, reason}}
    end
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    %{scheme: scheme, host: host, port: port} = state.uri

    with {:ok, conn} <-
           Mint.HTTP.connect(http_scheme(scheme), host, port,
             protocols: [:http1],
             transport_opts: state.transport_opts
           ),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(ws_scheme(scheme), conn, request_path(state.uri), state.headers) do
      Process.send_after(self(), :handshake_timeout, @handshake_timeout)
      {:noreply, %{state | conn: conn, request_ref: ref}}
    else
      {:error, reason} -> {:stop, {:shutdown, failure(reason)}, state}
      {:error, _conn, reason} -> {:stop, {:shutdown, failure(reason)}, state}
    end
  end

  @impl GenServer
  def handle_call({:send_text, _text}, _from, %{websocket: nil} = state) do
    {:reply, {:error, :not_open}, state}
  end

  def handle_call({:send_text, text}, _from, state) do
    case send_frame({:text, text}, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, state, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info(:handshake_timeout, %{status: :connecting} = state) do
    {:stop, {:shutdown, :handshake_timeout}, state}
  end

  def handle_info(:handshake_timeout, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, owner, _reason}, %{owner: owner} = state) do
    {:stop, :normal, state}
  end

  def handle_info(message, %{conn: conn} = state) when not is_nil(conn) do
    case Mint.WebSocket.stream(conn, message) do
      {:ok, conn, responses} ->
        handle_responses(responses, %{state | conn: conn})

      {:error, conn, reason, _responses} ->
        {:stop, {:shutdown, failure(reason)}, %{state | conn: conn}}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{conn: conn}) when not is_nil(conn) do
    Mint.HTTP.close(conn)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # --- responses -------------------------------------------------------------

  defp handle_responses([], state), do: {:noreply, state}

  defp handle_responses([{:status, ref, status} | rest], %{request_ref: ref} = state) do
    handle_responses(rest, %{state | handshake_status: status})
  end

  defp handle_responses([{:headers, ref, headers} | rest], %{request_ref: ref} = state) do
    handle_responses(rest, %{state | handshake_headers: headers})
  end

  defp handle_responses([{:done, ref} | rest], %{request_ref: ref} = state) do
    status = state.handshake_status
    headers = state.handshake_headers || []

    case Mint.WebSocket.new(state.conn, ref, status, headers) do
      {:ok, conn, websocket} ->
        send(state.owner, {:pulse_socket, self(), :open})
        state = %{state | conn: conn, websocket: websocket, status: :open}

        # A server that pushes immediately after the upgrade — Pulse sends the
        # manifest the moment it authenticates — can have its first frame arrive
        # in the same packet as the 101. Those bytes were held aside while the
        # websocket did not exist yet; they are decoded now rather than dropped.
        {buffered, state} = take_pending(state)

        case handle_frames_data(buffered, state) do
          {:ok, state} -> handle_responses(rest, state)
          {:stop, reason, state} -> {:stop, reason, state}
        end

      {:error, _conn, reason} ->
        {:stop, {:shutdown, upgrade_failure(status, reason)}, state}
    end
  end

  defp handle_responses([{:data, ref, data} | rest], %{request_ref: ref, websocket: nil} = state) do
    handle_responses(rest, %{state | pending_data: [data | state.pending_data]})
  end

  defp handle_responses([{:data, ref, data} | rest], %{request_ref: ref} = state) do
    case handle_frames_data(data, state) do
      {:ok, state} -> handle_responses(rest, state)
      {:stop, reason, state} -> {:stop, reason, state}
    end
  end

  defp handle_responses([_other | rest], state), do: handle_responses(rest, state)

  defp take_pending(state) do
    {state.pending_data |> Enum.reverse() |> IO.iodata_to_binary(), %{state | pending_data: []}}
  end

  defp handle_frames_data("", state), do: {:ok, state}

  defp handle_frames_data(data, state) do
    case Mint.WebSocket.decode(state.websocket, data) do
      {:ok, websocket, frames} ->
        handle_frames(frames, %{state | websocket: websocket})

      {:error, websocket, reason} ->
        {:stop, {:shutdown, failure(reason)}, %{state | websocket: websocket}}
    end
  end

  defp handle_frames([], state), do: {:ok, state}

  defp handle_frames([{:text, text} | rest], state) do
    send(state.owner, {:pulse_socket, self(), {:frame, text}})
    handle_frames(rest, state)
  end

  defp handle_frames([{:binary, _data} | rest], state) do
    # Pulse control frames and envelopes are JSON text. A binary frame is not
    # something Studio can interpret, and guessing at it would be worse than
    # ignoring it.
    handle_frames(rest, state)
  end

  defp handle_frames([{:ping, payload} | rest], state) do
    case send_frame({:pong, payload}, state) do
      {:ok, state} -> handle_frames(rest, state)
      {:error, state, reason} -> {:stop, {:shutdown, failure(reason)}, state}
    end
  end

  defp handle_frames([{:pong, _payload} | rest], state), do: handle_frames(rest, state)

  defp handle_frames([{:close, code, reason} | _rest], state) do
    {:stop, {:shutdown, {:closed, code, reason}}, state}
  end

  defp handle_frames([:close | _rest], state),
    do: {:stop, {:shutdown, {:closed, nil, nil}}, state}

  defp handle_frames([_other | rest], state), do: handle_frames(rest, state)

  defp send_frame(frame, state) do
    case Mint.WebSocket.encode(state.websocket, frame) do
      {:ok, websocket, data} ->
        state = %{state | websocket: websocket}

        case Mint.WebSocket.stream_request_body(state.conn, state.request_ref, data) do
          {:ok, conn} -> {:ok, %{state | conn: conn}}
          {:error, conn, reason} -> {:error, %{state | conn: conn}, failure(reason)}
        end

      {:error, websocket, reason} ->
        {:error, %{state | websocket: websocket}, failure(reason)}
    end
  end

  # --- helpers ---------------------------------------------------------------

  defp parse_url(url, token) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri when scheme in ["ws", "wss"] and is_binary(host) ->
        {:ok,
         %{uri | port: uri.port || default_port(scheme), query: merge_token(uri.query, token)}}

      _invalid ->
        {:error, :invalid_url}
    end
  end

  defp merge_token(query, nil), do: query

  defp merge_token(query, token) do
    (query || "")
    |> URI.decode_query()
    |> Map.put("token", token)
    |> URI.encode_query()
  end

  defp default_port("wss"), do: 443
  defp default_port("ws"), do: 80

  defp request_path(%URI{path: path, query: query}) do
    path = path || "/"
    if query in [nil, ""], do: path, else: path <> "?" <> query
  end

  defp http_scheme("wss"), do: :https
  defp http_scheme("ws"), do: :http

  defp ws_scheme("wss"), do: :wss
  defp ws_scheme("ws"), do: :ws

  # Certificate verification is on by default and only an explicit, per-endpoint
  # opt-out disables it. The UI marks such a connection as unverified, because
  # an observer that silently accepts any certificate is a credible way to hand
  # an operator's token to the wrong host.
  defp transport_opts("wss", true) do
    [
      verify: :verify_peer,
      cacertfile: CAStore.file_path(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  defp transport_opts("wss", false), do: [verify: :verify_none]
  defp transport_opts("ws", _verify), do: []

  defp upgrade_failure(status, _reason) when status in [401, 403], do: :unauthorized
  defp upgrade_failure(status, _reason) when is_integer(status), do: {:upgrade_failed, status}
  defp upgrade_failure(_status, reason), do: failure(reason)

  defp failure(%Mint.TransportError{reason: reason}), do: {:transport, reason}
  defp failure(%Mint.HTTPError{reason: reason}), do: {:http, reason}
  defp failure(%{reason: reason}), do: reason
  defp failure(reason), do: reason
end
