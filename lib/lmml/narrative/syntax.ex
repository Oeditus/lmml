defmodule Lmml.Narrative.Syntax do
  @moduledoc """
  Builds the `Md` syntax map used by `Lmml.Narrative.Parser`: `Md.Parser.Syntax`'s
  `Default` syntax module's prose/structure categories, plus lmml's own
  additions/overrides.

  Two additions on top of Default:

  - `magnet: "@"` is *overridden* (same category, same prefix key, so
    `Md.Parser.Syntax.merge/2` replaces Default's `TwitterHandle` transform
    with ours) to produce an `:lmml_ref` node instead of a Twitter link.
  - `block: "@@@"` is *added* (a new prefix key in the `block` category,
    alongside Default's ` ``` ` fenced-code entry) to produce an
    `:lmml_embed` node for inline embeds, with `escape: false` so its
    content is carried through verbatim instead of `Md`'s default
    HTML-entity escaping (see `Md` >= 0.12.2's `block:` `escape:` property).

  Both live in different categories than each other, and `Md`'s engine
  compiles `block` clauses before `magnet` clauses, so a `"@@@..."` input
  is tried against the (longer, more specific) block entry first and only
  falls through to the single-`"@"` magnet entry when it isn't a `"@@@"`
  sequence -- no custom dispatcher needed for this to be unambiguous.
  """

  alias Md.Parser.Syntax
  alias Md.Parser.Syntax.Default

  @custom %{
    # `Md.Parser.Syntax.merge/2` merges `:settings` with `Map.merge/2`, which
    # *replaces* a key's whole value rather than concatenating it -- so
    # `empty_tags` here must include Default's own entries too, not just
    # lmml's additions, or `:img`/`:hr`/`:br` would silently stop being
    # treated as legitimately childless tags.
    settings: %{empty_tags: Default.settings().empty_tags ++ [:lmml_ref, :lmml_embed]},
    magnet: [
      {"@",
       %{
         transform: &Lmml.Narrative.Reference.apply/2,
         # Deliberately no `terminators:` override -- the default,
         # `:ascii_punctuation`, stops the reference at *any* ASCII
         # punctuation character (comma, period, closing bracket,
         # asterisk, underscore, backtick, ...), matching how the
         # reference is meant to be used inline among ordinary prose and
         # markdown emphasis markers without swallowing them.
         ignore_in: [:img, :a, :lmml_ref, :lmml_embed]
       }}
    ],
    block: [
      {"@@@",
       %{
         tag: :lmml_embed,
         pop: %{lmml_embed: [attribute: :name, prefixes: [""]]},
         escape: false
       }}
    ]
  }

  @doc "Builds the final syntax map: Default plus lmml's overrides/additions."
  def build, do: Syntax.merge(@custom, Map.put(Default.syntax(), :settings, Default.settings()))
end
