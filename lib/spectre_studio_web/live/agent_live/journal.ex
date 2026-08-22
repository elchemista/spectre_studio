defmodule SpectreStudioWeb.AgentLive.Journal do
  @moduledoc """
  Bounded persisted conversation turns exposed by the Agent host.

  This is distinct from the connection event log and from temporary OTP
  monitoring. The host reads its configured Spectre state adapter only after
  granting `ledger.read`; Studio retains no second copy after the LiveView ends.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell

  alias SpectreStudio.Pulse.Scopes
  alias SpectreStudio.Pulse.StudioBridge
  alias SpectreStudioWeb.AgentLive.Shell

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :journal, :ledger_read) do
      {:ok, socket} ->
        socket =
          socket
          |> assign(:turns, [])
          |> assign(:revision, nil)
          |> assign(:pending, %{})
          |> assign(:error, nil)
          |> assign(:selected_subject, nil)
          |> assign(:form, journal_form())

        if connected?(socket) and Scopes.can?(socket.assigns.connection.manifest, :runtime_read),
          do: send(self(), :discover_instances)

        {:ok, socket}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load", %{"journal" => params}, socket) do
    subject = params |> Map.get("subject", "") |> String.trim()

    if subject == "" do
      {:noreply, assign(socket, :error, "a conversation subject is required")}
    else
      {:noreply, load_subject(socket, subject, limit(params["limit"]))}
    end
  end

  @impl Phoenix.LiveView
  def handle_info(:discover_instances, socket) do
    case Shell.refresh_instances(socket) do
      {:ok, _request_id} -> {:noreply, socket}
      {:error, reason} -> {:noreply, assign(socket, :error, describe(reason))}
    end
  end

  def handle_info({:instances_changed, _id, address, instances}, socket)
      when address == socket.assigns.agent.address do
    socket = assign(socket, :instances, instances)

    case Shell.first_subject(instances) do
      nil -> {:noreply, socket}
      subject -> {:noreply, load_subject(socket, subject, 50)}
    end
  end

  def handle_info({:instances_failed, _id, address, error}, socket)
      when address == socket.assigns.agent.address,
      do: {:noreply, assign(socket, :error, describe(error))}

  def handle_info({:envelope, _connection_id, envelope}, socket) do
    case StudioBridge.response(envelope, socket.assigns.pending) do
      {:ok, request_id, :journal_turns, data} ->
        turns = data |> Map.get("turns", []) |> Enum.filter(&is_map/1)

        {:noreply,
         socket
         |> finish(request_id)
         |> assign(:turns, turns)
         |> assign(:revision, Map.get(data, "revision"))}

      {:error, request_id, reason} ->
        {:noreply, socket |> finish(request_id) |> assign(:error, describe(reason))}

      :unrelated ->
        {:noreply, maybe_refresh_from_event(socket, envelope)}
    end
  end

  def handle_info({:connection_status, _id, _status}, socket),
    do: {:noreply, Shell.reload(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

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

      <div class="mt-6 space-y-6">
        <.term_window title="turn journal" status={status(@pending, @turns)}>
          <p class="mb-5 text-[0.76rem] leading-6 t-dim">
            Follows the active Agent Instance automatically and reloads when the host reports a new
            turn or failure. A manual subject remains available for persisted conversations whose
            Instance is no longer alive.
          </p>

          <.form for={@form} id="journal-form" phx-submit="load" class="grid gap-4 sm:grid-cols-3">
            <div class="sm:col-span-2">
              <.input
                :if={@instances != []}
                field={@form[:subject]}
                type="select"
                label="live conversation"
                options={Enum.map(@instances, &{&1["subject"], &1["subject"]})}
              />
              <.input
                :if={@instances == []}
                field={@form[:subject]}
                label="persisted conversation subject"
                placeholder="waiting for a live Instance…"
              />
            </div>
            <.input
              field={@form[:limit]}
              type="select"
              label="turn limit"
              options={[{"20", "20"}, {"50", "50"}, {"100", "100"}]}
            />
            <div class="sm:col-span-3">
              <.button variant="primary">load journal</.button>
            </div>
          </.form>

          <p :if={@error} class="mt-4 term-out text-[0.75rem] t-fail">{@error}</p>
          <p :if={@revision} class="mt-4 term-comment text-[0.72rem] t-faint">
            subject {@selected_subject} · state revision {@revision}
          </p>
        </.term_window>

        <.term_window title="persisted turns" status={"#{length(@turns)}"}>
          <p :if={@turns == []} class="term-comment text-[0.78rem] t-faint">no turns loaded</p>

          <div id="journal-turns" class="space-y-5">
            <article
              :for={{turn, index} <- Enum.with_index(@turns)}
              id={"journal-turn-#{index}"}
              class="border border-[var(--border)] p-4"
            >
              <div class="flex flex-wrap justify-between gap-3 text-[0.7rem] t-faint">
                <span>{turn["at"] || "unknown time"}</span>
                <span>{turn["route"] || "unrouted"}</span>
              </div>
              <p class="mt-4 term-label">user</p>
              <pre class="mt-2 whitespace-pre-wrap break-words text-[0.78rem] t-body">{turn["user"]}</pre>
              <p class="mt-4 term-label">assistant</p>
              <pre class="mt-2 whitespace-pre-wrap break-words text-[0.78rem] t-body">{turn["assistant"]}</pre>
              <p :if={turn["events"] not in [nil, []]} class="mt-4 text-[0.7rem] t-faint">
                events: {Enum.join(turn["events"], ", ")}
              </p>
            </article>
          </div>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end

  @spec journal_form(map()) :: Phoenix.HTML.Form.t()
  defp journal_form(params \\ %{}) do
    to_form(
      %{
        "subject" => Map.get(params, "subject", ""),
        "limit" => Map.get(params, "limit", "50")
      },
      as: :journal
    )
  end

  @spec limit(String.t() | nil) :: pos_integer()
  defp limit(value) do
    case Integer.parse(value || "") do
      {limit, ""} when limit in [20, 50, 100] -> limit
      _invalid -> 50
    end
  end

  @spec finish(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp finish(socket, request_id) do
    assign(socket, pending: Map.delete(socket.assigns.pending, request_id), error: nil)
  end

  defp load_subject(socket, subject, turn_limit) do
    case StudioBridge.journal_turns(
           socket.assigns.connection.id,
           socket.assigns.agent.address,
           subject,
           turn_limit
         ) do
      {:ok, envelope} ->
        pending = Map.put(socket.assigns.pending, envelope["id"], :journal_turns)

        socket
        |> assign(:pending, pending)
        |> assign(:error, nil)
        |> assign(:selected_subject, subject)
        |> assign(:form, journal_form(%{"subject" => subject, "limit" => to_string(turn_limit)}))

      {:error, reason} ->
        assign(socket, :error, describe(reason))
    end
  end

  defp maybe_refresh_from_event(socket, envelope) do
    from = Map.get(envelope, "from")
    subject = get_in(envelope, ["payload", "data", "subject"])

    if from == socket.assigns.agent.address and is_binary(subject) and subject != "" do
      load_subject(socket, subject, 50)
    else
      socket
    end
  end

  @spec status(map(), [map()]) :: String.t()
  defp status(pending, _turns) when map_size(pending) > 0, do: "loading"
  defp status(_pending, turns), do: "#{length(turns)} turns"

  @spec describe(term()) :: String.t()
  defp describe(%{} = error), do: "#{error["kind"] || "request"}/#{error["code"] || "failed"}"
  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(reason), do: inspect(reason)
end
