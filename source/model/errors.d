module model.errors;

import std.traits;
import std.range;
import std.algorithm;
import std.functional;

import model;

public:

alias ErrorFunction = real function(const(real[]) rank_probabilities, const(Queue[]) partitioning) pure;
alias ErrorDelegate = real delegate(const(Queue[]) partitioning) pure;
alias ErrorAccumulatorFunction = real function(real, real) @safe pure;

private enum error;

enum ErrorKind {
    Additive,
    Max
};

private struct ErrorFuns {
static:
    @error
    auto upper_estimate(const(Queue) q, const real[] rank_probabilities, ErrorAccumulatorFunction acc) @safe pure {
        cast(void)rank_probabilities;
        cast(void)acc;
        return rank_probabilities[q.lower .. q.upper].sum * q.width / 2;
    }

    @error
    auto exact(const(Queue) queue, const real[] rank_probabilities, ErrorAccumulatorFunction acc) @safe pure {
        auto P_i = rank_probabilities[queue.lower .. queue.upper].sum;
        return
            iota(queue.lower, queue.upper)
            .map!((a) =>
                // avoid division by zero if no packets are likely to arrive
                P_i == 0 ? 0 :
                    iota(a + 1, queue.upper)
                    .map!(b => rank_probabilities[a] * rank_probabilities[b] * (b - a))
                    .sum / P_i
            )
            .fold!((a, b) => acc(a, b));
    }

    @error
    auto inversion_count(const(Queue) queue, const real[] rank_probabilities, ErrorAccumulatorFunction acc) @safe pure {
        import std.conv: to;
        auto P_i = rank_probabilities[queue.lower .. queue.upper].map!(to!real).sum;

        return
            iota(queue.lower, queue.upper)
            .map!((a) =>
                // avoid division by zero if no packets are likely to arrive
                P_i == 0 ? 0 :
                    iota(a + 1, queue.upper)
                    .map!(b => rank_probabilities[a] * rank_probabilities[b])
                    .sum / (10_000 * P_i ^^ P_i)
            )
            .fold!((a, b) => acc(a, b));
    }

    @error
    auto mass_only(const(Queue) queue, const real[] rank_probabilities, ErrorAccumulatorFunction acc) @safe pure {
        return rank_probabilities[queue.lower .. queue.upper].sum;
    }
}

private {
    import std.string: format;
    template efn(alias U, ErrorKind Kind) {

        enum acc = accumulator(Kind);
        mixin(q{
            @(%s)
            auto efn(const(real[]) rank_probabilities, const(Queue[]) partitioning) {
                return
                    partitioning
                    .map!(q => U(q, rank_probabilities, acc))
                    .fold!acc;
            }
        }.format(__traits(identifier, Kind)));
    }

    template efn_name(alias U, ErrorKind Kind) {
        enum efn_name = format!`%s_%s`(
            __traits(identifier, U),
            (){
                final switch(Kind) with(ErrorKind) {
                case Max: return "per_queue_maximum";
                case Additive: return "sum";
                }
            }()
        );
    }
}

struct ErrorEstimation {

public:
    @disable this();

static @safe pure:
    static foreach(fun; getSymbolsByUDA!(ErrorFuns, error)) {
        static foreach(kind; EnumMembers!ErrorKind) {
            @(kind)
            mixin(q{
                auto %s(const(real[]) rank_probabilities, const(Queue[]) partitioning) {
                    return efn!(fun, kind)(rank_probabilities, partitioning);
                }
            }.format(efn_name!(fun, kind)));
        }
    }
}

public
ErrorAccumulatorFunction accumulator(ErrorKind k) pure @safe {
    final switch(k) with(ErrorKind) {
    case Additive: return (a, b) => a + b;
    case Max: return (a, b) => max(a, b);
    }
}
