defmodule SpectreStudioWeb.AgentLive.Cache do
  @moduledoc """
  Per-Agent semantic-cache review, editing and explicit promotion.

  Runtime-learned examples remain quarantined until the host verifies them.
  Studio only requests edits and transitions; the host resolves the Agent
  module and calls its configured cache adapter under application authorization.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell
  import SpectreStudioWeb.StudioComponents

  alias SpectreStudio.Pulse.Scopes
  alias SpectreStudio.Pulse.StudioBridge
  alias SpectreStudioWeb.AgentLive.Shell

  @requirements {:any, [:semantic_cache_read, :semantic_cache_write, :semantic_cache_promote]}

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :cache, @requirements) do
      {:ok, socket} ->
        socket =
          socket
          |> assign(:examples, [])
          |> assign(:labels, [])
          |> assign(:editing_example_id, nil)
          |> assign(:edit_form, empty_edit_form())
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
    if Scopes.can?(socket.assigns.connection.manifest, :semantic_cache_read) do
      send_bridge(socket, :cache_examples, fn ->
        StudioBridge.cache_examples(socket.assigns.connection.id, socket.assigns.agent.address)
      end)
    else
      {:noreply, assign(socket, :error, "cache inspection is not granted")}
    end
  end

  def handle_event("edit", %{"id" => example_id}, socket) do
    example = Enum.find(socket.assigns.examples, &(&1["id"] == example_id))

    cond do
      not Scopes.can?(socket.assigns.connection.manifest, :semantic_cache_write) ->
        {:noreply, assign(socket, :error, "cache editing is not granted")}

      is_nil(example) ->
        {:noreply, assign(socket, :error, "cache example was not found")}

      example["editable?"] != true ->
        {:noreply, assign(socket, :error, "this cache example is read-only")}

      true ->
        form =
          to_form(
            %{"text" => example["text"] || "", "label" => example["label"] || ""},
            as: :example
          )

        {:noreply,
         socket
         |> assign(:editing_example_id, example_id)
         |> assign(:edit_form, form)
         |> assign(:error, nil)
         |> assign(:result, nil)}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_example_id, nil)
     |> assign(:edit_form, empty_edit_form())
     |> assign(:error, nil)}
  end

  def handle_event("update", %{"example" => attrs}, socket) when is_map(attrs) do
    example_id = socket.assigns.editing_example_id
    example = Enum.find(socket.assigns.examples, &(&1["id"] == example_id))
    text = Map.get(attrs, "text")
    label = Map.get(attrs, "label")
    socket = assign(socket, :edit_form, to_form(attrs, as: :example))

    cond do
      not Scopes.can?(socket.assigns.connection.manifest, :semantic_cache_write) ->
        {:noreply, assign(socket, :error, "cache editing is not granted")}

      is_nil(example) or example["editable?"] != true ->
        {:noreply, assign(socket, :error, "this cache example cannot be edited")}

      not is_binary(text) or String.trim(text) == "" ->
        {:noreply, assign(socket, :error, "example text cannot be blank")}

      not is_binary(label) or String.trim(label) == "" ->
        {:noreply, assign(socket, :error, "choose a cache category")}

      true ->
        send_bridge(socket, :cache_update, fn ->
          StudioBridge.update_cache_example(
            socket.assigns.connection.id,
            socket.assigns.agent.address,
            example_id,
            %{"text" => text, "label" => label}
          )
        end)
    end
  end

  def handle_event("update", _params, socket),
    do: {:noreply, assign(socket, :error, "invalid cache update")}

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
        examples = data |> Map.get("examples", []) |> normalize_examples()

        labels =
          data
          |> Map.get("labels", [])
          |> normalize_labels()
          |> Kernel.++(Enum.map(examples, & &1["label"]))
          |> normalize_labels()

        {:noreply,
         socket
         |> finish(request_id)
         |> assign(:examples, examples)
         |> assign(:labels, labels)
         |> assign(:editing_example_id, nil)
         |> assign(:edit_form, empty_edit_form())
         |> assign(:result, "loaded #{length(examples)} review candidates")}

      {:ok, request_id, :cache_update, data} ->
        example = Map.get(data, "example", data)

        if valid_example?(example) do
          examples = replace_example(socket.assigns.examples, example)
          labels = normalize_labels(socket.assigns.labels ++ [example["label"]])

          {:noreply,
           socket
           |> finish(request_id)
           |> assign(:examples, examples)
           |> assign(:labels, labels)
           |> assign(:editing_example_id, nil)
           |> assign(:edit_form, empty_edit_form())
           |> assign(:result, "example changes saved")}
        else
          {:noreply,
           socket
           |> finish(request_id)
           |> assign(:error, "invalid cache update response")}
        end

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
      |> assign(:can_write?, Scopes.can?(assigns.connection.manifest, :semantic_cache_write))
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
                Mutable online rows can be edited before promotion. Dataset and static rows stay
                read-only. Editing never verifies a row automatically.
              </p>
              <p class="mt-2 t-faint">
                Studio never loads the cache locally; the Agent host performs and authorizes each change.
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
                  <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                    <p class="term-label">{example["label"] || "unlabelled"}</p>
                    <p class="text-[0.68rem] t-faint">
                      {example["source"] || "unknown source"} · {if(example["editable?"] == true,
                        do: "editable",
                        else: "read-only"
                      )}
                    </p>
                  </div>

                  <.form
                    :if={@editing_example_id == example["id"]}
                    for={@edit_form}
                    id={"cache-edit-form-#{example["id"]}"}
                    phx-submit="update"
                    class="mt-4 min-w-[min(42rem,75vw)]"
                  >
                    <.input
                      field={@edit_form[:text]}
                      type="textarea"
                      label="Example text"
                      rows="3"
                      maxlength="8000"
                      required
                    />
                    <.input
                      field={@edit_form[:label]}
                      type="select"
                      label="Category"
                      options={label_options(@labels, example["label"])}
                      required
                    />
                    <div class="flex flex-wrap gap-3">
                      <.button id={"save-cache-#{example["id"]}"} type="submit" variant="primary">
                        save changes
                      </.button>
                      <.button
                        id={"cancel-cache-#{example["id"]}"}
                        type="button"
                        phx-click="cancel_edit"
                      >
                        cancel
                      </.button>
                    </div>
                  </.form>

                  <p
                    :if={@editing_example_id != example["id"]}
                    class="mt-2 break-words text-[0.78rem] leading-6 t-body"
                  >
                    {example["text"]}
                  </p>
                  <p class="mt-2 text-[0.7rem] t-faint">{example["id"]}</p>
                </div>
                <div class="flex flex-wrap items-center justify-end gap-3">
                  <.led state={if(example["verified?"], do: :ok, else: :wait)}>
                    {if(example["verified?"], do: "verified", else: "quarantined")}
                  </.led>
                  <.button
                    :if={
                      @can_write? and example["editable?"] == true and
                        @editing_example_id != example["id"]
                    }
                    id={"edit-#{example["id"]}"}
                    type="button"
                    phx-click="edit"
                    phx-value-id={example["id"]}
                  >
                    edit
                  </.button>
                  <.button
                    :if={@can_promote? and not example["verified?"]}
                    id={"verify-#{example["id"]}"}
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

  defp valid_example?(%{"id" => id}) when is_binary(id) and id != "", do: true
  defp valid_example?(_example), do: false

  defp normalize_examples(examples) when is_list(examples), do: Enum.filter(examples, &is_map/1)
  defp normalize_examples(_examples), do: []

  @spec empty_edit_form() :: Phoenix.HTML.Form.t()
  defp empty_edit_form do
    to_form(%{"text" => "", "label" => ""}, as: :example)
  end

  @spec normalize_labels(term()) :: [String.t()]
  defp normalize_labels(labels) when is_list(labels) do
    labels
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.uniq()
  end

  defp normalize_labels(_labels), do: []

  @spec label_options([String.t()], term()) :: [{String.t(), String.t()}]
  defp label_options(labels, current) do
    labels
    |> normalize_labels()
    |> then(fn labels ->
      if is_binary(current), do: Enum.uniq([current | labels]), else: labels
    end)
    |> Enum.map(&{&1, &1})
  end

  @spec pending_label(map()) :: String.t()
  defp pending_label(pending) when map_size(pending) == 0, do: "idle"
  defp pending_label(pending), do: "#{map_size(pending)} pending"

  @spec describe(term()) :: String.t()
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
