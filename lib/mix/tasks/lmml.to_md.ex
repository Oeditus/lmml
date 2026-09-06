defmodule Mix.Tasks.Lmml.ToMd do
  use Mix.Task

  @shortdoc "Exports a bundle into standard, human-readable Markdown"

  @moduledoc """
  Opens a bundle and converts its embed syntaxes into standard Markdown
  placeholders, stripping inline fences and `@` sigils.

      mix lmml.to_md SOURCE [DEST]

  `DEST` defaults to `SOURCE` with its extension replaced by `.md`.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [source] -> do_to_md(source, default_dest(source, ".md"))
      [source, dest] -> do_to_md(source, dest)
      _ -> Mix.raise("Usage: mix lmml.to_md SOURCE [DEST]")
    end
  end

  defp do_to_md(source, dest) do
    bundle =
      try do
        Lmml.open!(source)
      rescue
        e -> Mix.raise("Failed to open #{source}: #{Exception.message(e)}")
      end

    md_content = Lmml.to_md(bundle)

    dest |> Path.dirname() |> File.mkdir_p!()
    File.write!(dest, md_content)

    Mix.shell().info("Exported #{source} -> #{dest}")
  rescue
    e -> Mix.raise("Failed to export #{source}: #{Exception.message(e)}")
  end

  defp default_dest(source, ext), do: Path.rootname(source, Path.extname(source)) <> ext
end
