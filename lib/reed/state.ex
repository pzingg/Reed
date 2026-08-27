defmodule Reed.State do
  @moduledoc """
  The state tracked when reading an RSS stream with `Reed`.

  ## Fields

  ### Public Fields

  These fields are considered public and are passed to the pipeline transformation steps:
  * `:feed_info` - The feed-level metadata from the RSS feed. This will be collected before any items
    are parsed, and will be available during each transformation step.
  * `:current_item` - Always references stores the current item in the stream.
  * `:halted` - Whether to halt the stream after the current item is processed. Defaults to `false`.
  * `:private` - A private map field that can be used during the transformation pipeline. Defaults to an empty map.
  * `:flavor` - The detected RSS flavors, a "+"-delimited string, like "rss", "atom", or "json". Can include other
    detected extension namespaces, such as "itunes", "media", "podcast", and "youtube".

  ### Private Fields

  These fields are considered private and are used internally by `Reed` during the parsing
  process. These are NOT passed to the pipeline transformation functions.

  * `:feed_private` - We keep an "inflated" version of the feed elements, to handle the
    outlying case where an XML document might have a `channel` metadata element located
    after an `item` element. The RSS 2.0 specification says that "The `channel` also may
    contain zero or more `item` elements, which SHOULD appear after all of the other
    `channel` elements defined in this specification". The Atom 1.0 specification is more
    explicit that the : "[The] element children [of the `atom:feed` element] consist of
    metadata elements FOLLOWED BY zero or more `atom:entry` child elements."
  * `:current_text`
  * `:current_path`
  * `:transform`
  * `:normalize_rss`
  * `:chunks`
  """

  defstruct feed_private: %{},
            feed_info: %{},
            current_item: nil,
            halted: false,
            private: %{},
            current_text: "",
            current_path: [],
            xhtml_path: nil,
            xhtml: "",
            transform: nil,
            normalize_rss: false,
            chunks: nil,
            flavor: nil

  @type t :: %__MODULE__{
          feed_private: map(),
          feed_info: map(),
          current_item: nil | map(),
          halted: boolean(),
          private: map(),
          current_text: String.t(),
          current_path: list(),
          transform: nil | list(),
          normalize_rss: boolean(),
          chunks: nil | list(),
          flavor: nil | String.t()
        }
end
