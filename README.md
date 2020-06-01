Investigations of string escape sequence parsing, for incorporation into [slox][slox].

In particular I was interested in the relative speeds of the two basic options for approaching this in Swift code. The obvious choice is to use Swift's `String`, `Character`, and `Unicode` APIs, which became [useCharacter.swift](useCharacter.swift). Presumably faster but also much more fiddly would be handling the input's raw data, processing it via pointers. This option is in [raw.swift](raw.swift).

After creating those two, I also wrote [an implementation in C](c_impl.c) to see how the Swift pointer version compared. Then, for good measure, I reworked raw.swift to be closer to the C version; this ended up being called [rawMorePointer.swift](rawMorePointer.swift).

# Making it happen

[The Makefile](Makefile) has two main "commands": `time` and `diff`. Both first ensure that an input file exists, which is created by the generateInput.swift helper. A file made up of plain text and randomly-generated escape sequences like `\u{01f600}` is produced. By default the file is somewhere between 4 and 5 MB.

The `time` command runs that input through the three Swift versions and the C implementation, discarding the output and just showing how long each execution took.

The `diff` command validates the implementations are by producing a sort of "golden master" with Swift's help:

- putting the input text into a Swift script such that it's enclosed in a multiline string and just printed out,
- running that script -- in other words, making the Swift compiler parse and render the same input* that's going into my implementations, and then
- diffing that output with the output of each of my implementations

The diff result for each implementation is written to a file in case there are errors. Since the `diff` utility returns non-zero when it find differences, `make` will also report an error, which we can interpret as a test failure.

## Results

Typical outcomes show that the C implementation is by far the fastest, and the `Character`-based Swift version is slowest. Hardly a surprise, of course. The two "raw" Swift implementations are approximately equal, with maybe a tiny edge, only seen with large input, for the "more raw" version.

The `Character`-based implementation is unfortunately also quite a bit slower than the raw ones -- by an order of magnitude and then some. Typical results (~4.7 MB input file, MacBook Pro 2.2 GHz Intel Core i7, 16 GB RAM):

```
% make time
time ./build/raw >/dev/null

real	0m0.188s
user	0m0.175s
sys	0m0.011s
time ./build/rawMorePointer >/dev/null	

real	0m0.184s
user	0m0.171s
sys	0m0.009s
time ./build/useCharacter >/dev/null

real	0m3.451s
user	0m3.429s
sys	0m0.014s
time ./build/c_impl >/dev/null

real	0m0.020s
user	0m0.013s
sys	0m0.004s
```

So far, I haven't put much effort into studying the details of the performance differences, so there may very well be improvements that could be made to useCharacter.swift. It's worth noting that, aside from `-Onone`/`-O0`**, the level of optimization doesn't make much difference to the relative times. (I also recorded an odd pothole I encountered on the perf-cliff branch.) 

I expect to base the slox implementation on the rawMorePointer.swift version; I actually find it slightly simpler and clearer to not use the buffer and slicing bits that are in raw.swift.

## Note on licensing

My code in this repo is MIT-licensed, but among the UTF-8 encoding implementations I studied was some code from the Swift stdlib, which I ended up adapting for the raw.swift implementation. This is marked out in the source, and the [SWIFT_ORG_LICENSE.txt file](SWIFT_ORG_LICENSE.txt) is included to accompany my adaptation.

---

*This is why I chose the `\u{...}` format for the Unicode escapes, which may not end up being what I use in slox.

**The results are actually quite weird^Winteresting with optimization disabled: on my machine, useCharacter.swift runs about as fast, as does the C implementation. rawMorePointer.swift becomes around 3x slower than its optimized version. But raw.swift goes from 20x faster than to _3x slower than_ useCharacter.swift -- ~3.5 seconds vs. almost 10!!

[slox]: https://github.com/woolsweater/slox
