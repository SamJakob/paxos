# Replace with your own implementation source files
# IEx.Helpers.c "beb.ex", "."
# IEx.Helpers.c "paxos.ex", "."

# Do not modify the following ##########
IEx.Helpers.c "test_with_mix/test_harness.ex", "."
IEx.Helpers.c "test_with_mix/paxos_test.ex", "."
IEx.Helpers.c "test_with_mix/test_util.ex", "."
# IEx.Helpers.c "uuid.ex", "."

host = String.trim(to_string(:os.cmd('hostname -s')))

# ###########

test_suite = [
    # test case, configuration, number of times to run the case, description
    # Use TestUtil.get_dist_config(host, n) to generate a multi-node configuration
    # consisting of n processes, each one on a different node.
    # Use TestUtil.get_local_config(n) to generate a single-node configuration
    # consisting of n processes, all running on the same node.

    {&PaxosTest.run_simple/3, TestUtil.get_local_config(3), 10, "No failures, no concurrent ballots, 3 local procs"},
    {&PaxosTest.run_simple/3, TestUtil.get_dist_config(host, 3), 10, "No failures, no concurrent ballots, 3 nodes"},
    {&PaxosTest.run_simple/3, TestUtil.get_local_config(5), 10, "No failures, no concurrent ballots, 5 local procs"},

    {&PaxosTest.run_simple_2/3, TestUtil.get_dist_config(host, 3), 10, "No failures, 2 concurrent ballots, 3 nodes"},
    {&PaxosTest.run_simple_2/3, TestUtil.get_local_config(3), 10, "No failures, 2 concurrent ballots, 3 local procs"},

    {&PaxosTest.run_simple_3/3, TestUtil.get_local_config(3), 10, "No failures, 2 concurrent instances, 3 local procs"},

    {&PaxosTest.run_simple_many_1/3, TestUtil.get_dist_config(host, 5), 10, "No failures, many concurrent ballots 1, 5 nodes"},
    {&PaxosTest.run_simple_many_1/3, TestUtil.get_local_config(5), 10, "No failures, many concurrent ballots 1, 5 local procs"},



    {&PaxosTest.run_simple_many_2/3, TestUtil.get_dist_config(host, 5), 10, "No failures, many concurrent ballots 2, 5 nodes"},
    {&PaxosTest.run_simple_many_2/3, TestUtil.get_local_config(5), 10, "No failures, many concurrent ballots 2, 5 local procs"},

    {&PaxosTest.run_non_leader_crash/3, TestUtil.get_dist_config(host, 3), 10, "One non-leader crashes, no concurrent ballots, 3 nodes"},
    {&PaxosTest.run_non_leader_crash/3, TestUtil.get_local_config(3), 10, "One non-leader crashes, no concurrent ballots, 3 local procs"},


    {&PaxosTest.run_minority_non_leader_crash/3, TestUtil.get_dist_config(host, 5), 10, "Minority non-leader crashes, no concurrent ballots"},
    {&PaxosTest.run_minority_non_leader_crash/3, TestUtil.get_local_config(5), 10, "Minority non-leader crashes, no concurrent ballots"},



    {&PaxosTest.run_leader_crash_simple/3, TestUtil.get_dist_config(host, 5), 10, "Leader crashes, no concurrent ballots, 5 nodes"},
    {&PaxosTest.run_leader_crash_simple/3, TestUtil.get_local_config(5), 10, "Leader crashes, no concurrent ballots, 5 local procs"},


    {&PaxosTest.run_leader_crash_simple_2/3, TestUtil.get_dist_config(host, 7), 10, "Leader and some non-leaders crash, no concurrent ballots, 7 nodes"},
    {&PaxosTest.run_leader_crash_simple_2/3, TestUtil.get_local_config(7), 10, "Leader and some non-leaders crash, no concurrent ballots, 7 local procs"},

    {&PaxosTest.run_leader_crash_complex/3, TestUtil.get_dist_config(host, 11), 10, "Cascading failures of leaders and non-leaders, 11 nodes"},
    {&PaxosTest.run_leader_crash_complex/3, TestUtil.get_local_config(11), 10, "Cascading failures of leaders and non-leaders, 11 local procs"},

    {&PaxosTest.run_leader_crash_complex_2/3, TestUtil.get_dist_config(host, 11), 10, "Cascading failures of leaders and non-leaders, random delays, 7 nodes"},
    {&PaxosTest.run_leader_crash_complex_2/3, TestUtil.get_local_config(11), 10, "Cascading failures of leaders and non-leaders, random delays, 7 local procs"},
]


Node.stop
# Confusingly, Node.start fails if epmd is not running.
# epmd can be started manually with "epmd -daemon" or
# will start automatically whenever any Erlang VM is
# started with --sname or --name option.
Node.start(TestUtil.get_node(host), :shortnames)
Enum.reduce(test_suite, length(test_suite),
     fn ({func, config, n, doc}, acc) ->
        IO.puts(:stderr, "============")
        IO.puts(:stderr, "#{inspect doc}, #{inspect n} time#{if n > 1, do: "s", else: ""}")
        IO.puts(:stderr, "============")
        for _ <- 1..n do
                res = TestHarness.test(func, Enum.shuffle(Map.to_list(config)))
                # IO.puts("#{inspect res}")
                {vl, al, ll} = Enum.reduce(res, {[], [], []},
                   fn
                      {_, _, s, v, a, {:message_queue_len, l}}, {vl, al, ll} ->
                        # if s not in [:killed, :none], do: {[v | vl], [a | al], [l | ll]},
                        if s not in [:killed], do: {[v | vl], [a | al], [l | ll]},
                        else: {vl, al, ll}
                      {_, _, _, _, _, nil}, {vl, al, ll} -> {vl, al, ll}
                   end
                )
                # IO.puts("#{inspect vl}")
                termination = vl != [] and :none not in vl
                agreement = termination and MapSet.size(MapSet.new(vl)) == 1
                {:val, agreement_val} = if agreement, do: hd(vl), else: {:val, -1}
                validity = agreement_val in 201..210
                safety = agreement and validity
                TestUtil.pause_stderr(100)
                if termination and safety do
                        too_many_attempts = (get_att = (fn a -> 10 - a + 1 end)).(Enum.max(al)) > 5
                        too_many_messages_left = Enum.max(ll) > 10
                        warn = if too_many_attempts, do: [{:too_many_attempts, get_att.(Enum.max(al))}], else: []
                        warn = if too_many_messages_left, do: [{:too_many_messages_left, Enum.max(ll)} | warn], else: warn
                        IO.puts(:stderr, (if warn == [], do: "PASS", else: "PASS (#{inspect warn})"))
                        # IO.puts(:stderr, "#{inspect res}")
                else
                        IO.puts(:stderr, "FAIL\n\t#{inspect res}")
                end
        end
        IO.puts(:stderr, "============#{if acc > 1, do: "\n", else: ""}")
        acc - 1
     end)
:os.cmd('/bin/rm -f *.beam')
Node.stop
System.halt
