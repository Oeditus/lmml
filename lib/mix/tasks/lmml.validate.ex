defmodule Mix.Tasks.Lmml.Validate do
  use Mix.Task

  @shortdoc "Validates a bundle's references, entries, and embed names"

  @moduledoc """
  Cross-checks a bundle's narrative against its own entries and internal
  consistency (see `Lmml.Bundle.validate/1`), printing every issue found.

      mix lmml.validate SOURCE

  Exits with a non-zero status (via `Mix.raise/1`) if any issue is found,
  making this suitable for a CI check.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [source] -> do_validate(source)
      _ -> Mix.raise("Usage: mix lmml.validate SOURCE")
    end
  end

  defp do_validate(source) do
    case Lmml.Bundle.open(source) do
      {:ok, _bundle} ->
        Mix.shell().info("#{source}: OK")

      {:error, {:invalid_bundle, issues}} ->
        Enum.each(issues, fn issue ->
          Mix.shell().error("#{source}: " <> format_issue(issue))
        end)

        Mix.raise("#{source}: #{length(issues)} issue(s) found")

      {:error, reason} ->
        Mix.raise("Failed to open #{source}: #{inspect(reason)}")
    end
  end

  defp format_issue({:missing_reference, name}), do: "missing reference: @#{name}"
  defp format_issue({:orphaned_entry, name}), do: "orphaned zip entry: #{name}"
  defp format_issue({:malformed_embed_name, name}), do: "malformed embed name: #{name}"
  defp format_issue({:conflicting_embed, name}), do: "conflicting embed: #{name}"

  defp format_issue({:reserved_narrative_entry, name}),
    do: "embed collides with narrative entry: #{name}"

  defp format_issue({:invalid_narrative, reason}),
    do: "invalid narrative: #{inspect(reason)}"

  defp format_issue({:invalid_manifest, reason}),
    do: "invalid manifest.json: #{inspect(reason)}"

  defp format_issue({:invalid_settings, {name, reason}}),
    do: "invalid settings (#{name}): #{inspect(reason)}"
end
