defmodule SpectreStudioWeb.AgentLive.Messages do
  @moduledoc """
  Sending Pulse envelopes to one Agent, and what came back.

  The sent list is a stream: a receipt arriving updates one row instead of
  re-rendering a history that only ever grows.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell

  alias SpectreStudio.Pulse.Agent
  alias SpectreStudio.Pulse.Connection
  alias SpectreStudioWeb.AgentLive.Shell

  @acts [{"inform", "inform"}, {"query", "query"}, {"request", "request"}]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :messages) do
      {:ok, socket} ->
        sent = socket.assigns.connection.sent

        {:ok,
         socket
         |> assign(:acts, @acts)
         |> assign(:error, nil)
         |> assign(:sent_count, length(sent))
         |> assign(:form, message_form(socket.assigns.agent))
         |> stream(:sent, sent)}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("send", %{"message" => params}, socket) do
    with {:ok, data} <- decode_json(params["data"]),
         opts = [
           to: socket.assigns.agent.address,
           act: params["act"],
           payload_type: String.trim(params["payload_type"] || ""),
           data: data
         ],
         {:ok, _envelope} <- Connection.send_envelope(socket.assigns.connection.id, opts) do
      {:noreply,
       socket
       |> assign(:error, nil)
       |> assign(:form, message_form(socket.assigns.agent, params))}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, describe(reason))}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:envelope_sent, _id, entry}, socket) do
    {:noreply,
     socket
     |> stream_insert(:sent, entry, at: 0)
     |> update(:sent_count, &(&1 + 1))}
  end

  def handle_info({:envelope_receipt, _id, entry}, socket) do
    {:noreply, stream_insert(socket, :sent, entry)}
  end

  def handle_info({:connection_status, _id, _status}, socket),
    do: {:noreply, Shell.reload(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp message_form(agent, params \\ %{}) do
    to_form(
      %{
        "act" => Map.get(params, "act", "inform"),
        "payload_type" => Map.get(params, "payload_type", default_payload_type(agent)),
        "data" => Map.get(params, "data", "{}")
      },
      as: :message
    )
  end

  defp default_payload_type(%Agent{capabilities: [capability | _rest]}),
    do: "#{capability}.perform"

  defp default_payload_type(_agent), do: ""

  defp decode_json(value) when value in [nil, ""], do: {:ok, %{}}

  defp decode_json(value) do
    case Jason.decode(value) do
      {:ok, data} when is_map(data) -> {:ok, data}
      {:ok, _other} -> {:error, :payload_must_be_an_object}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp describe(:not_ready), do: "the connection is not ready"
  defp describe(:not_connected), do: "the socket is closed"
  defp describe(:invalid_json), do: "payload is not valid JSON"
  defp describe(:payload_must_be_an_object), do: "payload must be a JSON object"
  defp describe(:invalid_payload_type), do: "a payload type is required"
  defp describe(:invalid_act), do: "unknown act"
  defp describe(:unknown_studio_identity), do: "no manifest identity yet"
  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(reason), do: inspect(reason)

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      connections={@connections}
      active_section={@active_section}
      active_connection={@active_connection}
    >
      <.agent_header connection={@connection} agent={@agent} tab={@tab} />

      <div class="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_28rem]">
        <.term_window title="send envelope">
          <.form for={@form} id="message-form" phx-submit="send" class="space-y-4">
            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={@form[:act]} type="select" label="act" options={@acts} />
              <.input
                field={@form[:payload_type]}
                label="payload type"
                placeholder="research.perform"
              />
            </div>
            <.input field={@form[:data]} type="textarea" label="payload data (JSON)" rows="10" />
            <p :if={@error} class="term-out text-[0.75rem] t-fail">{@error}</p>
            <.button variant="primary">send</.button>
          </.form>
        </.term_window>

        <.term_window title="sent" status={"#{@sent_count}"}>
          <p :if={@sent_count == 0} class="term-comment text-[0.78rem] t-faint">
            nothing sent on this connection yet
          </p>

          <ul id="sent" phx-update="stream" class="term-list">
            <li :for={{dom_id, entry} <- @streams.sent} id={dom_id}>
              <span class="term-list__key">{entry.act} · {entry.type}</span>
              <span class={["term-list__value", receipt_tone(entry)]}>{receipt_label(entry)}</span>
            </li>
          </ul>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end

  defp receipt_label(%{receipt: nil}), do: "pending"
  defp receipt_label(%{receipt: receipt}), do: Map.get(receipt, "status", "accepted")

  defp receipt_tone(%{receipt: nil}), do: "t-dim"
  defp receipt_tone(_entry), do: "t-strong"
end
