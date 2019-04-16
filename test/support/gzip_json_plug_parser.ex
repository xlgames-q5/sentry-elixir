defmodule Sentry.Plug.Parsers.GzipJSON do
  @behaviour Plug.Parsers

  def init(opts) do
    {decoder, opts} = Keyword.pop(opts, :json_decoder)
    {body_reader, opts} = Keyword.pop(opts, :body_reader, {Plug.Conn, :read_body, []})

    validate_decoder!(decoder)

    {body_reader, decoder, opts}
  end

  defp validate_decoder!(nil) do
    raise ArgumentError, "JSON parser expects a :json_decoder option"
  end

  defp validate_decoder!({module, fun, args})
  when is_atom(module) and is_atom(fun) and is_list(args) do
    arity = length(args) + 1

    unless Code.ensure_compiled?(module) and function_exported?(module, fun, arity) do
      raise ArgumentError,
        "invalid :json_decoder option. Undefined function " <>
          Exception.format_mfa(module, fun, arity)
    end
  end

  defp validate_decoder!(decoder) when is_atom(decoder) do
    unless Code.ensure_compiled?(decoder) do
      raise ArgumentError,
        "invalid :json_decoder option. The module #{inspect(decoder)} is not " <>
          "loaded and could not be found"
    end

    unless function_exported?(decoder, :decode!, 1) do
      raise ArgumentError,
        "invalid :json_decoder option. The module #{inspect(decoder)} must " <>
          "implement decode!/1"
    end
  end

  defp validate_decoder!(decoder) do
    raise ArgumentError,
      "the :json_decoder option expects a module, or a three-element " <>
        "tuple in the form of {module, function, extra_args}, got: #{inspect(decoder)}"
  end

  def parse(conn, "application", subtype, _params, {{mod, fun, args}, decoder, opts}) do
    IO.inspect "HELLO-1"
    if gzip_content_encoding?(conn) and (subtype == "json" or String.ends_with?(subtype, "+json")) do
      IO.inspect "HELLO"
      apply(mod, fun, [conn, opts | args]) |> decode(decoder)
    else
      {:next, conn}
    end
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp decode({:ok, "", conn}, _decoder) do
    {:ok, %{}, conn}
  end

  defp decode({:ok, body, conn}, decoder) do
    IO.inspect "HELLO2"
    body = :zlib.gunzip(body)
    case apply_mfa_or_module(body, decoder) do
      terms when is_map(terms) ->
        {:ok, terms, conn}

      terms ->
        {:ok, %{"_json" => terms}, conn}
    end
    rescue
    e -> raise Plug.Parsers.ParseError, exception: e
  end

  defp decode({:more, _, conn}, _decoder) do
    {:error, :too_large, conn}
  end

  defp decode({:error, :timeout}, _decoder) do
    raise Plug.TimeoutError
  end

  defp decode({:error, _}, _decoder) do
    raise Plug.BadRequestError
  end

  defp apply_mfa_or_module(body, decoder) when is_atom(decoder) do
    decoder.decode!(body)
  end

  defp apply_mfa_or_module(body, {module_name, function_name, extra_args}) do
    apply(module_name, function_name, [body | extra_args])
  end

  defp gzip_content_encoding?(conn) do
    if Plug.Conn.get_req_header(conn, "content-encoding") == ["gzip"] do
      true
    else
      false
    end
  end
end
