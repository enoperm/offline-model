module model.common;

import std.range;
import std.algorithm;
import std.random;

import optional;

public:
@safe:

struct SimState {
    ulong[] inversions;
    ulong[] lastInQueue;
    ulong[] received;

    this(size_t queue_count) {
        static foreach(fname; __traits(allMembers, typeof(this))) {{
            alias f = __traits(getMember, this, fname);
            alias T = typeof(f);
            static if(__traits(compiles, new T(queue_count))) f = new T(queue_count);
        }}
    }
}

struct Queue {
immutable {
    ulong lower;
    ulong upper;
}

    string toString() const {
        import std.string: format;
        return format!"[%2s, %2s)"(this.lower, this.upper);
    }

    version(none)
    invariant {
        import std.string: format;
        assert(lower < upper, format!`[%s, %s)`(lower, upper));
    }
}

struct ModelContext {
public:
    size_t packetCount, queueCount;
    double[] rankDistribution;

    invariant {
        assert(rankDistribution.length == queueCount);
        assert(queueCount > 0);
    }
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

auto lookup(const(Queue[]) queues, const(ulong) rank)
in(queues.length > 0)
//in(queues.front.lower == 0)
out(index; index.empty || index.front < queues.length && index.front >= 0)
out(index; index.empty || queues[index.front].lower <= rank && queues[index.front].upper > rank)
{
    foreach(i, const q; queues) if(q.lower <= rank && q.upper > rank) {
        return some(i);
    }
    return no!size_t;
}

@("queue lookup returns no index when no existing queue could accept the packet")
unittest
{
    auto queues = [Queue(0,2), Queue(2, 8)];
    assert(queues.lookup(10).empty);
}

@("queue lookup returns expected indices")
unittest
{
    import std.algorithm: map;
    auto queues = [Queue(0,2), Queue(2, 8)];
    auto expected = [0, 0, 1, 1, 1, 1, 1, 1];
    auto got = iota(8).map!(p => queues.lookup(p)).array;

    assert(expected == got);
}

SimState receivePacket(SimState sim, const(Queue[]) queues, ulong rank) pure @safe
in(rank < queues.back.upper)
in(queues.length > 0)
in(queues.zip(queues.dropOne).all!(pair => pair[0].upper == pair[1].lower))
{
    const target = queues.lookup(rank).front;

    SimState next = sim;
    with(next) {
        const inversionHappened = received[target] > 0 && rank < lastInQueue[target];
        inversions[target] += inversionHappened ? 1 : 0;
        lastInQueue[target] = rank;
        received[target] += 1;
    }
    return next;
}

@("SimState.receivePacket tracks inversions")
unittest {
    const queues = [Queue(0, 2), Queue(2, 4)];
    auto s = SimState(queues.length);

    // no inversion in queue case
    s = s.receivePacket(queues, 0);
    s = s.receivePacket(queues, 1);

    assert(s.inversions == [0, 0]);

    // no inversion across queues
    s = s.receivePacket(queues, 3);
    s = s.receivePacket(queues, 1);

    assert(s.inversions == [0, 0]);

    // inversion within queues
    s = s.receivePacket(queues, 1);
    s = s.receivePacket(queues, 0);

    assert(s.inversions == [1, 0]);

    s = s.receivePacket(queues, 3);
    s = s.receivePacket(queues, 2);

    assert(s.inversions == [1, 1]);

    // after inversion,
    // packets of the same rank are not counted
    // as further inversions.
    
    s = s.receivePacket(queues, 2);
    assert(s.inversions == [1, 1]);
}

