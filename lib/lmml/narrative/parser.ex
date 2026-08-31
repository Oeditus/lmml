defmodule Lmml.Narrative.Parser do
  @moduledoc """
  The lmml narrative parser: everything `Md.Parser.Syntax`'s `Default`
  syntax module supports (headings, lists, emphasis, links, tables,
  standard fenced code, ...) plus `@name.ext` external references and
  `@@@name.ext ... @@@` inline embeds. See `Lmml.Narrative.Syntax` for
  exactly what's added/overridden.
  """
  alias Lmml.Narrative.Syntax

  use Md.Parser, syntax: Syntax.build()
end
