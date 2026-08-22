defmodule SpectreStudioWeb.ErrorHTML do
  @moduledoc """
  Error pages, rendered in the same terminal language as the rest of Studio.

  A stray URL is an ordinary event in an operator tool — panels get bookmarked,
  connections get removed — so the page that reports it should look like part of
  the application and offer the way back, not read as a crash.
  """

  use SpectreStudioWeb, :html

  embed_templates "error_html/*"

  @doc "Renders any status without its own template as a styled shell page."
  def render(template, assigns) do
    status = Phoenix.Controller.status_message_from_template(template)
    code = template |> String.split(".") |> List.first()

    assigns
    |> Map.put(:status, status)
    |> Map.put(:code, code)
    |> generic()
  end

  attr :code, :string, required: true
  attr :status, :string, required: true

  defp generic(assigns) do
    ~H"""
    <.error_shell code={@code} status={@status}>
      <p class="term-out text-[0.8rem] t-dim">the request could not be completed</p>
    </.error_shell>
    """
  end

  @doc "The shared frame every error page uses."
  attr :code, :string, required: true
  attr :status, :string, required: true
  slot :inner_block, required: true

  def error_shell(assigns) do
    ~H"""
    <div class="site-shell flex min-h-screen items-center justify-center px-4 py-16">
      <div class="w-full max-w-xl">
        <.term_window title={"exit #{@code}"} status="spectre studio" class="overflow-hidden">
          <p class="term-prompt text-[0.72rem] t-faint">studio --status {@code}</p>
          <h1 class="mt-4 text-xl font-bold tracking-tight t-strong">{@status}</h1>

          <div class="mt-4 space-y-2">
            {render_slot(@inner_block)}
          </div>

          <div class="mt-7 flex flex-wrap gap-2">
            <.link navigate="/" class="term-btn term-btn--primary">./dashboard</.link>
            <.link navigate="/lab" class="term-btn">./lab</.link>
          </div>
        </.term_window>
      </div>
    </div>
    """
  end
end
