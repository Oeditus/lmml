defmodule Lmml do
  @moduledoc """
  `lmml` is a markup format for talking to LLMs, designed as a strict
  superset of Markdown.

  A `.lmml` file is a self-contained narrative (Markdown-superset text).
  A `.lmmlz` file is the same narrative packed into a zip archive
  alongside the external files it references (its canonical narrative
  entry is named by stripping the trailing `z` from the archive's own
  filename, e.g. `foo.lmmlz` contains `foo.lmml`).

  Both forms express the same underlying model: an ordered narrative with
  zero or more named *embeds*, differing only in whether each embed's
  content is inline (`@@@name ... @@@`) or external (`@name`, resolved
  against the zip).

  See `Lmml.Narrative.Parser` for the narrative syntax itself.
  """
end
