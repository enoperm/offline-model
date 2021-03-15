module errors;

import std.traits;
import std.range;
import std.algorithm;
import std.functional;

import model;

public:

alias ErrorFunction = double function(const(double[]) rank_probabilities, const(Queue[]) partitioning) pure;
alias ErrorDelegate = double delegate(const(Queue[]) partitioning) pure;

enum ErrorKind {
    Additive,
    Max
};

struct ErrorEstimation {
public:
    @disable this();

static @safe pure:
    @(ErrorKind.Additive)
    auto per_queue_maximum(const(double[]) rank_probabilities, const(Queue[]) partitioning) {
        return
            partitioning
            .map!(b => rank_probabilities[b.lower .. b.upper - 1].sum * b.width)
            .fold!((a, b) => max(a, b));
    }

    @(ErrorKind.Max)
    auto global_maximum(const(double[]) rank_probabilities, const(Queue[]) partitioning) {
        return
            partitioning
            .map!(b => rank_probabilities[b.lower .. b.upper - 1].sum * b.width)
            .sum;
    }
}

double function(double, double) accumulator(ErrorKind k) pure @safe {
    final switch(k) with(ErrorKind) {
    case Additive: return (a, b) => a + b;
    case Max: return (a, b) => max(a, b);
    }
}
