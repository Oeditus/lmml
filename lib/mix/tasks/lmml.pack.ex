defmodule Mix.Tasks.Lmml.Pack do
  use Mix.Task

  @shortdoc "Packs a bundle into a .lmmlz archive"

  @moduledoc """
  Externalizes every inline embed in a bundle into a real zip entry (see
  `Lmml.Pack.pack/2`), writing the result to a `.lmmlz` archive.

      mix lmml.pack SOURCE [DEST]

  `SOURCE` may be a bare `.lmml` text file or an existing `.lmmlz`
  archive (packing an archive is a safe, idempotent merge of its
  existing entries with any inline embeds it still carries). `DEST`
  defaults to `SOURCE` with its extension replaced by `.lmmlz`.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [source] -> do_pack(source, default_dest(source, ".lmmlz"))
      [source, dest] -> do_pack(source, dest)
      _ -> Mix.raise("Usage: mix lmml.pack SOURCE [DEST]")
    end
  end

  defp do_pack(source, dest) do
    bundle = Lmml.Bundle.open!(source)
    packed = Lmml.Pack.pack!(bundle)

    dest |> Path.dirname() |> File.mkdir_p!()
    Lmml.Bundle.write!(packed, dest)

    Mix.shell().info("Packed #{source} -> #{dest}")
  rescue
    e -> Mix.raise("Failed to pack #{source}: #{Exception.message(e)}")
  end

  defp default_dest(source, ext), do: Path.rootname(source, Path.extname(source)) <> ext
end
