defmodule PaxosTest do

    # The functions implement
    # the module specific testing logic
    defp init(name, participants, all \\ false) do
        cpid = TestHarness.wait_to_register(:coord, :global.whereis_name(:coord))
        try do
            pid = Paxos.start(name, participants)
            Process.sleep(100)
            if not Process.alive?(pid), do: raise "no pid"
            TestHarness.wait_for(MapSet.new(participants), name,
                        (if not all, do: length(participants)/2,
                        else: length(participants)))
            {cpid, pid}
        rescue
            _ -> {cpid, :c.pid(0,2048,0)}
        end
    end

    defp kill_paxos(pid, name) do
        Process.exit(pid, :kill)
        :global.unregister_name(name)
        pid
    end

    defp wait_for_decision(_, _, timeout) when timeout <= 0, do: {:none, :none}
    defp wait_for_decision(pid, inst, timeout) do
        Process.sleep(100)
        v = Paxos.get_decision(pid, inst, 1)
        case v do
            v when v != nil -> {:decide, v}
            nil -> wait_for_decision(pid, inst, timeout-100)
        end
    end

    defp propose_until_commit(pid, inst, val) do
        status = Paxos.propose(pid, inst, val, 10000)
        case status do
            {:decision, val} -> val
            {:abort, val} -> propose_until_commit(pid, inst, val)
            _ -> nil
        end
    end


    # Test cases start from here

    # No failures, no concurrent ballots
    def run_simple(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        {status, val, a} = receive do
            :start ->
                IO.puts("#{inspect name}: started")
                leader = (fn [h | _] -> h end).(participants)
                if name == leader do
                    Paxos.propose(pid, 1, val, 10000)
                end
                {status, v} = wait_for_decision(pid, 1, 10000)
                if status != :none do
                    IO.puts("#{name}: decided #{inspect v}")
                else
                    IO.puts("#{name}: No decision after 10 seconds")
                end
                {status, v, 10}
        end
        send(cpid, :done)
        receive do
            :all_done ->
                IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # No failures, 2 concurrent ballots
    def run_simple_2(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        {status, val, a} = receive do
            :start ->
                IO.puts("#{inspect name}: started")
                if name in (fn [h1, h2 | _] -> [h1, h2] end).(participants), do: Paxos.propose(pid, 1, val, 10000)
                {status, val} = wait_for_decision(pid, 1, 10000)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val}"),
                        else: IO.puts("#{name}: No decision after 10 seconds")
                {status, val, 10}
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

     # No failures, 2 concurrent instances
    def run_simple_3(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        {status, val, a} = receive do
            :start ->
                IO.puts("#{inspect name}: started")
                proposers = Enum.zip((fn [h1, h2 | _] -> [h1, h2] end).(participants), [1, 2])
                proposers = for {k, v} <- proposers, into: %{}, do: {k, v}
                if proposers[name], do: Paxos.propose(pid, proposers[name], val, 10000)
                y = List.to_integer((fn [_ | x] -> x end).(Atom.to_charlist((fn [h | _] -> h end).(Map.keys(proposers)))))
                :rand.seed(:exrop, {y*100+1, y*100+2, y*100+3})
                inst = Enum.random(1..2)
                {status, val} = wait_for_decision(pid, inst, 10000)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val}"),
                        else: IO.puts("#{name}: No decision after 10 seconds")
                {status, val, 10}
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # # No failures, many concurrent ballots
    def run_simple_many_1(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        {status, val, a} = receive do
            :start ->
                IO.puts("#{inspect name}: started")
                Paxos.propose(pid, 2, val, 10000)
                Process.sleep(Enum.random(1..10))
                {status, val} = wait_for_decision(pid, 2, 10000)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val}"),
                        else: IO.puts("#{name}: No decision after 10 seconds")
                {status, val, 10}
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # No failures, many concurrent ballots
    def run_simple_many_2(name, participants, val) do
        {cpid, pid} = init(name, participants)
        send(cpid, :ready)
        {status, val, a} = receive do
            :start ->
                IO.puts("#{inspect name}: started")
                for _ <- 1..10 do
                    Process.sleep(Enum.random(1..10))
                    Paxos.propose(pid, 1, val, 10000)
                end
                {status, val} = wait_for_decision(pid,1, 10000)
                if status != :none, do: IO.puts("#{name}: decided #{inspect val}"),
                        else: IO.puts("#{name}: No decision after 10 seconds")
                {status, val, 10}
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # # One non-leader process crashes, no concurrent ballots
    def run_non_leader_crash(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = receive do
            :start ->
                IO.puts("#{inspect name}: started")

                [leader, kill_p | spare] = participants

                case name do
                    ^leader ->
                        Paxos.propose(pid, 1, val, 10000)
                    ^kill_p ->
                        Process.sleep(Enum.random(1..5))
                        Process.exit(pid, :kill)
                    _ -> nil
                end

                spare = [leader | spare]

                if name in  spare do
                    {status, val} = wait_for_decision(pid, 1, 10000)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val}"),
                        else: IO.puts("#{name}: No decision after 10 seconds")
                    {status, val, 10, spare}
                else
                    {:killed, :none, -1, spare}
                end
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # # Minority non-leader crashes, no concurrent ballots
    def run_minority_non_leader_crash(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = try do
            receive do
                :start ->
                    IO.puts("#{inspect name}: started")

                    [leader | rest] = participants

                    to_kill = Enum.slice(rest, 0, div(length(participants),2))

                    if name == leader do
                        Paxos.propose(pid, 1, val, 10000)
                    end

                    if name in to_kill do
                        Process.sleep(Enum.random(1..5))
                        Process.exit(pid, :kill)
                    end

                    spare = for p <- participants, p not in to_kill, do: p

                    if name in spare do
                        {status, val} = wait_for_decision(pid, 1, 10000)
                        if status != :none, do: IO.puts("#{name}: decided #{inspect val}"),
                            else: IO.puts("#{name}: No decision after 10 seconds")
                        {status, val, 10, spare}
                    else
                        {:killed, :none, -1, spare}
                    end
            end
        rescue
            _ -> {:none, :none, 10, []}
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # # Leader crashes, no concurrent ballots
    def run_leader_crash_simple(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = try do
            receive do
                :start ->
                    IO.puts("#{inspect name}: started")

                    [leader | spare] = participants
                    [new_leader | _] = spare


                    if name == leader do
                        Paxos.propose(pid, 1, val, 10000)
                        Process.sleep(Enum.random(1..5))
                        Process.exit(pid, :kill)
                    end

                    if (name == new_leader) do
                        Process.sleep(10)
                        propose_until_commit(pid, 1, val)
                    end

                    if name in spare do
                        {status, val} = wait_for_decision(pid, 1, 10000)
                        if status != :none, do: IO.puts("#{name}: decided #{inspect val}"),
                            else: IO.puts("#{name}: No decision after 10 seconds")
                        {status, val, 10, spare}
                    else
                        {:killed, :none, -1, spare}
                    end
            end
        rescue
            _ -> {:none, :none, 10, []}
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # # Leader and some non-leaders crash, no concurrent ballots
    # # Needs to be run with at least 5 process config
    def run_leader_crash_simple_2(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = receive do
            :start ->
                IO.puts("#{inspect name}: started")
                leader = (fn [h | _] -> h end).(participants)
                if name == leader do
                    Paxos.propose(pid, 1, val, 10000)
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                spare = Enum.reduce(List.delete(participants, leader), List.delete(participants, leader),
                    fn _, s -> if length(s) > length(participants) / 2 + 1, do: tl(s), else: s
                    end
                )

                leader = hd(spare)

                if name not in spare do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name == leader do
                    Process.sleep(10)
                    propose_until_commit(pid, 1, val)
                end

                if name in spare do
                    {status, val} = wait_for_decision(pid, 1, 10000)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val}"),
                        else: IO.puts("#{name}: No decision after 10 seconds")
                    {status, val, 10, spare}
                else
                    {:killed, :none, -1, spare}
                end
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # # Cascading failures of leaders and non-leaders
    def run_leader_crash_complex(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = receive do
            :start ->
                IO.puts("#{inspect name}: started with #{inspect participants}")

                {kill, spare} = Enum.reduce(participants, {[], participants},
                    fn _, {k, s} -> if length(s) > length(participants) / 2 + 1,
                        do: {k ++ [hd(s)], tl(s)}, else: {k, s}
                    end
                )

                leaders = Enum.slice(kill, 0, div(length(kill), 2))
                followers = Enum.slice(kill, div(length(kill), 2), div(length(kill), 2) + 1)

                # IO.puts("spare = #{inspect spare}")
                # IO.puts "kill: leaders, followers = #{inspect leaders}, #{inspect followers}"

                if name in leaders do
                    Paxos.propose(pid, 1, val, 10000)
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if name in followers do
                    Process.sleep(Enum.random(1..5))
                    Process.exit(pid, :kill)
                end

                if hd(spare) == name do
                    Process.sleep(10)
                    propose_until_commit(pid, 1, val)
                end

                if name in spare do
                    {status, val} = wait_for_decision(pid, 1, 50000)
                    if status != :none, do: IO.puts("#{name}: decided #{inspect val}"),
                        else: IO.puts("#{name}: No decision after 50 seconds")
                    {status, val, 10, spare}
                else
                    {:killed, :none, -1, spare}
                end
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

    # # Cascading failures of leaders and non-leaders, random delays
    def run_leader_crash_complex_2(name, participants, val) do
        {cpid, pid} = init(name, participants, true)
        send(cpid, :ready)
        {status, val, a, spare} = try do
            receive do
                :start ->
                    IO.puts("#{inspect name}: started")

                    {kill, spare} = Enum.reduce(participants, {[], participants},
                        fn _, {k, s} -> if length(s) > length(participants) / 2 + 1,
                            do: {k ++ [hd(s)], tl(s)}, else: {k, s}
                        end
                    )

                    leaders = Enum.slice(kill, 0, div(length(kill), 2))
                    followers = Enum.slice(kill, div(length(kill), 2), div(length(kill), 2) + 1)

                    IO.puts("spare = #{inspect spare}")
                    IO.puts "kill: leaders, followers = #{inspect leaders}, #{inspect followers}"

                    if name in leaders do
                        Paxos.propose(pid, 1, val, 10000)
                        Process.sleep(Enum.random(1..5))
                        Process.exit(pid, :kill)
                    end

                    if name in followers do
                        for _ <- 1..10 do
                            :erlang.suspend_process(pid)
                            Process.sleep(Enum.random(1..5))
                            :erlang.resume_process(pid)
                        end
                        Process.exit(pid, :kill)
                    end

                    if hd(spare) == name do
                        Process.sleep(10)
                        Paxos.propose(pid, 1, val, 10000)
                    end

                    if name in spare do
                        for _ <- 1..10 do
                            :erlang.suspend_process(pid)
                            Process.sleep(Enum.random(1..5))
                            :erlang.resume_process(pid)
                            leader = hd(Enum.reverse spare)
                            if name == leader, do: Paxos.propose(pid, 1, val, 10000)
                        end
                        leader = hd(spare)
                        if name == leader, do: propose_until_commit(pid, 1, val)
                        {status, val} = wait_for_decision(pid, 1, 50000)
                        if status != :none, do: IO.puts("#{name}: decided #{inspect val}"),
                            else: IO.puts("#{name}: No decision after 50 seconds")
                        {status, val, 10, spare}
                    else
                        {:killed, :none, -1, spare}
                    end
            end
        rescue
            _ -> {:none, :none, 10, []}
        end
        send(cpid, :done)
        receive do
            :all_done ->
                Process.sleep(100)
                ql = if name in spare do
                    IO.puts("#{name}: #{inspect (ql = Process.info(pid, :message_queue_len))}")
                    ql
                else
                    {:message_queue_len, -1}
                end
                kill_paxos(pid, name)
                send cpid, {:finished, name, pid, status, val, a, ql}
        end
    end

end
