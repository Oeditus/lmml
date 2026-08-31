defmodule Lmml.Narrative.Reference do
  @moduledoc """
  `Md.Transforms` implementation for the `@name.ext` external-reference
  magnet: turns a bare `@name.ext` mention into an `:lmml_ref` AST node
  carrying the raw referenced name, without assuming anything about what
  kind of file it points to (image, settings, arbitrary attachment).
  """
  @behaviour Md.Transforms

  @impl Md.Transforms
  def apply(_md, name), do: {:lmml_ref, %{name: name}, []}
end
