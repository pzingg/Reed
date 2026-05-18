if Code.ensure_loaded?(Req) || Mix.env() == :docs do
  defmodule Reed.ReqPlugin do
    @moduledoc """
    A `Req` plugin for `Reed`.

    This will stream the RSS feed over the network and apply the transformation to each item lazily.

    This will store the result into the `Req.Response` struct under the `:rss` key in the `:private`
    field.

    This is streamed chunk-by-chunk, meaning you can stop reading the RSS feed at any point, and
    you only store in memory what you decide to using the `:transform` option.

    You can get the result using `Req.Response.get_private(response, :rss)`.

    ## Options
    * `:transform` - The transformation function / pipeline to apply to each item in the RSS feed. Check the documentation for `Reed` for more information.
    """

    require Logger

    alias Req.{Request, Response}

    @doc """
    Attaches `Reed.ReqPlugin` to the given `Req.Request` struct.
    """
    def attach(%Req.Request{} = req, options \\ []) do
      req
      |> Request.register_options([:transform, :normalize_rss])
      |> Request.merge_options(options)
      |> Request.prepend_request_steps(setup_rss_stream: &setup_rss_stream/1)
    end

    def setup_rss_stream(req) do
      Map.put(
        req,
        :into,
        fn
          {:data, chunk}, {req, resp} ->
            parser = Request.get_private(req, :parser)

            {req, parser} =
              if is_nil(parser) do
                init_parser(req, chunk)
              else
                {req, parser}
              end

            case parser do
              :json ->
                parse_json(req, resp, chunk)

              :xml ->
                parse_xml(req, resp, chunk)
            end
        end
      )
    end

    # Do setup - first chunk
    def init_parser(req, chunk) do
      item_handler = Reed.Handler.get_item_handler!(req.options)

      user_state = %Reed.State{
        transform: item_handler,
        normalize_rss: Map.get(req.options, :normalize_rss, false)
      }

      parser = chunk |> String.trim_leading() |> Reed.Handler.detect_parser!()

      partial =
        case parser do
          :xml ->
            {:ok, partial} = Saxy.Partial.new(Reed.Handler, user_state)
            partial

          :json ->
            %{user_state | chunks: [], flavor: "html"}

          :html ->
            %{user_state | chunks: [], flavor: "json"}
        end

      req =
        req
        |> Request.put_private(:parser, parser)
        |> Request.put_private(:partial, partial)

      {req, parser}
    end

    def parse_json(req, resp, chunk) do
      # Prepend the chunk
      req =
        Request.update_private(req, :partial, nil, fn user_state ->
          %{user_state | chunks: [chunk | user_state.chunks]}
        end)

      {:cont, {req, resp}}
    end

    def parse_xml(req, resp, chunk) do
      partial = Request.get_private(req, :partial)

      try do
        case Saxy.Partial.parse(partial, chunk) do
          {:cont, new_partial} ->
            req = Request.put_private(req, :partial, new_partial)

            client_state =
              new_partial
              |> Saxy.Partial.get_state()
              |> Reed.Handler.client_state()

            resp = Response.put_private(resp, :rss, client_state)
            {:cont, {req, resp}}

          {:halt, final_user_state} ->
            req =
              Request.update_private(
                req,
                :partial,
                nil,
                fn %{state: state} = partial ->
                  %{partial | state: %{state | user_state: final_user_state}}
                end
              )

            rss = Reed.Basic.Transformer.finalize_and_normalize(final_user_state)
            resp = Response.put_private(resp, :rss, rss)
            {:halt, {req, resp}}

          {:error, reason} ->
            raise reason
        end
      rescue
        e in Saxy.ParseError ->
          message = Exception.message(e)
          Logger.debug("parse_xml halting on error: #{message}")

          client_state =
            partial
            |> Saxy.Partial.get_state()
            |> Reed.Handler.client_state()

          resp = Response.put_private(resp, :rss, client_state)
          {:halt, {req, resp}}
      end
    end
  end
end
