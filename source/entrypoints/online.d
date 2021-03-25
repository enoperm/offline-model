module entrypoints.online;

version(online_model):

import std;
import std.traits;

import model.online;

void entrypoint(ModelContext context) {
    enum algos = () {
        AdaptationAlgorithm[] a;
        static foreach(alg; getSymbolsByUDA!(AdaptationAlgorithms, algorithm))
            a ~= &alg;
        return a;
    }();

    enum algoNames = () {
        string[] a;
        static foreach(alg; getSymbolsByUDA!(AdaptationAlgorithms, algorithm))
            a ~= __traits(identifier, alg);
        return a;
    }();

    ulong[] countsByRank = new ulong[](context.rankDistribution.length);

    SimState[algos.length] simStates =
        algos.map!(_ => SimState(context.queueCount)).array;

    Queue[][algos.length] queues =
        algos.map!(
            _ =>
                iota(context. queueCount)
                .map!(i => Queue(i, i + 1))
        ).join;

    // TODO/IMPROVE?: current output contains a lot of redundant information, but it is easy to process
    void emitState(R)(R output, ulong t, ulong selector) {
        import asdf: serializeToJson;
        static struct ReportedState {
            ulong time;
            string algorithm;
            SimState state;
            Queue[] queues;
            ulong[] countsByRank;
        }
        ReportedState s = {
            time: t,
            algorithm: algoNames[selector],
            state: simStates[selector],
            queues: queues[selector],
            countsByRank: countsByRank,
        };
        output.put(s.serializeToJson);
    }

    auto incoming =
        packets(context.rankDistribution)
        .take(context.packetCount);

    {
        auto output = stdout.lockingTextWriter;
        static foreach(i, alg; algos) emitState(output, 0, i);
        output.put('\n');
    }

    foreach(time, packet; incoming.enumerate(1)) {
        countsByRank[packet] += 1;

        static foreach(i, alg; algos) {{
            queues[i] = alg(queues[i], countsByRank, packet);
            simStates[i] = simStates[i].receivePacket(queues[i], packet);
        }}

        auto output = stdout.lockingTextWriter;
        static foreach(i, alg; algos) {{
            emitState(output, time, i);
        }}
        output.put('\n');
    }
}
