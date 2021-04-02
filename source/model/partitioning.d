module model.partitioning;

import std.range;
import std.algorithm;
import std.random;

import optional;


public:
@safe:

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
    size_t queueCount;
    double[] rankDistribution;

    invariant {
        assert(rankDistribution.length == queueCount);
        assert(queueCount > 0);
    }
}

auto lookup(const(Queue[]) queues, const(ulong) rank)
in(queues.length > 0)
in(queues.front.lower == 0)
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
import model.errors;

public:
@safe pure:

ErrorDelegate withProbabilities(ErrorFunction efn, double[] rank_probabilities) {
    return partitioning => efn(rank_probabilities, partitioning);
}

auto width(const(Queue) q)
in(q.upper > q.lower)
out(w; w >= 0)
{
    return q.upper - q.lower - 1;
}

struct ErrorGraph {
import mir.ndslice;

public alias Link = Optional!double;

private:
    Slice!(Link*, 2) adjacencyMatrix;

public:
    this(size_t node_count, ErrorDelegate fn) @trusted pure {
        this.adjacencyMatrix = [node_count + 1, node_count].slice!Link;
        ndiota(node_count + 1, node_count)
            .each!(pos =>
                pos[1] < pos[0] ?
                    this.adjacencyMatrix[pos] = fn([Queue(pos[1], pos[0])]) :

                    no!double
            );
    }

    auto nodeCount() const {
        return this.adjacencyMatrix.shape[0] - 1;
    }

    string toString() @trusted {
        import std.conv: to;
        import std.array: array, join;
        import std.string: format;

        return
            this.adjacencyMatrix
                .byDim!1
                .map!(row =>
                    row.map!(e =>
                        e.match!(
                            v => v.format!`%s`,
                            () => "*"
                        ).format!`% 4s`
                    )
                )
                .map!(row => row.format!`[ %-(%s%| %) ]`)
                .join('\n');
    }
}

auto from(ErrorGraph g, ulong node) {
    import mir.ndslice: byDim, Slice, mir_slice_kind;
    static struct PathFrom {
        Slice!(ErrorGraph.Link*, 1, mir_slice_kind.universal) outgoingEdges;

        public
        auto to(ulong node) {
            return outgoingEdges[node];
        }

        alias outgoingEdges this;
    }

    return PathFrom(g.adjacencyMatrix.byDim!1[node]);
}

@trusted
@("edges of an ErrorGraph are assigned weights according to the error function.")
unittest {
    import std;
    import std.algorithm: equal;
    import core.exception: AssertError;
    import mir.math.sum: sum;
    import mir.ndslice: byDim;

    ErrorDelegate u =
        partitioning =>
            partitioning
            .map!(q => q.width.to!double)
            .sum;

    auto eg = ErrorGraph(4, u);
    assert(
        eg.adjacencyMatrix
        .byDim!1
        .equal([
            [no!double,  some(0.0),  some(1.0),  some(2.0),  some(3.0)],
            [no!double,  no!double,  some(0.0),  some(1.0),  some(2.0)],
            [no!double,  no!double,  no!double,  some(0.0),  some(1.0)],
            [no!double,  no!double,  no!double,  no!double,  some(0.0)],
        ])
    );
}

@trusted
@("declarative distance API returns expected elements of the adjacency matrix.")
unittest {
    import std;
    import std.algorithm: equal;
    import core.exception: AssertError;
    import mir.math.sum: sum;

    ErrorDelegate u =
        partitioning =>
            partitioning
            .map!(q => q.width.to!double)
            .sum;

    auto eg = ErrorGraph(4, u);

    auto pathsFromZero = eg.from(0);
    assert(pathsFromZero.to(0) == no!double);
    assert(pathsFromZero.to(1) == some(0.0));
    assert(pathsFromZero.to(2) == some(1.0));
    assert(pathsFromZero.to(3) == some(2.0));
    assert(pathsFromZero.to(4) == some(3.0));

    auto pathsFromOne = eg.from(1);
    assert(pathsFromOne.to(0) == no!double);
    assert(pathsFromOne.to(1) == no!double);
    assert(pathsFromOne.to(2) == some(0.0));
    assert(pathsFromOne.to(3) == some(1.0));
    assert(pathsFromOne.to(4) == some(2.0));
}

auto minimalPartitioning(ErrorGraph g, size_t queueCount) @trusted pure {
    return minimalPartitioning!((s, n) => s + n)(g, queueCount);
}

auto minimalPartitioning(alias accumulate)(ErrorGraph g, size_t queueCount) @trusted pure
in(queueCount > 0, "zero queues?")
{
    import std.range: iota, retro;
    import std.algorithm: canFind, reverse, min;
    import std.conv: to;

    const k = g.adjacencyMatrix.shape[0];
    queueCount = min(k - 1, queueCount);

    auto distance = new double[][](k, k);
    Optional!size_t[][] preceeding = new Optional!size_t[][](k, k);

    preceeding.each!((ref dv) => dv[] = no!size_t);
    distance.each!((ref dv) => {dv[] = double.infinity; dv[0] = 0;}());
    auto zero = g.from(0);
    foreach(di, ref d; distance[1][1..$]) {
        d = zero.to(1 + di).front;
        preceeding[1][1 + di] = some(0);
    }

    void relax_edges(int step) {
        import std.algorithm: min;
        auto sources = iota(k - 1);
        foreach(s; sources) {
            auto sn = g.from(s);
            auto destinations = iota(s + 1, k);
            foreach(d; destinations) {
                auto td = accumulate(distance[step-1][s], sn.to(d).front);
                if(td < distance[step][d]) {
                    distance[step][d] = td;
                    preceeding[step][d] = s;
                } else if(preceeding[step][d].empty) {
                    distance[step][d] = distance[step - 1][d];
                    preceeding[step][d] = preceeding[step-1][d];
                }
            }
        }
    }

    for(auto i = 2; i <= queueCount; ++i) relax_edges(i);

    size_t[] path;
    size_t curr = k - 1;
    size_t step = queueCount;
    while(curr > 0) {
        assert(distance[step][curr] < double.infinity);

        path ~= curr;
        curr = preceeding[step][curr].front;
        --step;
    }
    reverse(path);

    auto bounds = 0.only.chain(path);
    return bounds.zip(bounds.dropOne).map!(b => Queue(b[0], b[1])).array;
}

@trusted
@("DAG-based partitioning algorithm yields expected bounds for a known error function.")
unittest {
    import std.range;
    import std.algorithm: equal, joiner;
    import core.exception: AssertError;
    import mir.math.sum: sum;

    ErrorDelegate u =
        partitioning =>
            partitioning
            .map!(q =>
                iota(q.lower, q.upper)
                .map!((packet) {
                    switch(packet) {
                    case 0: .. case 1: return 0.25;
                    case 2:            return 0.00;
                    case 3:            return 0.50;
                    case 4:            return 0.00;
                    default: assert(false);
                    }
                })
                .enumerate(q.lower)
                .map!(t => (t.index - q.lower) * t.value)
            )
            .joiner
            .sum;

    auto eg = ErrorGraph(4, u);
    auto partitionings =
        std.range.iota(1, 7)
        .map!(n => eg.minimalPartitioning(n).array)
        .array;

    assert(
        partitionings ==
        [
            // lower error rates as queue counts go up...
            [Queue(0, 4)],
            [Queue(0, 3), Queue(3, 4)],
            [Queue(0, 1), Queue(1, 3), Queue(3, 4)],

            // due to packet probabilities, more queues does not help anymore.
            [Queue(0, 1), Queue(1, 3), Queue(3, 4)],
            [Queue(0, 1), Queue(1, 3), Queue(3, 4)],
            [Queue(0, 1), Queue(1, 3), Queue(3, 4)],
        ]
    );
}
