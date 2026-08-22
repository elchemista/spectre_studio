defmodule Mix.Tasks.Studio.Secrets do
  @moduledoc """
  Generates the vault key Spectre Studio requires in production.

      mix studio.secrets

  Prints a fresh 32-byte key. It is not written anywhere: copy it into the
  environment yourself.
  """

  @shortdoc "Generates the vault key that seals stored connection tokens"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("""

    STUDIO_VAULT_KEY='#{Base.encode64(:crypto.strong_rand_bytes(32))}'

    # This key seals the connection tokens stored in the vault. Rotating it
    # makes existing tokens unreadable: Studio keeps the endpoints and asks for
    # their tokens again rather than failing.
    """)
  end
end
