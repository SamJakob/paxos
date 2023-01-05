defmodule TestUtil do

    def get_node(host), do: String.to_atom(UUID.uuid1 <> "@" <> host)

    def get_dist_config(host, n) do
        for i <- (1..n), into: %{}, do:
            {String.to_atom("p"<>to_string(i)), {get_node(host), {:val, Enum.random(201..210)}}}
    end

    def get_local_config(n) do
        for i <- 1..n, into: %{}, do:
            {String.to_atom("p"<>to_string(i)), {:local, {:val, Enum.random(201..210)}}}
    end

    def pause_stderr(d) do
        my_pid = self()
        spawn(fn -> pid=Process.whereis(:standard_error);
            :erlang.suspend_process(pid);
            send(my_pid, {:suspended})
            Process.sleep(d);
            :erlang.resume_process(pid) end)
        receive do
            {:suspended} -> :done
        end
    end
end
