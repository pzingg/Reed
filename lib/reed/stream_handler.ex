defmodule Reed.StreamHandler do
  require Logger

  @doc """
  This will take a (file or string IO) stream and apply the transformation to each item lazily,
  returning the transformed result as a map with `:feed_info` and `:items` elements.

  The data is streamed chunk-by-chunk, meaning you can stop transforming the RSS feed at any
  point, and you only store in memory what you decide to using the `:transform` option.

  ## Options

  * `:feed_url` - The URL for the document being streamed.
  * `:transform` - The transformation function / pipeline to apply to each item in the RSS feed.
    Check the documentation for `Reed` for more information.
  * `:normalize_rss` - If present and true, transform items and feed_info into "common" values.
    Note: this option requires the presence of `Reed.Transformers.collect/1` in the
    transformer pipeline.
  """
  def parse(stream, options \\ []) do
    options = Map.new(options)
    item_handler = Reed.Handler.get_item_handler!(options)

    initial_state = %Reed.State{
      transform: item_handler,
      normalize_rss: Map.get(options, :normalize_rss, false)
    }

    first_chunk = Enum.take(stream, 1) |> List.first() |> String.trim_leading()

    case Reed.Handler.detect_parser!(first_chunk) do
      :json ->
        chunks = Enum.reduce(stream, [], fn chunk, chunks -> [chunk | chunks] end)
        json_body = chunks |> Enum.reverse() |> Enum.join("")
        final_state = %{initial_state | flavor: "json"}
        Reed.Basic.JsonFeed.parse(json_body, final_state)

      :html ->
        url = Map.fetch!(options, :feed_url)
        chunks = Enum.reduce(stream, [], fn chunk, chunks -> [chunk | chunks] end)
        html_body = chunks |> Enum.reverse() |> Enum.join("")
        final_state = %{initial_state | flavor: "html+mf2"}
        Reed.Basic.HtmlFeed.parse(html_body, url, final_state)

      :xml ->
        stream = Stream.concat([first_chunk], Stream.drop(stream, 1))

        case Saxy.parse_stream(stream, Reed.Handler, initial_state) do
          {:ok, final_state} ->
            {:ok, Reed.Basic.Transformer.finalize_and_normalize(final_state)}

          {:halt, final_state, _rest} ->
            Logger.debug("parse_stream halted #{inspect(final_state)}")
            {:ok, Reed.Basic.Transformer.finalize_and_normalize(final_state)}

          {:error, %Saxy.ParseError{} = e} ->
            message = Exception.message(e)
            Logger.error("parse_stream error #{message}")
            {:error, message}
        end
    end
  end
end
