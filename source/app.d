import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.regex;
import std.stdio;

import model;

enum Exit {
    Ok,
    NotEnoughArgs,
    NotEnoughWeights,
}

version(unittest) {}
else
int main(string[] args) {
    if(args[1..$].length != 2) {
        stderr.writeln(
            `usage: sp_pifo weight[,weight]* number-of-queues`
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

    import model: ModelContext;
    ModelContext context = {
        queueCount: queue_count,
        rankDistribution: rank_probabilities,
    };
    solve(context);

    return Exit.Ok;
}

void solve(ModelContext context) {
    import std.traits: getSymbolsByUDA, getUDAs;
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

    ModelOutput report;
    static foreach(i, efn; errors) with(report) {
        name = errorNames[i];
        bounds = minPartitions[i].map!(q => q.lower.to!ulong).array;
        perQueueErrors = minPartitions[i].map!(queue => efn(context.rankDistribution, [queue])).array;
        perQueueProbablities =
            minPartitions[i]
                .map!(q => iota(q.lower, q.upper)
                    .map!(p => context.rankDistribution[p])
                    .sum
                ).array;
        import asdf: serializeToJson;
        stdout.writeln(report.serializeToJson);
    }
}

struct ModelOutput {
    string name;
    ulong[] bounds;
    double[] perQueueProbablities;
    double[] perQueueErrors;
}
