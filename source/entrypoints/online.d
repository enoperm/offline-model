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

    SimState[algos.length] simStates =
        algos.map!(_ => SimState(context.queueCount)).array;

    Queue[][algos.length] queues =
        algos.map!(
            _ =>
                iota(context. queueCount)
                .map!(i => Queue(i, i + 1))
        ).join;

    static foreach(i, alg; algos) {{
        writeln("alg found: ", algoNames[i]);
    }}
}
