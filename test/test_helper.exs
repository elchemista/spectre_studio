Application.ensure_all_started(:spectre_studio)

# The vault is a file that outlives the suite. Emptying it here — rather than
# deleting it before boot, which would leave the running table pointing at a
# removed inode — keeps each run independent of the last.
Enum.each(SpectreStudio.Vault.list(), &SpectreStudio.Vault.delete(&1.id))

ExUnit.start()
