defmodule Lmml.Embed do
  @moduledoc """
  The one abstraction behind both `lmml` embedding syntaxes.

  `@name.ext` (a reference) and `@@@name.ext ... @@@` (an inline embed) are
  two different textual *renderings* of the exact same semantic idea:
  "this document contains a named embedded entity called `name.ext`."
  They differ only in where the entity's content actually lives:

    - `{:inline, binary}` -- the content is the embed's own text, captured
      directly from a `@@@name.ext ... @@@` block. Works in any `lmml`
      document, including a bare `.lmml` text file with no other files.
    - `{:external, entry_name}` -- the content lives elsewhere, referenced
      by `@entry_name` and resolved against a `.lmmlz` zip archive's
      entries. Meaningless (unresolvable) outside a zip container.

  `Lmml.Pack.pack/2` and `Lmml.Pack.inline/2` mechanically convert one
  form into the other; nothing about the embed's *meaning* changes.
  """

  @enforce_keys [:name, :content]
  defstruct [:name, :content]

  @typedoc "Where an embed's actual bytes live."
  @type content :: {:inline, binary()} | {:external, String.t()}

  @type t :: %__MODULE__{name: String.t(), content: content()}

  @doc "Builds an inline embed (content captured directly in the narrative)."
  @spec inline(String.t(), binary()) :: t()
  def inline(name, content) when is_binary(name) and is_binary(content) do
    %__MODULE__{name: name, content: {:inline, content}}
  end

  @doc """
  Builds an external embed (content resolved from a zip entry at read time).

  `entry_name` defaults to `name` itself when omitted or `nil`, so
  `external("a.png")` and `external("a.png", nil)` both resolve against
  a zip entry literally named `"a.png"`.
  """
  @spec external(String.t(), String.t() | nil) :: t()
  def external(name, entry_name \\ nil)

  def external(name, nil), do: external(name, name)

  def external(name, entry_name) when is_binary(name) and is_binary(entry_name) do
    %__MODULE__{name: name, content: {:external, entry_name}}
  end

  @doc "True when the embed's content is carried inline in the narrative itself."
  @spec inline?(t()) :: boolean()
  def inline?(%__MODULE__{content: {:inline, _}}), do: true
  def inline?(%__MODULE__{}), do: false

  @doc "True when the embed's content must be resolved against an external (zip) entry."
  @spec external?(t()) :: boolean()
  def external?(%__MODULE__{} = embed), do: not inline?(embed)
end
