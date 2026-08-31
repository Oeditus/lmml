# Worked example: a multi-turn conversation narrative that references an
# image, packed into a `.lmmlz` archive, then resolved and rendered into
# the content-part shape a multimodal LLM chat completion API expects.
#
# Run with:
#
#     mix run examples/conversation_with_image.exs
#
# This writes `conversation.lmmlz` into the current directory so you can
# also inspect it directly (it's a real zip archive) or round-trip it
# with `mix lmml.inline conversation.lmmlz`.

alias Lmml.Bundle
alias Lmml.Narrative.Renderer
alias Lmml.Narrative.Resolver
alias Lmml.Pack

# A real (if tiny) 1x1 transparent PNG, so the example produces a
# genuinely valid image_url data URI, not a placeholder.
tiny_png =
  Base.decode64!(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
  )

narrative = """
# Debugging session

## Turn 1 -- user

Here is the failing screenshot: @screenshot.png

Can you tell what's wrong with the layout?

## Turn 2 -- assistant

The button is overflowing its container. Here's a suggested fix,
captured for the record:

@@@fix.diff
- padding: 24px;
+ padding: 12px;
@@@

## Turn 3 -- user

That worked, thanks!
"""

{:ok, bundle} = Bundle.new_zip("conversation", narrative, %{"screenshot.png" => tiny_png})

# Persist it as a real .lmmlz archive alongside this script.
:ok = Bundle.write!(bundle, "conversation.lmmlz")
IO.puts("Wrote conversation.lmmlz (#{byte_size(tiny_png)}-byte embedded image)")

# Cross-check it before using it for anything -- no dangling references,
# no orphaned entries.
:ok = Bundle.validate(bundle)
IO.puts("Validated: no issues found")

# Resolve every embed's actual bytes, then render the LLM-ready content
# parts: one verbatim "text" part, an "image_url" part for the
# screenshot (base64 data URI), and an "attachment" part for the inline
# diff.
{:ok, resolved} = Resolver.resolve(bundle)
parts = Renderer.render(resolved)

IO.puts("\nRendered #{length(parts)} content part(s):")

Enum.each(parts, fn
  %{"type" => "text", "text" => text} ->
    IO.puts("  - text (#{byte_size(text)} bytes)")

  %{"type" => "image_url", "image_url" => %{"url" => url}} ->
    IO.puts("  - image_url (#{byte_size(url)}-byte data URI)")

  %{"type" => "attachment", "name" => name, "mime" => mime} ->
    IO.puts("  - attachment #{name} (#{mime})")
end)

# Lmml.Pack.inline/2 only ever inlines text-like content -- a real image
# can't be spliced into UTF-8 narrative text, so it stays external. This
# bundle also has one already-inline, text-like embed (the diff), which
# packs and unpacks losslessly instead:
text_only_bundle_narrative = "See the fix below.\n\n@@@fix.diff\n- old\n+ new\n@@@"
{:ok, text_only_bundle} = Bundle.new_text("fix-only", text_only_bundle_narrative)

{:ok, packed_text} = Pack.pack(text_only_bundle)
{:ok, roundtripped} = Pack.inline(packed_text)

true = Bundle.embed(roundtripped, "fix.diff") == Bundle.embed(text_only_bundle, "fix.diff")
IO.puts("\nRound-trip (pack -> inline) preserved the text-like fix.diff embed.")

# Confirm the image itself is correctly rejected if you try to inline it:
case Pack.inline(bundle) do
  {:error, {"screenshot.png", :not_utf8}} ->
    IO.puts("As expected, inlining the binary screenshot.png was rejected (not_utf8).")
end
