defmodule Mix.Tasks.Lmml.Inline do
  use Mix.Task

  @shortdoc "Inlines a bundle's external references into a bare .lmml file"

  @moduledoc """
  Inlines every external reference in a bundle into a `@@@name ... @@@`
  block (see `Lmml.Pack.inline/2`), writing the result to a bare `.lmml`
  text file.

      mix lmml.inline SOURCE [DEST]

  `SOURCE` is typically a `.lmmlz` archive. Fails outright if any
  external reference cannot be resolved, rather than writing a partial
  result. `DEST` defaults to `SOURCE` with its extension replaced by
  `.lmml`.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [source] -> do_inline(source, default_dest(source, ".lmml"))
      [source, dest] -> do_inline(source, dest)
      _ -> Mix.raise("Usage: mix lmml.inline SOURCE [DEST]")
    end
  end

  defp do_inline(source, dest) do
    bundle = Lmml.Bundle.open!(source)
    inlined = Lmml.Pack.inline!(bundle)

    dest |> Path.dirname() |> File.mkdir_p!()
    Lmml.Bundle.write!(inlined, dest)

    Mix.shell().info("Inlined #{source} -> #{dest}")
  rescue
    e -> Mix.raise("Failed to inline #{source}: #{Exception.message(e)}")
  end

  defp default_dest(source, ext), do: Path.rootname(source, Path.extname(source)) <> ext
end
