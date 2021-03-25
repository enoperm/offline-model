module entrypoints.offline;

version(offline_model):

import std;
import std.regex: splitter;

import model;
import errors;

void entrypoint(ModelContext context) {
    auto incoming =
        packets(context.rankDistribution)
        .take(context.packetCount);
    
    assert(context.rankDistribution.length > 0);

    alias errors = getSymbolsByUDA!(ErrorEstimation, ErrorKind);

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
        enum errorKind = getUDAs!(efn, ErrorKind)[$-1];
        enum accumulationFunction = errorKind.accumulator;

        auto u = withProbabilities(&efn, context.rankDistribution);
        auto eg = ErrorGraph(context.rankDistribution.length, u);

        minPartitions[i] = eg.minimalPartitioning!(accumulationFunction)(context.queueCount).array;
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
                        .map!(p => context.rankDistribution[p])
                        .sum
                    ),
                    minPartitions[i].map!(queue => efn(context.rankDistribution, [queue])),
                    minMaxValues[i]
        );
    }}

    SimState[errors.length] state;
    foreach(ref s; state) s = SimState(context.queueCount);
    ulong[ulong] packetCounts;

    foreach(packet; incoming) {
        packetCounts[packet] += 1;
        foreach(i, q; minPartitions) {
            state[i] = state[i].receivePacket(minPartitions[i], packet);
        }
    }

    if(context.packetCount > 0)
    foreach(i, simState; state) {
        auto formatQueueList(T)(T aaRange) {
            return
                aaRange
                .map!(t =>
                        format!"\n\t\t% 2s => %-5d\t(%-01.03s)"(
                            minPartitions[i][t.index].toString, t.value, t.value.to!double / context.packetCount
                        )
                )
                .array
                .sort
                .joiner;
        }

        auto inversionsReport = formatQueueList(simState.inversions.enumerate);
        auto receivedReport = formatQueueList(simState.received.enumerate);
        auto totalInversions = simState.inversions.sum;

        writefln("-----------------------\n"
               ~ "sim result %s // partitioning chosen by %s\n"
               ~ "    queues: %s\n"
               ~ "    total inversions: %s (%s)\n"
               ~ "    inversions per queue (per packet):%s\n"
               ~ "    received per queue (per packet):%s\n",

                i, errorNames[i],
                minPartitions[i].map!(p => p.toString).join(' '),
                totalInversions, totalInversions.to!double / context.packetCount,
                inversionsReport,
                receivedReport
        );
    }
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
