defmodule Reed.Basic.Transformer do
  @moduledoc """
  These are handled internally by Reed.Handler:
  - entries
  - items

  Links are handled specially:
  - link (as a URL) is transformed to a rel="alternate", type="html" link
  - link/alternate
  - link/enclosure
  - link/related
  - link/self

  In JSON feeds:
  - feed_url is transformed to a rel="self" link
  - home_page_url is transformed to a rel="alternate" link
  - url is transformed to a rel="related" link
  - external_url is transformed to a rel="alternate" link

  ## References for some of the RSS namespaces encountered

  | Prefix           | Reference docs |
  | ---------------- | -------------- |
  | rss:             | https://www.rssboard.org/rss-specification |
  | atom:            | https://feedsmith.dev/reference/namespaces/atom |
  | content:         | https://feedsmith.dev/reference/namespaces/content |
  | acast:           | https://feedsmith.dev/reference/namespaces/acast |
  | blogChannel:     | https://feedsmith.dev/reference/namespaces/blogchannel |
  | castfire:        | |
  | creativeCommons: | https://feedsmith.dev/reference/namespaces/creativecommons |
  | dc:              | https://feedsmith.dev/reference/namespaces/dc |
  | dcterms:         | https://feedsmith.dev/reference/namespaces/dcterms |
  | feedburner:      | |
  | feedpress:       | https://feedsmith.dev/reference/namespaces/feedpress |
  | fireside:        | |
  | flatplan:        | |
  | foaf/friends:    | https://xmlns.com/foaf/spec/ |
  | georss:          | https://feedsmith.dev/reference/namespaces/georss |
  | googleplay:      | https://feedsmith.dev/reference/namespaces/googleplay |
  | housekeeping:    | |
  | itunes:          | https://feedsmith.dev/reference/namespaces/itunes |
  | lab:             | |
  | lj:              | |
  | openSearch:      | https://feedsmith.dev/reference/namespaces/opensearch |
  | media:           | https://feedsmith.dev/reference/namespaces/media |
  | meta:            | |
  | omny:            | |
  | podcast:         | https://feedsmith.dev/reference/namespaces/podcast |
  | ppg:             | |
  | psc:             | https://podlove.org/simple-chapters/ |
  | rawvoice:        | https://feedsmith.dev/reference/namespaces/rawvoice |
  | slash:           | https://feedsmith.dev/reference/namespaces/slash |
  | slate:           | |
  | snf:             | https://publishers.smartnews.com/hc/ja/articles/360036526213-SmartFormat%E6%A6%82%E8%A6%81-%E3%83%90%E3%83%BC%E3%82%B8%E3%83%A7%E3%83%B32-1 |
  | source:          | https://feedsmith.dev/reference/namespaces/source |
  | spotify:         | https://feedsmith.dev/reference/namespaces/spotify |
  | ssp:             | https://wordpress.org/plugins/seriously-simple-podcasting/ |
  | sy:              | https://web.resource.org/rss/1.0/modules/syndication/ |
  | thr:             | https://feedsmith.dev/reference/namespaces/thr |
  | truthout:        | |
  | webfeeds:        | https://webfeeds.org/rss/1.0 |
  | wfw:             | https://feedsmith.dev/reference/namespaces/wfw |
  | yt:              | https://feedsmith.dev/reference/namespaces/yt |

  ## Other elements without explicit namespaces

  - author_name
  - author_url
  - characters
  - html
  - imageCaption
  - location
  - meta
  - provider_name
  - provider_url
  - thumbnail
  - thumbnail_height
  - thumbnail_url
  - thumbnail_width
  - timeToRead
  - webmaster

  ## Other notes

  The Atom spec includes many variants for the <atom:content>
  element. We only handle the text, html, or xhtml content in the
  atomInlineTextContent, atomInlineXHTMLContent, atomInlineOtherContent
  variants, and we ignore the media type.

  See https://www.rfc-editor.org/info/rfc4287
  """

  require Logger

  @doc """
  Normalizes both `rss.feed_info` and `rss.private.items` and
  then converts the normalized data into Reed.Basic structs
  (Feed, Item, Link, and Attachment).
  """
  def to_feed(%{feed_info: _feed_info} = rss) do
    rss = normalize_rss(rss)
    items = get_in(rss, [:private, :items]) || []

    rss
    |> Map.get(:feed_info)
    |> Map.put("items", items)
    |> Reed.Basic.Feed.to_feed()
  end

  @doc """
  Normalizes both `rss.feed_info` and `rss.private.items`
  into a standardized format.
  """
  def normalize_rss(%{feed_info: feed_info, private: %{items: items}} = rss) do
    if Enum.all?([feed_info | items], &normalized?/1) do
      rss
    else
      items = Enum.map(items, &normalize/1)
      rss |> normalize_feed_info() |> put_in([:private, :items], items)
    end
  end

  @doc """
  Normalizes a single feed info or item into a standardized format.
  The sentinel "_reed_normalized_" prevents re-normalizing an already
  normalized item.
  """
  def normalize(%{"_reed_normalized_" => true} = item), do: item

  def normalize(item) when is_map(item) do
    handlers = element_handlers()

    item
    |> Map.put("_reed_normalized_", true)
    |> Enum.reduce(%{}, fn {name, value}, acc ->
      name =
        name
        |> String.replace_prefix("atom:", "")
        |> String.replace_prefix("atom10:", "")

      handler = :lists.keyfind(name, 1, handlers)

      result =
        case handler do
          false ->
            if !String.starts_with?(name, "xmlns") do
              # File.write!("attributes.txt", "#{name}\n", [:append])
              Logger.warning("no handler for item #{name}")
            end

            ignore(name, value)

          {_name, _type, :ignore} ->
            ignore(name, value)

          {name, :string, fun} ->
            case get_text(value) do
              text when is_binary(text) ->
                fun.(name, text)

              _ ->
                :delete
            end

          {_name, _, fun} ->
            fun.(name, value)
        end

      case result do
        {:merge, values} ->
          Enum.reduce(values, acc, fn
            {key, {:append, vals}}, acc when is_list(vals) ->
              Map.update(acc, key, vals, fn values -> vals ++ values end)

            {key, {:append, val}}, acc ->
              Map.update(acc, key, [val], fn values -> [val | values] end)

            {key, val}, acc ->
              Map.put(acc, key, val)
          end)

        {:append, key, vals} when is_list(vals) ->
          Map.update(acc, key, vals, fn values -> vals ++ values end)

        {:append, key, val} ->
          Map.update(acc, key, [val], fn values -> [val | values] end)

        :delete ->
          acc
      end
    end)
  end

  @doc """
  Returns `true` if normalization has been applied to `rss.feed_info`.
  """
  def normalized?(%{feed_info: %{"_reed_normalized_" => true}}), do: true
  def normalized?(_), do: false

  # Private functions

  defp normalize_feed_info(%{feed_info: %{"_reed_normalized_" => true}} = rss), do: rss

  defp normalize_feed_info(%{feed_info: feed_info} = rss) when is_map(feed_info) do
    feed_info =
      case feed_info do
        %{"feed" => feed} -> normalize(feed)
        %{"rss" => %{"channel" => channel}} -> normalize(channel)
        _ -> raise "invalid feed_info #{inspect(feed_info)}"
      end

    %{rss | feed_info: feed_info}
  end

  defp element_handlers do
    [
      {"_reed_normalized_", :boolean, :ignore},
      {"attachments", :string, &handle_attachments/2},
      {"author", :map, &handle_authors/2},
      {"authors", :map, &handle_authors/2},
      {"avatar", :string, :ignore},
      {"banner_image", :string, :ignore},
      {"categories", :list, &handle_categories/2},
      {"category", :list, &handle_categories/2},
      {"cloud", :map, &handle_rsscloud/2},
      {"comments", :string, :ignore},
      {"content", :map, &handle_content/2},
      {"content_html", :string, &handle_content/2},
      {"content_text", :string, &handle_content/2},
      {"content:encoded", :string, &handle_content/2},
      {"contributor", :string, :ignore},
      {"copyright", :string, :ignore},
      {"date_modified", :string, &handle_updated/2},
      {"date_published", :string, &handle_published/2},
      {"dc:creator", :string, &handle_authors/2},
      {"dc:date", :string, :ignore},
      {"dc:language", :string, :ignore},
      {"dc:rights", :string, :ignore},
      {"description", :string, &handle_summary/2},
      {"docs", :string, :ignore},
      {"duration", :integer, &handle_duration/2},
      {"duration_in_seconds", :integer, &handle_duration/2},
      {"email", :string, :ignore},
      {"enclosure", :list, &handle_attachments/2},
      {"expired", :string, :ignore},
      {"external_url", :string, &handle_alternate_url/2},
      {"favicon", :string, &handle_image/2},
      {"feed_url", :string, &handle_self_url/2},
      {"generator", :string, :ignore},
      {"googleplay:author", :string, :ignore},
      {"googleplay:email", :string, :ignore},
      {"googleplay:owner", :string, :ignore},
      {"guid", :map, &handle_id/2},
      {"height", :integer, :ignore},
      {"home_page_url", :string, &handle_alternate_url/2},
      {"href", :string, :ignore},
      {"hubs", :string, :ignore},
      {"icon", :string, &handle_image/2},
      {"id", :string, &handle_id/2},
      {"image", :map, &handle_image/2},
      {"itunes:applepodcastsverify", :string, :ignore},
      {"itunes:author", :string, &handle_authors/2},
      {"itunes:block", :string, :ignore},
      {"itunes:category", :list, &handle_categories/2},
      {"itunes:chapters", :string, :ignore},
      {"itunes:complete", :string, :ignore},
      {"itunes:duration", :string, &handle_duration/2},
      {"itunes:episode", :string, :ignore},
      {"itunes:episodeType", :string, :ignore},
      {"itunes:explicit", :string, :ignore},
      {"itunes:image", :map, &handle_image/2},
      {"itunes:keywords", :string, :ignore},
      {"itunes:new-feed-url", :string, :ignore},
      {"itunes:owner", :string, :ignore},
      {"itunes:season", :string, :ignore},
      {"itunes:summary", :string, &handle_summary/2},
      {"itunes:subtitle", :string, &handle_subtitle/2},
      {"itunes:title", :map, &handle_title/2},
      {"itunes:transcript", :string, :ignore},
      {"itunes:type", :string, :ignore},
      {"language", :string, &handle_language/2},
      {"lastBuildDate", :string, &handle_published/2},
      {"length", :string, :ignore},
      {"link", :list, &handle_links/2},
      {"logo", :string, &handle_image/2},
      {"managingEditor", :string, :ignore},
      {"media:content", :map, &handle_media_content/2},
      {"media:credit", :string, :ignore},
      {"media:description", :string, :ignore},
      {"media:group", :map, &handle_media_group/2},
      {"media:thumbnail", :map, &handle_media_thumbnail/2},
      {"mime_type", :string, :ignore},
      {"name", :string, :ignore},
      {"next_url", :string, :ignore},
      {"openSearch:itemsPerPage", :integer, :ignore},
      {"openSearch:startIndex", :integer, :ignore},
      {"openSearch:totalResults", :integer, :ignore},
      {"podcast:alternateEnclosure", :string, :ignore},
      {"podcast:block", :string, :ignore},
      {"podcast:chapters", :string, :ignore},
      {"podcast:episode", :string, :ignore},
      {"podcast:funding", :string, :ignore},
      {"podcast:guid", :string, &handle_id/2},
      {"podcast:images", :string, :ignore},
      {"podcast:license", :string, :ignore},
      {"podcast:liveItem", :string, :ignore},
      {"podcast:location", :string, :ignore},
      {"podcast:locked", :string, :ignore},
      {"podcast:medium", :string, :ignore},
      {"podcast:person", :string, :ignore},
      {"podcast:podping", :string, :ignore},
      {"podcast:podroll", :string, :ignore},
      {"podcast:season", :string, :ignore},
      {"podcast:socialInteract", :string, :ignore},
      {"podcast:soundbite", :string, :ignore},
      {"podcast:trailer", :string, :ignore},
      {"podcast:transcript", :string, :ignore},
      {"podcast:txt", :string, :ignore},
      {"podcast:value", :string, :ignore},
      {"post-id", :integer, :ignore},
      {"pubDate", :string, &handle_published/2},
      {"published", :string, &handle_published/2},
      {"rating", :string, :ignore},
      {"rights", :string, :ignore},
      {"site", :string, :ignore},
      {"size", :integer, :ignore},
      {"size_in_bytes", :integer, :ignore},
      {"skipDays", :string, :ignore},
      {"skipHours", :string, :ignore},
      {"slash:comments", :integer, :ignore},
      {"source", :map, :ignore},
      {"source:account", :map, :ignore},
      {"source:blogroll", :string, :ignore},
      {"source:comments", :map, :ignore},
      {"source:inReplyTo", :map, :ignore},
      {"source:localTime", :string, :ignore},
      {"source:markdown", :string, :ignore},
      {"source:outline", :map, :ignore},
      {"source:self", :string, &handle_self_url/2},
      {"standfirst", :string, &handle_summary/2},
      {"subtitle", :string, &handle_subtitle/2},
      {"summary", :string, &handle_summary/2},
      {"sy:updateFrequency", :integer, :ignore},
      {"sy:updatePeriod", :string, :ignore},
      {"tags", :list, &handle_categories/2},
      {"textInput", :string, :ignore},
      {"title", :map, &handle_title/2},
      {"ttl", :string, :ignore},
      {"type", :string, :ignore},
      {"updated", :string, &handle_updated/2},
      {"url", :string, &handle_related_url/2},
      {"user_comment", :string, :ignore},
      {"version", :string, :ignore},
      {"webfeeds:icon", :string, :ignore},
      {"webMaster", :string, :ignore},
      {"width", :integer, :ignore},
      {"wfw:commentRss", :string, :ignore},
      {"xml:base", :string, :ignore},
      {"xml:lang", :string, :ignore},
      {"yt:channelId", :string, :ignore},
      {"yt:videoId", :string, :ignore}
    ]
  end

  # rss %{"source:outline" => %{"text" => _, "created" => _, "type" => "outline",
  #  "flInCalendar" => "true", "permalink" => "http://scripting.com/2026/06/08.html#a141559"} }

  defp ignore(name, value), do: {:merge, %{name => value}}

  # Can have multiple elements
  defp handle_attachments(_name, value) do
    # json %{"enclosure" => %{"length" => "76810164", "type" => "audio/mpeg", "url" => "https://2.gum.fm/mgln.ai/e/802/op3.dev/e/pscrb.fm/rss/p/pdst.fm/e/dts.podtrac.com/redirect.mp3/media.transistor.fm/935f4c29/a4f2930c.mp3"}}}
    attachments =
      value
      |> List.wrap()
      |> Enum.map(fn
        %{"url" => _, "length" => length} = attachment ->
          attachment |> Map.put("size", length)

        %{"url" => _, "size" => size} = attachment ->
          attachment |> Map.put("size", size)

        %{"url" => _} = attachment ->
          attachment

        attachment ->
          Logger.error("missing url for attachment #{inspect(attachment)}")
          nil
      end)
      |> reject_nils()
      |> Enum.map(&normalize_attachment/1)

    {:append, "attachments", attachments}
  end

  # Can have multiple elements
  defp handle_authors(name, value) do
    # atom %{"itunes:author" => "AppleInsider"}
    # atom %{"author" => %{"name" => "John Gruber", "uri" => "http://daringfireball.net/"}
    # json %{"authors" => %{"name" => "John Gruber", "url" => "https://twitter.com/gruber"}
    # %{"dc:creator" => "Peter Zingg"}
    names =
      value
      |> List.wrap()
      |> Enum.reduce([], fn
        %{"name" => name}, acc when is_binary(name) ->
          [name | acc]

        name, acc when is_binary(name) ->
          [name | acc]

        val, _acc ->
          raise "authors (#{name}) cannot handle value #{inspect(val)}"
      end)
      |> Enum.reverse()

    if names != [] do
      {:merge, %{"authors" => Enum.join(names, ", ")}}
    else
      :delete
    end
  end

  # Can have multiple elements in RSS, and itunes:category can be nested
  defp handle_categories(name, value) do
    # rss %{"category" -> %{"domain" => _, "_text_" => "Arts"}}
    # atom %{"category" -> %{"scheme" => "https://www.theverge.com", "term" => "News"}}
    # %{"tags" => ["prototyping"]}
    # %{"itunes:category" => %{"text" => "Technology", %{"itunes:category" => %{"text" => "Tech News"}, "text" => "News"}}
    categories =
      value
      |> List.wrap()
      |> Enum.reduce([], fn
        %{"_text_" => text} = val, acc when is_binary(text) ->
          add_categories(acc, val, text)

        %{"text" => text} = val, acc when is_binary(text) ->
          add_categories(acc, val, text)

        %{"term" => text} = val, acc when is_binary(text) ->
          add_categories(acc, val, text)

        val, acc when is_binary(val) ->
          [val | acc]

        val, acc when is_list(val) ->
          val ++ acc

        val, acc ->
          Logger.warning("categories (#{name}) missing text in #{inspect(val)}")
          acc
      end)
      |> Enum.reverse()

    if categories == [] do
      :delete
    else
      {:merge, %{"categories" => categories}}
    end
  end

  defp add_categories(acc, val, text) when is_map(val) and is_binary(text) do
    case Map.get(val, "itunes:category") do
      subvalue when is_map(subvalue) ->
        {_op, %{"categories" => subcats}} = handle_categories("itunes:category", subvalue)
        [Enum.join([text | subcats], " > ") | acc]

      _ ->
        [text | acc]
    end
  end

  defp handle_content(_name, value) when is_map(value) do
    # atom (feed) %{"content" => %{"type" => "html", "xml:base" => _, "xml:lang" => "en", "_text_" => _}}
    {:merge,
     %{
       "content" => get_text(value),
       "content_base" => Map.get(value, "xml:base"),
       "content_lang" => Map.get(value, "xml:lang")
     }}
  end

  defp handle_content(_name, value) when is_binary(value) do
    # json %{"content:encoded" => _}}
    # json %{"content_html" => _}
    {:merge, %{"content" => value, "content_base" => nil, "content_lang" => nil}}
  end

  defp handle_content(name, value) do
    raise "content (#{name}) cannot handle #{inspect(value)}"
  end

  defp handle_duration(_name, value) when is_binary(value) do
    value = parse_duration(value)

    if value == 0 do
      :delete
    else
      {:merge, %{"duration" => value}}
    end
  end

  defp parse_duration(value) do
    case Regex.named_captures(~r/(?<hours>\d\d?):(?<minutes>\d\d):(?<seconds>\d\d)/, value) do
      %{"hours" => hours, "minutes" => mins, "seconds" => secs} ->
        hours = String.to_integer(hours)
        mins = String.to_integer(mins)
        secs = String.to_integer(secs)
        hours * 3_600 + mins * 60 + secs

      _ ->
        case Integer.parse(value) do
          {secs, ""} -> secs
          _ -> 0
        end
    end
  end

  defp handle_self_url(name, value) when is_binary(value) do
    # json %{"feed_url" => url}
    # rss %{"source:self" => _url}
    type = if name == "feed_url", do: "application/json", else: "application/rss+xml"
    {:append, "links", %{"rel" => "self", "type" => type, "href" => value}}
  end

  defp handle_alternate_url(_name, value) when is_binary(value) do
    {:append, "links", %{"rel" => "alternate", "type" => "text/html", "href" => value}}
  end

  defp handle_related_url(_name, value) when is_binary(value) do
    {:append, "links", %{"rel" => "related", "type" => "text/html", "href" => value}}
  end

  defp handle_id(_name, %{"_text_" => id, "isPermaLink" => permalink}) do
    # rss %{"guid" => %{"isPermaLink" => _, "_text_" => _}}
    {:merge, %{"id" => id, "permalink" => permalink}}
  end

  defp handle_id(_name, value) when is_binary(value) do
    # rss %{"guid" => _}}
    # atom %{"id" => _}
    {:merge, %{"id" => value, "permalink" => "undefined"}}
  end

  defp handle_image(_name, %{"url" => _} = value) do
    # rss %{"image" => %{"url" => _, "link" => _, "title" => _, "description" => _, "height" => _, "width" => _}}
    {:merge, %{"image" => value}}
  end

  defp handle_image(_name, %{"href" => value}) do
    # rss %{"itunes:image" => %{"href" => _}}
    {:merge, %{"image" => value}}
  end

  defp handle_image(_name, value) when is_binary(value) do
    # json %{"favicon" => _} 64 x 64 pixels
    # json %{"icon" => _} 512 x 512 pixels
    # atom %{"icon" => _} 1:1 aspect ratio
    # atom %{"logo" => _} 2:1 aspect ratio
    {:merge, %{"image" => value}}
  end

  defp handle_language(_name, value) when is_binary(value) do
    {:merge, %{"language" => value}}
  end

  # Can have multiple elements in RSS
  defp handle_links(_name, value) do
    # atom %{"link" => %{"rel" => "hub", "href" => _}}
    # atom/rss %{"link" => %{"rel" => "alternate", "type" => "application/rss+xml", "title" => "The Bipeds&#039; Monitor &raquo; Feed", "href" => "https://bipedsmonitor.com/feed/"}}
    # rss %{"atom:link" => %{"rel" => "self", "type" => "application/rss+xml", "href" => "https://bipedsmonitor.com/comments/feed/"}}
    links =
      value
      |> List.wrap()
      |> Enum.map(fn
        value when is_binary(value) -> %{"rel" => "alternate", "type" => "html", "href" => value}
        %{"rel" => "hub", "href" => _} = value -> Map.put_new(value, "type", "websub")
        %{"href" => _} = value -> value
      end)

    {:append, "links", links}
  end

  defp handle_rsscloud(_name, %{"domain" => host, "port" => port, "path" => path}) do
    # rss %{"cloud" => %{"domain" => _, "port" => _, "path" => _, "registerProcedure" => "", "protocol" => "http-post"}}
    port = String.to_integer(port)
    url = %URI{scheme: "http", host: host, port: port, path: path} |> URI.to_string()
    {:append, "links", %{"rel" => "hub", "type" => "rsscloud", "href" => url}}
  end

  defp handle_media_content(_name, value) do
    attachments = List.wrap(value) |> Enum.map(&media_content_attachment/1)
    {:append, "attachments", attachments}
  end

  defp media_content_attachment(value) do
    # wordpress %{"media:content" => %{
    #   "url" => _,
    #   "medium" => "image",
    #   "fileSize" => _,
    #   "media:rating" => %{"scheme" => "urn.simple", "_text_" => "adult"},
    #   "media:title" => %{"type" => "html", _text_" => "img_8245"}
    # }
    {title, value} = Map.pop(value, "media:title")
    {size, value} = Map.pop(value, "fileSize")
    {type, value} = Map.pop(value, "medium")

    value
    |> Map.merge(%{"title" => get_text(title), "size" => size})
    |> Map.put_new("type", type)
    |> reject_nils()
    |> normalize_attachment()
  end

  defp handle_media_thumbnail(_name, value) when is_map(value) do
    # wordpress %{"media:thumbnail" => %{"url" => _}}
    # youtube %{"media:thumbnail" => %{"url" => _, "height" => _, "width" => _}}
    {:append, "attachments", normalize_attachment(value)}
  end

  defp handle_media_group(_name, value) when is_map(value) do
    # youtube %{"media:group" = %{
    #   "media:title" => _title,
    #   "media:description" => _,
    #   "media:content => %{"url" => _, "type" => _, "width" => _, "height" => _},
    #   "media:thumbnail" => %{"url" => _, "type" => _, "width" => _, "height" => _}.
    #   "media:community" => %{
    #     "media:starRating" => %{"count" => _, "average" => "5.00", "min" => _, "max" => _}
    #     "media:statistics" => %{"views" => _}
    #   }
    # }
    main_content =
      case Map.get(value, "media:content") do
        %{"url" => _} = content -> Map.put(content, "primary", true)
        _ -> nil
      end

    attachments =
      [main_content, Map.get(value, "media:thumbnail")]
      |> reject_nils()
      |> Enum.map(&normalize_attachment/1)

    group =
      %{
        "title" => Map.get(value, "media:title") |> get_text(),
        "summary" => Map.get(value, "media:description")
      }
      |> reject_nils()

    group =
      if attachments == [] do
        group
      else
        Map.put(group, "attachments", {:append, attachments})
      end

    {:merge, group}
  end

  defp normalize_attachment(att_data) do
    Enum.reduce(["size", "width", "height"], att_data, fn key, acc ->
      case Map.get(acc, key) do
        value when is_binary(value) -> Map.put(acc, key, String.to_integer(value))
        value when is_integer(value) -> acc
        _ -> Map.delete(acc, key)
      end
    end)
  end

  defp handle_published(_name, value) when is_binary(value) do
    # Note: rss channel "pubDate" is ignored.
    # rss channel %{"lastBuildDate" => rfc822_formatted_date}
    # rss item %{"pubDate" => rfc822_formatted_date}
    # atom entry %{"published" => rfc3339_formatted_date}
    # json item %{"date_published" => rfc3339_formatted_date}
    {:merge, %{"published" => value}}
  end

  defp handle_updated(_name, value) when is_binary(value) do
    # atom entry %{"updated" => rfc3339_formatted_date}
    # json item %{"date_modified" => rfc3339_formatted_date}
    {:merge, %{"updated" => value}}
  end

  defp handle_subtitle(_name, value) when is_binary(value) do
    {:merge, %{"subtitle" => value}}
  end

  defp handle_summary(_name, value) when is_binary(value) do
    {:merge, %{"summary" => value}}
  end

  defp handle_title(_name, value) do
    # atom %{"title" => %{"type" => "html", "_text_" => title}}
    # rss %{"title" => title}
    {:merge, %{"title" => get_text(value)}}
  end

  defp get_text(text) when is_binary(text), do: text
  defp get_text([text]) when is_binary(text), do: text
  defp get_text(%{"_text_" => _} = value), do: strip_namespace_prefixes(value)
  defp get_text([%{"_text_" => _} = value]), do: strip_namespace_prefixes(value)
  defp get_text(_), do: nil

  defp strip_namespace_prefixes(%{"type" => "xhtml", "_text_" => xhtml}) do
    String.replace(xhtml, ~r/(<\/?)([a-zA-Z_][\w.-]*):([a-zA-Z_][\w.-]*)/, "\\1\\3")
  end

  defp strip_namespace_prefixes(%{"_text_" => text}), do: text

  defp reject_nils(value) when is_map(value) do
    value
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp reject_nils(value) when is_list(value) do
    Enum.reject(value, fn
      {_k, v} -> is_nil(v)
      v -> is_nil(v)
    end)
  end

  defp reject_nils(value), do: value
end
