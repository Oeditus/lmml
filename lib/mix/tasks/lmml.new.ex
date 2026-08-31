defmodule Mix.Tasks.Lmml.New do
  use Mix.Task

  @shortdoc "Creates a new, empty .lmml narrative file"

  @moduledoc """
  Creates a new, empty `.lmml` narrative file.

      mix lmml.new PATH

  `PATH` is normalized to end in `.lmml` if it doesn't already; any
  missing parent directories are created. Refuses to overwrite an
  existing file.

  ## Example

      mix lmml.new notes/meeting

  Creates `notes/meeting.lmml` containing a minimal starter narrative.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [raw_path] -> create(raw_path)
      _ -> Mix.raise("Usage: mix lmml.new PATH")
    end
  end

  defp create(raw_path) do
    path = normalize(raw_path, ".lmml")

    if File.exists?(path) do
      Mix.raise("Refusing to overwrite existing file: #{path}")
    end

    try do
      name = Path.basename(path, ".lmml")
      {:ok, bundle} = Lmml.Bundle.new_text(name, starter_narrative(name))

      path |> Path.dirname() |> File.mkdir_p!()
      Lmml.Bundle.write!(bundle, path)

      Mix.shell().info("Created #{path}")
    rescue
      e -> Mix.raise("Failed to create #{path}: #{Exception.message(e)}")
    end
  end

  defp normalize(path, ext) do
    if String.ends_with?(path, ext), do: path, else: path <> ext
  end

  defp starter_narrative(name) do
    """
    # #{name}

    Write your narrative here. Reference an external file with `@name.ext`,
    or embed one directly:

    @@@settings.yaml
    key: value
    @@@
    """
  end
end
