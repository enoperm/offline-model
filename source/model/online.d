module model.online;
public import model.common;

import std.algorithm: all;
import std.range;

import optional;

alias PacketCounts = ulong[/* rank */];
alias AdaptationAlgorithm = Queue[] function(const(Queue[]) currentQueues, const(PacketCounts) byRank, ulong receivedRank) pure @safe;

enum algorithm;

struct AdaptationAlgorithms {
public:
    @disable this();

static @safe pure:

    @algorithm
    Queue[] pupd(const(Queue[]) currentQueues, const(PacketCounts) byRank, ulong receivedRank) {
        import std.algorithm;
        import std.array;

        auto bounds = currentQueues.map!(q => q.lower).array.dup;

        auto pushDown() {
            pragma(inline, true);

            immutable cost = bounds.front - receivedRank;
            foreach(ref b; bounds) b -= cost;
        }

        auto pushUp(ulong target) {
            pragma(inline, true);
            bounds[target] = receivedRank;
        }

        if(receivedRank < bounds.front) pushDown();
        else {
            auto target = currentQueues.lookup(receivedRank);
            if(target.empty) target = some(bounds.length - 1); // TODO: rework internals to have a single bound per queue as in the papers.
            pushUp(target.front);
        }

        auto seq = bounds.chain(only(max(bounds[$-1]+1, currentQueues.back.upper)));
        return
            seq
            .zip(seq.dropOne)
            .map!(t => Queue(t[0], t[1]))
            .array;
    }
}

version(unittest):
import std;

@("pupd: NSDI '20 example input produces known expected output")
unittest {
    immutable inputs = [4, 3, 2, 3];
    immutable expected = [
        [Queue(0, 4), Queue(4, 5)],
        [Queue(3, 4), Queue(4, 5)],
        [Queue(2, 3), Queue(3, 5)],
        [Queue(2, 3), Queue(3, 5)],
    ];

    Queue[] current = [Queue(0, 1), Queue(0, 1)];
    foreach(i, input; inputs) {
        current = AdaptationAlgorithms.pupd(current, [], input);
        assert(current == expected[i], format!`%s: %s -> %s`(i, input, current));
    }
}
