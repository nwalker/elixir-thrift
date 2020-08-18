defmodule Thrift.Generator.Binary.Framed.Server.HTTP do
  def generate(dest_module, service, file_group) do

    thrift_root = generate_thrift_root(service)

    quote do
      defmodule Binary.Framed.Server.HTTP do

        unquote(thrift_root)

        def get_child_spec do
          {Plug.Cowboy, scheme: :http, plug: __MODULE__.Router, options: [port: 4001]}
        end
      end
    end
  end

  def generate_thrift_root(service) do
    quote do
      defmodule Router do
        use Plug.Router

        alias Thrift.Protocol

        plug :match
        plug :dispatch

        post "/thrift" do
          # send_resp(conn, 200, "keke")
          with(
            {:ok, payload, conn} <- Plug.Conn.read_body(conn),
            {:ok, parsed} <- Protocol.Binary.deserialize(:message_begin, payload) |> IO.inspect()
          ) do
            handle_thrift_message(conn, parsed)
          end
        end

        match _ do
          send_resp(conn, 404, "not found")
        end

        def handle_thrift_message(conn, {:call, sequence_id, name, args_binary}) do
          IO.inspect(name, label: "FORWARD")
          conn = %{conn | body_params: args_binary, path_info: [name]}
          Plug.forward(conn, [name], __MODULE__.Handlers, [])
        end

        unquote(generate_thrift_handlers(service))

      end
    end
  end

  def generate_thrift_handlers(service) do
    quote do
      defmodule Handlers do
        use Plug.Router

        plug :match
        plug :dispatch

        unquote_splicing(Enum.map(service.functions, &generate_thrift_handle/1))

        match _ do
          IO.inspect(conn, label: "Not matched")
          send_resp(conn, 404, "Ohh")
        end
      end
    end
  end

  def generate_thrift_handle({fname, _function_ast}) do
    func_name = "/" <> Atom.to_string(fname)
    quote do
      post unquote(func_name) do
        send_resp(conn, 200, unquote(func_name) <> "GOTCHA")
      end
    end

  end
end
