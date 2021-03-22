import std.stdio;
import std.algorithm;
import std.regex;
import std.conv;
import std.range;
import std.array;

version(offline_model) {
    import runnableModel = entrypoints.offline;
} else version(online_model) {
    import runnableModel = entrypoints.online;
} else {
    static assert(false);
}

enum Exit {
    Ok,
    NotEnoughArgs,
    NotEnoughWeights,
}

version(unittest) {}
else
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

    import model: ModelContext;
    ModelContext context = {
        packetCount: sim_packet_count,
        queueCount: queue_count,
        rankDistribution: rank_probabilities,
    };
    runnableModel.entrypoint(context);

    return Exit.Ok;
}
