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

        return currentQueues.map!(q => Queue(q.lower, q.upper)).array;
    }
}
