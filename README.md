# jq-bencode
Bencode encoder/decoder module for jq

## Description

This is a module for [jq](https://stedolan.github.io/jq) whose purpose is to provide ways to convert JSON structures into [Bencode](https://en.wikipedia.org/wiki/Bencode)-d strings and the other way around.

The conversion is lossy, since Bencode has no notion of _null_ or _boolean_ values, unlike JSON. Null values will be converted to empty strings, while boolean values to `0` or `1` integer values.

## Interface

The module provides three pairs of functions/filters for external consumption, each pair containing a Bencode encoder and decoder.
The reason there isn't just one such pair of filters stems from the author's original motivation in writing such an implementation for `jq`, that is processing serialised metadata used by the [Zimbra project](https://github.com/Zimbra), a [Collaboration Suite](https://en.wikipedia.org/wiki/Zimbra), internally. The serialisation is achieved through Bencode, however the string length is not computed counting the number of bytes the string encodes into but rather as the count of UTF-16 code units used for its representation (given how the main component of the software is Java-based).
Behind the scenes, each of the filter pairs calls the same internal filter pairs implementing Bencode encoding/decoding and providing as argument another filter implementing the specific computation of a single character's length according to the intended algorithm.

### Standard Bencode

String length as the count of bytes resulting from its encoding via UTF-8

`bencode/0`: JSON to Bencode conversion  
`bdecode/0`: Bencode to JSON conversion


### String length as character count

String length as the count of UTF-8 code units (which should be identical to the number of codepoints used in the string).

`strbencode/0`: JSON to Bencode conversion  
`strbdecode/0`: Bencode to JSON conversion


### String length as count of UTF-16 code units needed to represent the data

String length as the count of UTF-16 code units needed to encode the string. Each character outside the [BMP](https://en.wikipedia.org/wiki/Plane_(Unicode)#Basic_Multilingual_Plane) needs two UTF-16 code units to encode (see [here](https://en.wikipedia.org/wiki/UTF-16#Code_points_from_U+010000_to_U+10FFFF)).

`u16strbencode/0`: JSON to Bencode conversion  
`u16strbdecode/0`: Bencode to JSON conversion

## Implementation notes

The actual implementation of the encoder/decoder relies on `jq`'s [streaming parsing](https://stedolan.github.io/jq/manual/#Streaming), which turns a data structure into a list of path expressions, some of them with leaf values, some of them not.
The internal `_bencode` function takes a streaming form of the JSON input and through `reduce` processes it generating the Bencode-d output.
The internal `_bdecode` function instead processes the Bencode-d string character by character through `reduce`, generating a streaming JSON form which is converted to a JSON data structure via `fromstream` at the end.

## Examples

After copying `bencode.jq` in one of the directories of the `jq` modules search path (see `jq`'s documentation) or using `jq`'s `-L` option to reference the directory containing the module file:

```
$ jq --null-input -L ~/jq-bencode '
import "bencode" as bencdec;

["a",[],{},[{}],{"a":[{"b":[2]}],"f":""},1,{"c":{"d":[]}},"a"] | bencdec::bencode
'

"l1:aledeldeed1:ald1:bli2eeee1:f0:ei1ed1:cd1:dleee1:ae"


$ jq --null-input -L ~/jq-bencode '
import "bencode" as bencdec;

["a",[],{},[{}],{"a":[{"b":[2]}],"f":""},1,{"c":{"d":[]}},"a"] | bencdec::bencode | bencdec::bdecode
'
["a",[],{},[{}],{"a":[{"b":[2]}],"f":""},1,{"c":{"d":[]}},"a"]

# In the case above we can achieve round-trip encoding/decoding since the are no null or boolean values in the input.


# Let's see the different string length implementations below using an emoji
# 😃 encodes to F0 9F  98 83, a 4-byte sequence using UTF-8; it's 1 codepoint (U+1F603) but it requires 2 UTF-16 code units (D83D DE03) to be represented.

$ jq --null-input -L ~/jq-bencode '
import "bencode" as bencdec;

[ "😃" ] | bencdec::bencode
'
"l4:😃e"


$ jq --null-input -L ~/jq-bencode '
import "bencode" as bencdec;

[ "😃" ] | bencdec::strbencode
'
"l1:😃e"

$ jq --null-input -L ~/jq-bencode '
import "bencode" as bencdec;

[ "😃" ] | bencdec::u16strbencode
'
"l2:😃e"

```

## Limitations

Bencode does not specify the encoding used in its string data. This implementation takes for granted the use of UTF-8 for string encoding, since that's the only legal encoding for JSON string data. Problems may arise if, for instance, byte strings within a Bencode-d string are the end result of a different encoding.
