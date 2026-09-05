# Reed

[![Reed version](https://img.shields.io/hexpm/v/reed.svg)](https://hex.pm/packages/reed)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/reed/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/reed)](https://hex.pm/packages/reed)
[![Twitter Follow](https://img.shields.io/twitter/follow/ac_alejos?style=social)](https://twitter.com/ac_alejos)
<!-- BEGIN MODULEDOC -->

Streaming RSS parser with a built-in `Req` plugin for network-enabled chunked streaming.

## Installation

```elixir
def deps do
  [
    {:reed, "~> 0.2.0"}
  ]
end
```

## Rationale

`Reed` implements a Sax-based parser for RSS feeds using the [`Saxy`](https://github.com/qcam/saxy) library.

You can manually use the `Reed.Handler` (which implements the `Saxy.Handler` behaviour) with `Saxy` to parse
strings or from `Stream`s, but the killer feature of `Reed` is the `Reed.ReqPlugin` module, which powers the top-level
`Reed.get/2` / `Reed.get!/2` API functions.

`Reed` began as a need for a way to read RSS feeds by first reading the feed-level metadata followed
by item-by-item streaming without loading the entire feed into memory, all while doing so from a remote URL.

`Reed` combines the `Saxy.Partial` module with `Req`'s streaming `:into` option to do just that.

`Reed.ReqPlugin` takes advantage of `Req`'s chunking capability to parse RSS feeds directly from over the network, applying
transformation functions to each RSS item lazily.

`Reed.StreamHandler` uses `Saxy.parse_stream/4` as an alternative method when you want to parse a traditional Elixir
`Stream`, with data from a file or string IO. To parse a stream, use the `Reed.stream/2` API function (which delegates to
`Reed.StreamHandler.parse/2`).

## Parsing other feed formats

In addition to parsing XML feed formats (such as standard [Atom](https://www.ietf.org/rfc/rfc4287.txt)
and [RSS 2.0](https://www.rssboard.org/rss-specification)), `Reed` can also detect and parse other
feed formats:

  * [JSON Feed](https://www.jsonfeed.org/version/1.1/) and
  * [microformats 2 h-feed/h-entry elements in HTML](https://microformats.org/wiki/h-feed)

Detection of the appropriate format is done transparently by `Reed.get/2`, `Reed.get!/2` and `Reed.stream/2`.
Note that the JSON and h-feed/h-entry parsers cannot parse streams directly, so chunked or streamed data
is simply accumulated and then post-processed as a single document.

## Transformers

The `Reed.Transformers` module provides some convenient transformation functions to be used during the parsing.

The transformation pipeline is invoked whenever a new RSS item is read, and works with an accumulating state that persists
during the entire RSS read.

`Reed` provides a dead-simple API that also allows for flexible handling of items during the stream through
the use of transformation pipelines (see `Reed.Transformers`).  These pipelines define how to handle the item
stream, and function as a reduction over an input state containing feed-level metadata, the current item, and
a private field where you can store other data.

The state also maintains a `:halted` field that controls whether to halt the stream after the current item has been
processed (had the whole `:transform` pipeline applied).

You can also control when to move on to the next item during a transformation pipeline by returning either `:halt`
or `{:halt, state}` from any step in the transformation pipeline (see `Reed.Transformers.filter/2` for an example).

Normally, you include `Reed.Transformers.collect/1` in the pipeline, which takes the (possibly transformed)
current item and prepends it to the `:items` list inside the `:private` field of the state. When parsing is completed
or halted, these collected `:items` are reversed so that they will appear in the correct order in the final state.

You can compose the built-in pipeline function from `Reed.Transformers` or create your own unique steps to create very
simple yet powerful parsing instructions to carefully read only the exact parts of the RSS stream that you're interested in.

## A note on parsed XML feed and item data

`Reed.Handler` collects feed and item data into an accumulating state. Both the `:feed_info` and the `:current_item`
fields of the state are Elixir maps, with string keys taken verbatim from the XML tag name. Since some XML tags
(such as `<link>`) may occur multiple times in a feed or item, values for these keys may appear as a list rather than
a single text or map.

If a parsed XML tag has only text content and no attributes or child tags, then the value of the tag will just be
a scalar string containing the text.

If the tag has attributes or child tags, but no text content, the value of the tag will be an Elixir map with
the keys being the attribute and child tag names.

In the case where the tag has "mixed content" (that is, text content interspersed with optional child tags)
or text content and attributes, the concatenated text content will be found in a "\_text\_" field in the tag's map,
along with the other attribute and child tag fields.

## Normalization and "basic" feed data

The `Reed.Basic` modules attempt to capture feed information from the various flavors of RSS that exist in the
wild into standardized data structures. If the keyword option `:normalize_rss` is set to `true` for any of the
`Reed` API calls, a post-parsing normalization step will be applied to the `:feed_info` and `:private` `:items`
fields of the final state, resulting in data being converted into `Reed.Basic.Feed`, `Item`, `Link`, and `Attachment`
structs. For feed items to be normalized this way, you must specify `Reed.Transformers.collect/1` in the
transformation pipeline, and you should not transform item data other than limiting or filtering items with,
for example, `Reed.Transformers.limit/2` or `Reed.Transformers.filter/2`.

### Reed.Basic transformer coverage

The table below shows the basic attributes that are collected by the `Reed.Basic.Transformer` module
and standardized in the `Reed.Basic.Feed`, `Item`, `Link` and `Attachment` structs. See the specifications 
for the Atom, RSS 2.0, and Microformats mentioned above for more information.

In addition, attributes from other commonly used namespaces that are parsed by the `Transformer` module include:

["dc:creator" from the Dublin Core namespace](https://www.dublincore.org/specifications/dublin-core/dcmi-terms/)
["source:self" from the RSS 2.0 "source" namespace](https://source.scripting.com/)
["podcast:guid" from the Podcasting 2.0 namespace](https://podcasting2.org/docs/podcast-namespace/1.0)
[Several "media:" attributes from the Media RSS namespace](https://www.rssboard.org/media-rss)
[Several "itunes:" attributes from the Apple Podcasts specification](https://help.apple.com/itc/podcasts_connect/#/itcb54353390)

Attributes that are not explicitly parsed into the `Reed.Basic` structs are available for clients
in the `data` element of each struct.

`Reed.Basic.Feed` attributes:

| RSS            | Atom           | JSON          | Microformats | Feed field |
| -------------- | -------------- | ------------- | -------- | ---------- |
|                | author+        | authors       |          | author     |
|                | contributor+   |               |          | author     |
|                | id*            |               |          | id         |
| image          |                |               |          | image      |
| link           | link/other     |               | rel-urls | links      |
| language       |                | language      |          | language   |
|                | subtitle       |               |          | subtitle   |
| description*   |                | description   |          | summary    |
| title*         | title*         | title*        | name     | title      |
| pubDate        | updated*       |               |          | updated    |
|                | link/self      | feed_url      |          | links      |
|                | link/alternate |               |          | links      |
| items*         | entries*       |               |          | items      |
| category       | category+      |               |          |            |
| generator      | generator      |               |          |            |
| copyright      | rights         |               |          |            |
| cloud          |                |               |          |            |
| docs           |                |               |          |            |
| lastBuildDate  |                |               |          |            |
| managingEditor |                |               |          |            |
| rating         |                |               |          |            |
| skipDays       |                |               |          |            |
| skipHours      |                |               |          |            |
| textInput      |                |               |          |            |
| ttl            |                |               |          |            |
| webMaster      |                |               |          |            |
|                | icon           | icon          |          |            |
|                | logo           |               |          |            |
|                |                | expired       |          |            |
|                |                | favicon       |          |            |
|                |                | home_page_url |          |            |
|                |                | hubs          |          |            |
|                |                | next_url      |          |            |
|                |                | user_comment  |          |            |
|                |                | version*      |          |            |

`Feed.Basic.Item` attributes:

| RSS         | Atom           | JSON           | Microformats  | Item field  |
| ----------- | -------------- | -------------- | ------------- | ----------- |
| author      | author+        | authors        |               | author      |
| category    | category+      | tags           |               | categories  |
|             |                |                |               | duration    |
| enclosure   | link/enclosure | attachments    |               | attachments |
|             |                | image          |               | image       |
| guid        | id*            | id*            | id            | id          |
| link        | link/alternate |                |               | links       |
| pubDate     | published      | date_published | published     | published   |
| description | summary*       |                |               | summary     |
| title       | title*         | title          |               | title       |
|             | updated*       |                |               | updated     |
|             | link/self      | url            | url           | links       |
| comments    |                |                |               |             |
| source      | source         |                |               |             |
|             | content        |                | content.value | content     |
|             |                | content_html   | content.html  | content     |
|             |                | content_text   |               | content     |
|             | contributor+   |                |               |             |
|             | link/related   | external_url   |               | links       |
|             | rights         |                |               |             |
|             |                | banner_image   |               |             |
|             |                | date_modified  |               |             |

`Reed.Basic.Attachment` attributes:

| RSS and Atom     | RSS Media | JSON Attachment     | Attachment field |
| ---------------- | ----------| ------------------- | ------- |
| enclosure.length | length    | size_in_bytes       | size    |
| enclosure.type   | type      | mime_type           | type    |
| enclosure.url    | url       | url                 | url     |
| image.url        | url       |                     | url     |
| image.link       |           |                     | link    |
| image.title      |           |                     | title   |
| image.height     | height    |                     | height  |
| image.width      | width     |                     | width   |
| itunes:duration  |           | duration_in_seconds |         |

The transformer parses the RSS Media attributes for `media:content`
and `media:thumbnail` elements.

The Attachment `primary` field is set to true for the `media:content`
inside a `media:group` element, to distinguish it from the other
`media:thumbnail` elements in the group. 

`Reed.Basic.Link` attributes:

| RSS  | Atom      | JSON          | Microformats  | Link field |
| ---- | ----------| ------------- | ------------- | ------ |
|      | link.rel  |               | rel-url.rel   | rel    |
|      | link.type |               | rel-url.type  | type   |
| link | link.href | url           | rel-url       | href   |
|      |           | external_url  |               | href   |
|      |           | feed_url      |               | href   |
|      |           | home_page_url |               | href   |
|      |           |               | rel-url.title | title  |

### Atom links

The Atom specification defines five initial values for the Registry of Link
Relations:

  1.  The value "alternate" signifies that the IRI in the value of the
      href attribute identifies an alternate version of the resource
      described by the containing element.
  2.  The value "related" signifies that the IRI in the value of the
      href attribute identifies a resource related to the resource
      described by the containing element.  For example, the feed for a
      site that discusses the performance of the search engine at
      "http://search.example.com" might contain, as a child of
      atom:feed:
      `<link rel="related" href="http://search.example.com/"/>`
      An identical link might appear as a child of any atom:entry whose
      content contains a discussion of that same search engine.
  3.  The value "self" signifies that the IRI in the value of the href
      attribute identifies a resource equivalent to the containing
      element.
  4.  The value "enclosure" signifies that the IRI in the value of the
      href attribute identifies a related resource that is potentially
      large in size and might require special handling.  For atom:link
      elements with rel="enclosure", the length attribute SHOULD be
      provided.
  5.  The value "via" signifies that the IRI in the value of the href
      attribute identifies a resource that is the source of the
      information provided in the containing element.

Some other rel values encountered:

  * "amphtml"
  * "apple-touch-icon-precomposed"
  * "canonical"
  * "dns-prefetch"
  * "EditURI"
  * "hub"
  * "icon"
  * "mask-icon"
  * "me"
  * "pingback"
  * "preconnect"
  * "prefetch"
  * "preload"
  * "profile"
  * "search"
  * "shortcut icon"
  * "shortlink"
  * "shorturl"
  * "stylesheet"

### Get just the feed metadata

```elixir
import Reed.Transformers

Reed.get!(rss_url, transform: transform(halt()))
```

### Get all items in a list

```elixir
import Reed.Transformers

Reed.get!(rss_url, transform: pipeline(collect()))
```

### Get the first 5 items in a list

```elixir
import Reed.Transformers

Reed.get!(rss_url, transform: collect() |> limit(5) |> pipeline())
```

### Get the first 5 items, then convert to Reed.Basic structs

```elixir
import Reed.Transformers

%Reed.Basic.Feed{} =
  feed =
  Reed.get!(rss_url,
    transform: collect() |> limit(5) |> pipeline(),
    normalize_rss: true
  )
```

### Get all `itunes:` namespaced elements from the first 2 items as a list

```elixir
import Reed.Transformers

Reed.get!(rss_url,
  transform:
    transform(
      &Map.filter(&1, fn
        {<<"itunes:", _rest::binary>>, _v} -> true
        _ -> false
      end)
    )
    |> collect()
    |> limit(2)
    |> pipeline()
)
```

#### Get the description, title, and publication date of the first episode that starts with a `10`

```elixir
import Reed.Transformers

Reed.get!(rss_url,
  transform:
    filter(&match?(%{"title" => <<"#10", _rest::binary>>}, &1))
    |> transform(&Map.take(&1, ["description", "title", "pubDate"]))
    |> limit(1)
    |> collect()
    |> pipeline()
)
```
<!-- END MODULEDOC -->
