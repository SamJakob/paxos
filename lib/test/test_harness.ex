defmodule TestHarness do

    # @compile :nowarn_unused_vars

    # TODO: limit the number of attempts
    def wait_to_register(name, :undefined) do
        Process.sleep(10)
        wait_to_register(name, :global.whereis_name(name))
    end
    def wait_to_register(_, pid), do: pid

    defp wait_for_set(_, n, q, _, false) when n < q, do: :done
    defp wait_for_set(procs, _, q, name, _) do
        Process.sleep(10)
        s = Enum.reduce(procs, MapSet.new,
            fn p, s -> if :global.whereis_name(p) != :undefined, do: MapSet.put(s, p), else: s end)
        (fn d -> wait_for_set(d, MapSet.size(d), q, name, name in d) end).(MapSet.difference(procs, s))
    end
    def wait_for(proc_set, my_name, q) do
        (fn d, n -> wait_for_set(d, n, q, my_name, my_name in d) end).
            (proc_set, MapSet.size(proc_set))
    end

    def send_back_os_pid(pid) do
        send(pid, {:os_pid, :os.getpid()})
    end

    def wait_until_up(node) do
        Process.sleep(500)
        status = Node.ping(node)
        IO.puts("#{status}")
        case status do
            :pong -> :ok
            _ -> wait_until_up(node)
        end
    end

    def get_os_pid(node) do
        Process.sleep(1000)

        Node.spawn(node, TestHarness, :send_back_os_pid, [self()])
        # (fn pid -> Node.spawn(node,
        #     fn -> send(pid, {:os_pid, :os.getpid()}) end
        # ) end).(self())

        receive do
            {:os_pid, os_pid} -> os_pid
            after 1000 -> get_os_pid(node)
        end
    end

    def deploy_procs(func, config) do
        os_pids = for node <- MapSet.new(nodes(config)) do
            cmd = "elixir --sname " <> (hd String.split(Atom.to_string(node), "@")) <> " --no-halt --erl \"-detached\" --erl \"-kernel prevent_overlapping_partitions false\""
            cmd = String.to_charlist(cmd)
            # IO.puts("#{inspect cmd}")
            :os.cmd(cmd)
            # wait_until_up(node)
            get_os_pid(node)
        end

        pids = (fn participants ->
            for {name, {node, param}} <- config do
                case node do
                    :local -> Node.spawn(Node.self, fn -> func.(name, participants, param) end)
                    _ -> Node.spawn(node, fn -> func.(name, participants, param) end)
                end
            end
        end).(proc_names(config))
        {pids, os_pids}
    end

    def proc_names(config), do: for {name, _} <- config, do: name
    def nodes(config), do: for {_, {node, _}} <- config, node != :local, do: node

    def notify_all(procs, msg) do
        for p <- procs, do: send(p, msg)
    end

    defp sync(msg, n) do
        for _ <- 1..n do
            receive do
                ^msg -> :ok
            end
        end
    end

    defp sync_and_collect(m_type, n) do
        Enum.reduce(1..n, [],
            fn _, res ->
                [h | t] = receive do
                    msg -> Tuple.to_list(msg)
                end
                if h == m_type, do: [List.to_tuple(t) | res], else: res
            end)
    end

    defp kill_os_procs(os_pids) do
        for os_pid <- os_pids, do: :os.cmd('kill -9 ' ++ os_pid ++ ' 2>/dev/null')
    end

    # ideally should take an instance of a protocol for tested module
    def test(func, config) do
        :global.re_register_name(:coord, self())
        # pids = deploy_procs(&FloodingTest.run/2)
        {pids, os_pids} = deploy_procs(func, config)
        sync(:ready, length(config))
        notify_all(pids, :start)
        sync(:done, length(config))
        notify_all(pids, :all_done)
        # sync(:finished, length(config))
        res = sync_and_collect(:finished, length(config))
        :global.unregister_name(:coord)
        kill_os_procs(os_pids)
        res
    end
end
