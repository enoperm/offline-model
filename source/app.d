import std;
import std.regex: splitter;

import model;
import errors;

enum Exit {
    Ok,
    NotEnoughArgs,
    NotEnoughWeights,
}

int main(string[] args) {
    if(args[1..$].length < 2) {
        stderr.writeln(
            `usage: sp_pifo weight[,weight]* number-of-queues [simulated-packet-count]`
        );
        return Exit.NotEnoughArgs;
    }

    auto relative_weights =
        args[1]
        .splitter(`[\s,]+`.regex)
        .map!(to!ulong)
        .array;

    if(relative_weights.empty) {
        stderr.writeln(`must pass at least one weight`);
        return Exit.NotEnoughWeights;
    }

    auto total_weight = sum(relative_weights);
    auto rank_probabilities = relative_weights.map!(w => w.to!double / total_weight).array;

    auto queue_count = args[2].to!ulong;

    auto sim_packet_count = args[3..$].empty ? 0 : args[3].to!int;
    auto incoming =
        packets(rank_probabilities)
        .take(sim_packet_count);
    
    assert(rank_probabilities.length > 0);

    alias errors = getSymbolsByUDA!(ErrorEstimation, error);

    static errorNames = () {
        string[errors.length] names;
        static foreach(i, error; errors) {
            names[i] = __traits(identifier, error);
        }
        return names;
    }();

    double[errors.length] minMaxValues;
    Queue[][errors.length] minPartitions;

    minMaxValues[] = real.max;

    static foreach(i, efn; errors) {{
        auto u = withProbabilities(&efn, rank_probabilities);
        auto eg = ErrorGraph(rank_probabilities.length, u);
        minPartitions[i] = eg.minimalPartitioning(queue_count).array;
        minMaxValues[i] = u(minPartitions[i]);
    }}

    static foreach(i, efn; errors) {{
        writefln!("-----------------------\n"
                ~ "error function %s // %s\n"
                ~ "    selected partitioning: %s\n"
                ~ "    probability of packets hitting each queue: %s\n"
                ~ "    estimated error per queue: %s\n"
                ~ "    estimated total error: %s\n")(

                    i, errorNames[i],
                    minPartitions[i].map!(q => q.toString).join('~'),
                    minPartitions[i].map!(q =>
                        iota(q.lower, q.upper)
                        .map!(p => rank_probabilities[p])
                        .sum
                    ),
                    minPartitions[i].map!(queue => efn(rank_probabilities, [queue])),
                    minMaxValues[i]
        );
    }}

    SimState[errors.length] state;
    foreach(ref s; state) s = SimState(queue_count);
    ulong[ulong] packetCounts;

    void receive(ref SimState state, Queue[] partitioning, ulong packet) pure @safe
    in(partitioning.length > 0)
    {
        auto q = partitioning.countUntil!(b => b.lower <= packet && b.upper > packet);
        q = q < 0 ? partitioning.length - 1 : q;

        with(state) {
            auto inversionHappened = received[q] > 0 && packet > state.lastInQueue[q];
            inversions[q] += inversionHappened ? 1 : 0;
            lastInQueue[q] = packet;
            received[q] += 1;
        }
    }

    foreach(packet; incoming) {
        packetCounts[packet] += 1;
        foreach(i, q; minPartitions) receive(state[i], q, packet);
    }

    if(sim_packet_count > 0)
    foreach(i, simState; state) {
        auto formatQueueList(T)(T aaRange) {
            return
                aaRange
                .map!(t =>
                        format!"\n\t\t% 2s => %-5d\t(%-01.03s)"(
                            minPartitions[i][t.index].toString, t.value, t.value.to!double / sim_packet_count
                        )
                )
                .array
                .sort
                .joiner;
        }

        auto inversionsReport = formatQueueList(simState.inversions.enumerate);
        auto receivedReport = formatQueueList(simState.received.enumerate);

        writefln("-----------------------\n"
               ~ "sim result %s // partitioning chosen by %s\n"
               ~ "    queues: %s\n"
               ~ "    inversions per queue (per packet):%s\n"
               ~ "    received per queue (per packet):%s\n",

                i, errorNames[i],
                minPartitions[i].map!(p => p.toString).join(' '),
                inversionsReport,
                receivedReport
        );
    }

    return Exit.Ok;
}

version(none)
InputRange!(Queue[]) partitions(ulong count, ulong min_rank, ulong max_rank)
in(count > 0)
{
    auto outer = new Generator!(Queue[])({
        if(count == 1) {
            Queue[] leaf = [Queue(min_rank, max_rank)];
            yield(leaf);
            return;
        }

        foreach(i; min_rank .. max_rank + 2 - count) {
            auto sub = partitions(count - 1, i + 1, max_rank);
            while(!sub.empty) {
                yield([Queue(min_rank, i)] ~ sub.front);
                sub.popFront;
            }
        }
    }).inputRangeObject;
    return cast(typeof(return))outer;
}

auto packets(const(double[]) probabilities) {
    auto mins =
        probabilities
        .enumerate
        .map!(t => t.index)
        .map!(i => probabilities[0..i].sum)
        .array;

    auto selector =
        mins
        .zip(mins[1..$].chain(1.0.only))
        .enumerate;

    return generate!(() {
        const random = uniform01();
        foreach(p, bounds; selector) if(bounds[0] <= random && bounds[1] >= random) return p;
        assert(false);
    });
}
