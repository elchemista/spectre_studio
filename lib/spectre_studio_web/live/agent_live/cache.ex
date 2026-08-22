defmodule SpectreStudioWeb.AgentLive.Cache do
  @moduledoc """
  Per-Agent semantic-cache review and explicit promotion.

  Runtime-learned examples remain quarantined until the host verifies them.
  Studio only requests the transition; the host resolves the Agent module and
  calls its configured cache adapter under application authorization.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell
  import SpectreStudioWeb.StudioComponents

  alias SpectreStudio.Pulse.Scopes
  alias SpectreStudio.Pulse.StudioBridge
  alias SpectreStudioWeb.AgentLive.Shell

  @requirements {:any, [:semantic_cache_read, :semantic_cache_promote]}

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :cache, @requirements) do
      {:ok, socket} ->
        socket =
          socket
          |> assign(:examples, [])
          |> assign(:pending, %{})
          |> assign(:error, nil)
          |> assign(:result, nil)

        if connected?(socket) and
             Scopes.can?(socket.assigns.connection.manifest, :semantic_cache_read),
           do: send(self(), :load_cache)

        {:ok, socket}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket) do
    send_bridge(socket, :cache_examples, fn ->
      StudioBridge.cache_examples(socket.assigns.connection.id, socket.assigns.agent.address)
    end)
  end

  def handle_event("verify", %{"id" => example_id}, socket) do
    if Scopes.can?(socket.assigns.connection.manifest, :semantic_cache_promote) do
      send_bridge(socket, :cache_verify, fn ->
        StudioBridge.verify_cache_example(
          socket.assigns.connection.id,
          socket.assigns.agent.address,
          example_id
        )
      end)
    else
      {:noreply, assign(socket, :error, "cache promotion is not granted")}
    end
  end

  @impl Phoenix.LiveView
  def handle_info(:load_cache, socket) do
    send_bridge(socket, :cache_examples, fn ->
      StudioBridge.cache_examples(socket.assigns.connection.id, socket.assigns.agent.address)
    end)
  end

  def handle_info({:envelope, _connection_id, envelope}, socket) do
    case StudioBridge.response(envelope, socket.assigns.pending) do
      {:ok, request_id, :cache_examples, data} ->
        examples = data |> Map.get("examples", []) |> Enum.filter(&is_map/1)

        {:noreply,
         socket
         |> finish(request_id)
         |> assign(:examples, examples)
         |> assign(:result, "loaded #{length(examples)} review candidates")}

      {:ok, request_id, :cache_verify, data} ->
        example = Map.get(data, "example", data)

        {:noreply,
         socket
         |> finish(request_id)
         |> assign(:examples, replace_example(socket.assigns.examples, example))
         |> assign(:result, "example verified and promoted")}

      {:error, request_id, reason} ->
        {:noreply, socket |> finish(request_id) |> assign(:error, describe(reason))}

      :unrelated ->
        {:noreply, socket}
    end
  end

  def handle_info({:connection_status, _id, _status}, socket),
    do: {:noreply, Shell.reload(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def render(assigns) do
    assigns =
      assigns
      |> assign(:can_read?, Scopes.can?(assigns.connection.manifest, :semantic_cache_read))
      |> assign(:can_promote?, Scopes.can?(assigns.connection.manifest, :semantic_cache_promote))

    ~H"""
    <Layouts.app
      flash={@flash}
      connections={@connections}
      active_section={@active_section}
      active_connection={@active_connection}
    >
      <.agent_header connection={@connection} agent={@agent} tab={@tab} />

      <div class="mt-6">
        <.term_window title="semantic cache review" status={pending_label(@pending)}>
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div class="max-w-3xl text-[0.76rem] leading-6 t-dim">
              <p>
                Online-learned rows are quarantined until explicitly verified. Verification is the
                promotion step that makes a row eligible for normal exact and semantic lookup.
              </p>
              <p class="mt-2 t-faint">
                Studio never loads the cache locally; the Agent host performs and authorizes the change.
              </p>
              <p :if={!@can_read?} class="mt-2 t-fail">
                inspection locked — missing agent.semantic_cache.read
              </p>
            </div>
            <.button :if={@can_read?} type="button" phx-click="refresh">refresh candidates</.button>
          </div>

          <p :if={@error} class="mt-4 term-out text-[0.75rem] t-fail">{@error}</p>
          <p :if={@result} class="mt-4 term-out text-[0.75rem] t-ok">{@result}</p>

          <p :if={@examples == []} class="mt-6 term-comment text-[0.78rem] t-faint">
            no candidates loaded
          </p>

          <div id="cache-examples" class="mt-6 space-y-4">
            <article
              :for={example <- @examples}
              id={"cache-example-#{example["id"]}"}
              class="border border-[var(--border)] p-4"
            >
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="min-w-0">
                  <p class="term-label">{example["label"] || "unlabelled"}</p>
                  <p class="mt-2 break-words text-[0.78rem] leading-6 t-body">{example["text"]}</p>
                  <p class="mt-2 text-[0.7rem] t-faint">{example["id"]}</p>
                </div>
                <div class="flex items-center gap-3">
                  <.led state={if(example["verified?"], do: :ok, else: :wait)}>
                    {if(example["verified?"], do: "verified", else: "quarantined")}
                  </.led>
                  <.button
                    :if={@can_promote? and not example["verified?"]}
                    type="button"
                    phx-click="verify"
                    phx-value-id={example["id"]}
                    variant="primary"
                  >
                    verify + promote
                  </.button>
                </div>
              </div>
            </article>
          </div>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end

  @spec send_bridge(Phoenix.LiveView.Socket.t(), StudioBridge.operation(), (-> term())) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp send_bridge(socket, operation, fun) do
    case fun.() do
      {:ok, envelope} ->
        pending = Map.put(socket.assigns.pending, envelope["id"], operation)
        {:noreply, assign(socket, pending: pending, error: nil, result: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, describe(reason))}
    end
  end

  @spec finish(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp finish(socket, request_id) do
    assign(socket, pending: Map.delete(socket.assigns.pending, request_id), error: nil)
  end

  @spec replace_example([map()], map()) :: [map()]
  defp replace_example(examples, %{"id" => id} = updated) do
    case Enum.find_index(examples, &(&1["id"] == id)) do
      nil -> [updated | examples]
      index -> List.replace_at(examples, index, updated)
    end
  end

  defp replace_example(examples, _invalid), do: examples

  @spec pending_label(map()) :: String.t()
  defp pending_label(pending) when map_size(pending) == 0, do: "idle"
  defp pending_label(pending), do: "#{map_size(pending)} pending"

  @spec describe(term()) :: String.t()
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
