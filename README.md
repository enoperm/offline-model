## Dependencies:

As far as I am aware, the only build dependency is [dub](https://dub.pm),
a package manager/build system for the [D programming language](https://dlang.org).

## Testing

```sh
dub test
```

## Running

Building and running:
```sh
dub build
./compare_fw weight[,weight]* number-of-queues [simulated-packet-count]
```

Alternatively, build and run in the same step while editing
to ensure you always observe the output of the current version of the code:
```sh
dub run -- weight[,weight]* number-of-queues [simulated-packet-count]
```
