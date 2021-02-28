module errors;

import std.range;
import std.algorithm;
import std.functional;

import model;

public:

enum error;
alias ErrorFunction = double function(const(double[]) rank_probabilities, const(Queue[]) partitioning) pure;
alias ErrorDelegate = double delegate(const(Queue[]) partitioning) pure;

private template isErrorFunction(F) {
    enum isErrorFunction = is(F == ErrorFunction);
}

private template overloadsOf(holder, string fname) {
    alias overloadsOf = __traits(getOverloads, holder, fname);
}

struct ErrorEstimation {
public:
    @disable this();

static @safe pure:

    version(currently_not_applicable_to_dag_based_partitioning)
    @error
    auto per_queue_maximum(const(double[]) rank_probabilities, const(Queue[]) partitioning) {
        return
            partitioning
            .map!(b => rank_probabilities[b.lower .. b.upper - 1].sum * b.width)
            .fold!((a, b) => max(a, b));
    }

    @error
    auto global_maximum(const(double[]) rank_probabilities, const(Queue[]) partitioning) {
        return
            partitioning
            .map!(b => rank_probabilities[b.lower .. b.upper - 1].sum * b.width)
            .sum;
    }

}
