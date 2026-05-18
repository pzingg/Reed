defmodule Reed do
  if Code.ensure_loaded?(Req) do
    @moduledoc """
    #{File.cwd!() |> Path.join("README.md") |> File.read!() |> then(&Regex.run(~r/.*<!-- BEGIN MODULEDOC -->(?P<body>.*)<!-- END MODULEDOC -->.*/s, &1, capture: :all_but_first)) |> hd()}
    """

    alias Req.{Request, Response}

    @doc """
    Stream the RSS feed at the specified URL.

    ## Options

    * `:transform` - The transformation pipeline to apply while streaming the RSS feed's items.
      Accepts either a single `transformer` or a list of `transformer`s.
    * `:normalize_rss` - If present and true, transform items and feed_info into "common" values.
      Note: this option requires the presence of `Reed.Transformers.collect/1` in the
      transformer pipeline.

    Accepts other options passed through to `Req`.
    """
    def get(url, req_opts \\ []) do
      req =
        Req.new(url: url)
        |> Reed.ReqPlugin.attach()
        |> Req.merge(req_opts)

      case Request.run_request(req) do
        {req, %Response{} = resp} ->
          case Request.get_private(req, :parser) do
            :json ->
              %{chunks: chunks} = user_state = Request.get_private(req, :partial)

              if is_list(chunks) do
                json_body = chunks |> Enum.reverse() |> Enum.join("")

                case Reed.Basic.JsonFeed.parse(json_body, user_state) do
                  {:ok, client_state} -> {:ok, Response.put_private(resp, :rss, client_state)}
                  error -> error
                end
              else
                {:error, "invalid json body #{inspect(chunks)}"}
              end

            :html ->
              %{chunks: chunks} = user_state = Request.get_private(req, :partial)

              if is_list(chunks) do
                html_body = chunks |> Enum.reverse() |> Enum.join("")

                case Reed.Basic.HtmlFeed.parse(html_body, url, user_state) do
                  {:ok, client_state} -> {:ok, Response.put_private(resp, :rss, client_state)}
                  error -> error
                end
              else
                {:error, "invalid html body #{inspect(chunks)}"}
              end

            :xml ->
              {:ok, resp}
          end

        {_req, error} ->
          error
      end
    end

    def get!(url, req_opts \\ []) do
      case get(url, req_opts) do
        {:ok, resp} -> resp
        {:error, err} -> raise err
      end
    end

    @doc """
    Parse an RSS feed document from a file or string IO stream.

    ## Options

    * `:feed_url` - The URL for the document being streamed.
    * `:transform` - The transformation pipeline to apply while streaming the RSS feed's items.
      Accepts either a single `transformer` or a list of `transformer`s.
    * `:normalize_rss` - If present and true, transform items and feed_info into "common" values.
      Note: this option requires the presence of `Reed.Transformers.collect/1` in the
      transformer pipeline.
    """
    defdelegate stream(stream, options \\ []), to: Reed.StreamHandler, as: :parse
  end
end
