defmodule SpectreStudioWeb.Layouts do
  @moduledoc """
  Application shell for Spectre Studio.

  Studio is an operator tool, not a published site: the document layout carries
  no social metadata, no canonical URL and no indexable hints. What it does carry
  is the terminal shell — grid background, sticky header, navigation rail and a
  footer that reports the state of the session.
  """

  use SpectreStudioWeb, :html

  import SpectreStudioWeb.StudioComponents

  embed_templates "layouts/*"

  @app_name "spectre studio"

  @doc "The application name, used in the brand and the document title."
  def app_name, do: @app_name

  attr :flash, :map, required: true
  attr :connections, :list, default: []
  attr :active_section, :atom, default: nil
  attr :active_connection, :any, default: nil

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :session_summary, session_summary(assigns.connections))

    ~H"""
    <a href="#main-content" class="skip-link">Skip to content</a>
    <div class="site-shell flex min-h-screen flex-col">
      <header
        id="studio-header"
        class="sticky top-0 z-40 border-b border-[color:var(--line)] bg-[color:var(--surface-translucent)] backdrop-blur-xl"
      >
        <div class="mx-auto flex h-14 w-full max-w-[110rem] items-center gap-4 px-4 sm:px-6">
          <.link
            id="studio-brand"
            navigate={~p"/"}
            class="group flex min-w-0 items-center gap-3"
            aria-label="Spectre Studio home"
          >
            <span class="term-dots" aria-hidden="true">
              <span class="term-dot transition-colors group-hover:bg-[color:var(--fg-dim)]"></span>
              <span class="term-dot"></span>
              <span class="term-dot"></span>
            </span>
            <span class="truncate text-[0.82rem] tracking-tight">
              <span class="t-strong">spectre</span><span class="t-dim">@studio</span><span class="t-dim">:~$</span>
            </span>
            <.cursor class="hidden sm:inline-block" />
          </.link>

          <nav class="ml-auto flex items-center gap-2 text-[0.75rem]" aria-label="Session">
            <.theme_toggle />
          </nav>
        </div>
      </header>

      <div class="mx-auto flex w-full max-w-[110rem] flex-1 flex-col gap-0 px-4 sm:px-6 lg:flex-row lg:gap-8">
        <aside class="border-b border-[color:var(--line)] py-4 lg:w-52 lg:flex-none lg:border-b-0 lg:border-r lg:py-8 lg:pr-6">
          <.rail>
            <:group label="./connections" />
            <:item
              :for={connection <- @connections}
              navigate={~p"/connections/#{connection.id}"}
              current={@active_connection == connection.id}
              state={connection.state}
            >
              {connection.label}
            </:item>
            <:item navigate={~p"/"} current={@active_section == :connections}>
              ./all
            </:item>
            <:group label="./lab" />
            <:item navigate={~p"/lab"} current={@active_section == :lab}>./bundles</:item>
          </.rail>
        </aside>

        <main id="main-content" tabindex="-1" class="min-w-0 flex-1 py-6 lg:py-8">
          {render_slot(@inner_block)}
        </main>
      </div>

      <footer id="studio-footer" class="border-t border-[color:var(--line)]">
        <div class="mx-auto flex w-full max-w-[110rem] flex-wrap items-center gap-x-5 gap-y-2 px-4 py-5 text-[0.72rem] t-faint sm:px-6">
          <span class="term-prompt">
            echo "{@session_summary}"
          </span>
          <span class="ml-auto flex items-center gap-2">
            <span class="size-1.5 rounded-full bg-[color:var(--fg-dim)]"></span> exit status 0
          </span>
        </div>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed right-4 top-[4.25rem] z-50 flex w-[calc(100vw-2rem)] flex-col gap-3 sm:right-6 sm:w-96"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Connection lost"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Reconnecting <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Retrying in a moment
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <button
      id="theme-toggle"
      type="button"
      data-theme-toggle
      class="flex size-8 cursor-pointer items-center justify-center rounded border border-[color:var(--line)] t-dim transition hover:border-[color:var(--line-strong)] hover:t-strong"
      aria-label="Toggle colour theme"
      title="Toggle colour theme"
    >
      <.icon name="hero-sun" class="size-3.5 dark:hidden" />
      <.icon name="hero-moon" class="hidden size-3.5 dark:block" />
    </button>
    """
  end

  # Reports what the session is actually holding, in the shell's own voice.
  defp session_summary([]), do: "spectre studio — no connections configured"

  defp session_summary(connections) do
    ready = Enum.count(connections, &(&1.state == :ok))
    "spectre studio — #{length(connections)} connections, #{ready} ready"
  end

  @doc "Builds the document title."
  def document_title(nil), do: @app_name
  def document_title(title), do: "#{title} · #{@app_name}"
end
