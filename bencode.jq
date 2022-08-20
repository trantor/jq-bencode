def _log($string):
    . as $save |
    $string |
    debug |
    $save
;

# Outputs the input character length as the length of its UTF-8-encoded version in bytes
def _bytecharlength:
    utf8bytelength
;

# Outputs the input character length in UTF-8 code units
def _charlength:
    1
;

# Outputs the input character length in UTF-16 code units
def _u16charlength:
    if utf8bytelength > 3 then 2 else 1 end
;

# Bencode to JSON decoder
# The argument is a function returning the "length" of a character
def _bdecode(length_function):

    def integer_process($ichar):
#  $ichar: current character of the Bencode-d input being processed
        if $ichar == "e" then (
        # End of the integer string representation: converts it to an actual integer
            ( .[2][2] | tonumber ) as $value |
            # Adds the leaf value to the current path
            .[0][-1][1] |= $value |
            # Deletes the transient work structure
            del( .[2] )
        ) else (
        # Builds the string representation of the integer value
            .[2][2] |= . + $ichar
        ) end
    ;

    def string_process($ichar;length_function):
#  $ichar: current character of the Bencode-d input being processed
#  length_function: the filter matching the character length algorithm used for the Bencode-d string
#
#  .[2] ->  [
#  "standalone" or "key" or "value",
#  "string",
#  "length" or "value",
#  "", Length of the string, filled as a string while .[2][2] is "length", a number afterwards
#  ""  Actual string contents
#  ]

        def zero_length_check:
        # Function checking for strings fully processed and performing actions at that point
            if .[2][3] == 0 then (
            # String length at 0: empty string and/or end of the string
                if .[2][0] == "key" then (
                # Adds the key to the current path
                    .[0][-1][0] += [.[2][4]] |
                # Switches to evaluating the value of the KV-pair
                    .[2] = [ "value" ]
                ) else (
                # KV-pair value or standalone string
                    # Writing the string as leaf value of the current path
                    .[0][-1][1] = .[2][4] |
                    # Deletes the transient work structure: end of string processing
                    del( .[2] )
                ) end
            ) else (
            # Not the end of the string: proceeds from here
                .
            ) end
        ;

        if .[2][2] == "length" and (.[2][3]|type) == "string" then (
        # Building the string length from the prefix
            if $ichar == ":" then (
            # End of prefix length: converts it to a number for later use
                .[2][3] |= tonumber |
                zero_length_check
            ) else (
            # Filling the prefix length
                .[2][3] |= . + $ichar
            ) end
        ) elif .[2][2] == "length" and (.[2][3]|type) == "number" then (
        # Prefix length evaluation ended: first character of the actual contents
            # Value mode
            .[2][2] |= "value" |
            # Decreases the string length by the current character's length according
            # to length_function
            .[2][3] |= . - ( $ichar | length_function ) |
            # Appends $ichar to the output string
            .[2][4] |= . + $ichar |
            zero_length_check
        ) elif .[2][2] == "value" and .[2][3] != 0 then (
            # Decreases the string length by the current character's length according
            # to length_function
            .[2][3] |= . - ( $ichar | length_function ) |
            # Appends $ichar to the output string
            .[2][4] |= . + $ichar |
            zero_length_check
        ) else (
            error("This shouldn't be possible!")
        ) end
    ;

# Wraps within a list the input
    "l\(.)e" |
# Reduces character by character the input Bencode-d string
    reduce split("")[] as $item (
        # Initial state
        [
            # Array accumulating stream elements for output
            [
                [
                    null
                ]
            ],
            # [ previous_stack_of_structures, current_stack_of_structures ]
            [ [], [] ]
            # Transient array (missing here) for building keys/values/standalones
        ];

        #
        # Start of the iterative code
        #
        # Convenient aliases
        .[1][1] as $stack |
        .[1][1] as $prev_stack |
        .[1][0] as $old_stack |
        ( $stack | length ) as $stack_length |
        ( $prev_stack | length ) as $prev_stack_length |
        ( $old_stack | length ) as $old_stack_length |

        .[0][-1] as $prev |
        .[0][-1][0] as $prev_path |
        .[0][-1][1] as $prev_value |
        ( $prev_path | length ) as $prev_path_length |

        if length == 2 then (
        # TL Length == 2 -> No value to process

            if (.[0][0][0] == null) then (
            # .[0][0][0] == null  -> First run

                if $item == "l" then (
                # Start of list
                    [
                        [
                            [
                                []
                            ]
                        ],
                        [ [], ["array"] ]
                    ]

                ) elif $item == "d" then (
                # Start of dictionary
                    [
                        [
                            [
                                []
                            ]
                        ],
                        [ [], ["dictionary"] ]
                    ]

                ) elif $item == "i" then (
                # Start of integer value
                    [
                        [
                            [
                                [],0
                            ]
                        ],
                        [ [], [] ],
                        [
                            "standalone",
                            "integer",
                            ""
                        ]
                    ]

                ) else (
                # Start of string value
                    [
                        [
                            [
                                [],""
                            ]
                        ],
                        [ [], [] ],
                        [
                            "standalone",
                            "string",
                            "length",
                            $item,
                            ""
                        ]
                    ]
                ) end

            ) else (
            # Inbetween values -> Second run onwards

                if $item == "e" then (
                # End of dictionary or list
                    $stack[-2:] as $last_two |

                    # Removes the last element (array/dictionary) we are closing from the stack
                    del(.[1][1][-1]) |
                    .[1][1] as $stack |
                    ( $stack | length ) as $stack_length |

                    if $old_stack_length == $stack_length and $old_stack_length < $prev_stack_length and $prev_value == null then (
                    # If a list or dictionary closed as empty, adds it as value for the previous path
                        if $last_two[-1] == "array" then (
                            .[0][-1][1] = []
                        ) elif $last_two[-1] == "dictionary" then (
                            .[0][-1][1] = {}
                        ) else (
                            error("This shouldn't be possible!")
                        ) end
                    ) else (
                        .
                    ) end |

                    # Adds intermediate paths to continue
                    # E.g. if the last element was [[0,"a"],2] and the dictionary ended, add [[0,"a"]]
                    .[0] += [
                            # Calculates the number of intermediate paths needed
                        [
                            range(
                                if ( $prev_value == null ) then (
                                # The previous iteration was the end of another list/dictionary or the start of one
                                    $prev_path_length - 1
                                ) else (
                                # The previous element had a standalone leaf value
                                    $prev_path_length
                                ) end;


                                if (
                                    (
                                        $last_two |
                                        IN( ["dictionary","array"], ["dictionary","dictionary"] )
                                    ) and $stack_length > 1
                                ) then (
                                # If the last element was, for instance, [[0,2,"a","b",0],2]
                                # the stack would contain ["array","array","dictionary","dictionary","array"]
                                # Closing the trailing array would also mean removing the dictionary key from the intermediate paths, hence
                                # [[0,2,"a","b",0]],[[0,2,"a","b"]] added at the end of this step
                                    $stack_length - 2
                                ) else (
                                # Not "closing" a key-value pair
                                    $stack_length - 1
                                ) end;


                                # Negative step
                                -1
                            )
                        ] |
                        # Creates the list of intermediate paths in decreasing length
                        # by slicing the last element multiple times with decreasing
                        # ranges provided by the "range" function above.
                        # If no intermediate paths needs to be added "range" outputs
                        # an empty list.
                        map(
                            [ $prev_path[0:.] ]
                        )[]
                    ]

                ) else (
                # Start of dictionary/list/KV-pair/value
                    if $stack[-1] == "array" then (
                        if $prev_path_length < $stack_length then (
                        # First element of a new array
                            .[0][-1][0] += [0]
                        ) elif $prev_path_length == $stack_length then (
                        # Subsequent elements
                            .[0] += [[
                                $prev_path[ 0:($stack_length - 1) ] +
                                [ $prev_path[ -1 ] + 1 ]
                            ]]
                        ) else (
                            error("This shouldn't be possible!")
                        ) end
                    ) elif $stack[-1] == "dictionary" then (
                        if $prev_path_length == $stack_length then (
                        # "Closes" the KV-pair and possibly the dictionary if it's the last KV-pair
                            .[0] += [[
                                $prev_path[ 0:($stack_length - 1) ]
                            ]]
                        ) elif $prev_path_length < $stack_length then (
                        # A new KV-pair opened: nothing to do
                            .
                        ) else (
                            error("This shouldn't be possible!")
                        ) end
                    ) else (
                        error("This shouldn't be possible!")
                    ) end |


                    if $item == "l" then (
                    # Starting a list/array: adds that to the stack
                        .[1][-1] += ["array"]
                    ) elif $item == "d" then (
                    # Starting a dictionary: adds that to the stack
                        .[1][-1] += ["dictionary"] |
                    # Starting a dictionary: goes into key processing of the KV-pair
                        .[2] =  [
                                "key"
                                ]
                    ) elif $item == "i" then (
                    # Start of an integer standalone value
                        . +=
                            [[
                                "standalone",
                                "integer",
                                ""
                            ]]
                    ) else (
                        if $stack[-1] == "dictionary" then (
                        # Starts processing the prefix length of the key of a KV-pair
                            . +=
                                [[
                                    "key",
                                    "string",
                                    "length",
                                    $item,
                                    ""
                                ]]
                        ) else (
                        # Starts processing the prefix length of a standalone string value
                            . +=
                                [[
                                    "standalone",
                                    "string",
                                    "length",
                                    $item,
                                    ""
                                ]]
                        ) end
                    ) end
                ) end
            ) end
        ) elif length == 3 then (
        # Processing of values after the first character
            if .[2][0] == "standalone" and .[2][1] == "string" then (
            # Standalone string
                string_process($item;length_function)
            ) elif .[2][0] == "standalone" and .[2][1] == "integer" then (
            # Standalone integer
                integer_process($item)
            ) elif .[2][0] == "key" then (
            # KV-pair: key
                if (.[2]|length == 1) then (
                # Starting processing the first character of the key
                    if $item == "e" then (
                    # Empty dictionary: writing it as leaf value of the current path
                        del(.[1][1][-1]) |
                        .[0][-1][1] = {} |
                    # Deletes the transient work structure
                        del(.[2])
                    ) else (
                    # Transient ds with the first character of the prefix key length
                        .[2] = [ "key", "string","length",$item,"" ]
                    ) end
                ) else (
                # Processing from the second character of the prefix length of the key
                # to the end of the actual key
                    string_process($item;length_function)
                ) end
            ) elif .[2][0] == "value" then (
            # KV-pair: value
                if (.[2]|length == 1) then (
                # Processing the first character of the value part of a KV-pair
                    if $item == "i" then (
                    # Integer value: transient ds for the processing of the value
                        .[2] = [ "value", "integer","" ]
                    ) elif $item == "l" then (
                    # Nested array/list
                        .[1][1] += ["array"] |
                        # Deleting the transient ds to leave the value processing phase
                        del(.[2])
                    ) elif $item == "d" then (
                    # Nested dictionary
                        .[1][1] += ["dictionary"] |
                        # Deleting the transient ds to leave the value processing phase
                        del(.[2])
                    ) else (
                    # String value: transient ds with the first character of the prefix value length
                        .[2] = [ "value", "string","length",$item,"" ]
                    ) end
                ) else (
                # Processing from the second character of integer/string values onwards
                    if .[2][0] == "value" and .[2][1] == "integer" then (
                    # Integer value: processing
                        integer_process($item)
                    ) elif .[2][0] == "value" and .[2][1] == "string" then (
                    # String value: processing
                        string_process($item;length_function)
                    ) else (
                        error("This shouldn't be possible!")
                    ) end
                ) end
            ) else (
                error("This shouldn't be possible!")
            ) end
        ) else (
            error("This shouldn't be possible!")
        ) end |
        if .[1][1] | length > 0 then (
        # Saves the "previous" stack for the next iteration
            .[1][0] = $prev_stack
        ) else (
        # Unless we've finished processing the input
            .
        ) end
    ) |
    # Converts the stream representation into a JSON DS, removing the initial list wrapping
    fromstream(.[0][0:-1][])[]
;

# JSON to Bencode encoder
# The argument is a function returning the "length" of a character
def _bencode(length_function):

# Function expressing the length of the leading
# slice of an array/list common to both the input
# and $b. Which also coincides with the index of
# the first element which differs between the two
# lists.
    def common_length($b):
        . as $a |
        ($a|length) as $len_a |
        ($b|length) as $len_b |
        ([$len_a,$len_b] | min ) as $min |
        [ range(0;$min;1) ] |
        map($a[.] == $b[.]) |
        index(false) // $min
    ;

# Function computing the length of its string argument
# following the string length conventions of "length_function"
    def string_length(length_function):
        reduce split("")[] as $char (
            # Initial state
            0;
            . + ( $char | length_function )
        ) |
        tostring
    ;

# Wraps within a list the input
    [.] |
# Generates a streaming form of the wrapped input, wrapped into a list
    [tostream] |
# Processes the streaming form list elements through "reduce", with each
# subsequent element aliased to $item
    reduce .[] as $item (
        # Initial reduce data structure
        [
            # String accumulating the Bencode-d form of the input
            "",
            # Data from previous iteration
            [
                []
            ],
            # Data stack from previous iteration
            []
            # Working container object (missing at the start here)
        ];

        # Aliases for the previous iteration elements
        .[1] as $previous |
        .[1][0] as $prev_path |
        ( .[1] | length ) as $prev_length |
        ( .[1][0] | length ) as $prev_path_length |
        .[2] as $previous_stack |
        ( .[2] | length ) as $prev_stack_length |

        # Processes the new stream element
        .[1] |= $item |
        # Builds the stack from the new stream element
        # (e.g. from [[0,2,"a",0,"b",0],2] build
        # ["array","array","dictionary","array","dictionary","array"] )
        .[2] |= (
                $item[0] |
                map(
                    if type == "number" then (
                        "array"
                    ) else (
                        "dictionary"
                    ) end
                )
            ) |

        # Aliases for the current iteration elements
        .[2] as $current_stack |
        ( .[2] | length ) as $curr_stack_length |
        .[1] as $current |
        .[1][0] as $curr_path |
        ( .[1] | length ) as $curr_length |
        ( .[1][0] | length ) as $curr_path_length |

        # Find the index of the first different element between
        # the paths of the previous and the current stream elements
        ( $curr_path | common_length($prev_path)) as $divergence_index |

        if $prev_path_length > 0 and $divergence_index > 0 and $curr_length == 1 then (
        # Add a closing mark (i.e. "e") for each list/dictionary still open once
        # we've reached the base level of the input data
            .[0] += (
                (
                    "e" * ( $previous_stack[$divergence_index:] | length )
                ) // ""
            )
        ) else (
            if $prev_path_length > 1 then (
                if $divergence_index + 1 < $prev_path_length  then (
                # One or more data structures have been closed since the last iteration: adds
                # the appropriate number of markers (i.e. "e") to reflect that
                #
                # Let's take the "bencode" function input to be [ [[[1]]], {"a":{"b":{"c":2}}} ] .
                # With the initial list wrapping, the stream element before the start
                # of the dictionary will be
                # [[0,0,0]]
                # followed by
                # [[0,1,"a","b","c"],2]
                # The index at which the paths diverge is 1, but that's the index of the array key.
                # The same would go for a dictionary.
                # Hence we count the number of elements following the aforementioned index as the
                # number of end markers (i.e. "e") we have to add.
                    .[0] += (
                        (
                            "e" * ( $previous_stack[$divergence_index+1:] | length )
                        ) // ""
                    )
                ) else (
                    .
                ) end
            ) else (
                .
            ) end |
            # Copy the trailing portion of the current path which differs from
            # the one of the previous iteration for further processing
            .[3] |= $item[0][$divergence_index:] |

            # Adds any start of dictionary/list marker (i.e. "d" or "l") needed
            .[0] += (
                reduce .[3][] as $key (
                    [
                        # Bencode-d string accumulator
                        "",
                        # Index of the key being processed
                        0
                    ];
                    if ( $key | type == "number" and $key == 0 ) then (
                    # The key is a number and that number is 0, hence we are at the start of a list/array
                        .[0] += "l"
                    ) elif ( $key | type == "number" ) then (
                    # The key is a number different from 0, we are within a list/array
                    .
                    ) elif ( $key | type == "string" ) then (
                    # The key is a string, hence there's a dictionary
                        .[0] += (
                            (
                                # Adds a start of dictionary marker unless the key index is 0
                                # (which means that a new key-value pair is being added to a
                                # previously opened dictionary)
                                if .[1] == 0
                                then ""
                                else "d"
                                end
                            ) + (
                                # Adds the dictionary key in Bencode-d form
                                $key |
                                # Computes the length of the key according to our definition of string length
                                string_length( length_function )
                            ) + ":" + $key
                        )
                    ) else (
                    # We should never reach this fork
                        error("This should not happen!")
                    ) end |
                    # Increase the key index counter
                    .[1] += 1
                ) |
                # Extracts the Bencode-d string
                .[0]
            ) |
            if $item | length == 2 then (
                # We are looking at a stream leaf element (i.e. we have an actual value)
                .[0] += (
                    # Translates values in Bencode-d forms, with a few implementation choices
                    # where data types have no direct correspondance
                    if $item[1] | type == "number" then (
                        "i" + ( $item[1] | tostring ) + "e"
                    ) elif $item[1] | type == "string" then (
                        (
                            $item[1] |
                            # Computes the length of the string value according to our definition of string length
                            string_length( length_function )
                        ) + ":" + $item[1]
                    ) elif $item[1] | type == "boolean" then (
                    # We choose to represent boolean values as "1" or "0" integer values
                        if $item[1] == true
                        then "i1e"
                        else "i0e"
                        end
                    ) elif $item[1] | type == "null" then (
                    # We choose to represent null values as empty strings
                        "0:"
                    ) elif $item[1] | type == "array" then (
                        "le"
                    ) elif $item[1] | type == "object" then (
                        "de"
                    ) else (
                        # We should never reach this fork
                        error("This should not happen!")
                    ) end
                )
            ) else (
                .
            ) end
        ) end
    )|
    # Removes the leading "l" coming from the list wrapper at the start
    .[0][1:]
;


# Implementation of Bencode where the string length is expressed as a count of UTF-16 code units.
# So every character within the Basic Multilingual Plane requires 1 code unit
# to encode, while every character in Supplementary planes requires 2 code units.
def u16strbdecode: _bdecode(_u16charlength);
def u16strbencode: _bencode(_u16charlength);

# Implementation of Bencode where the string length is expressed as a count of UTF-8 code units.
def strbdecode: _bdecode(_charlength);
def strbencode: _bencode(_charlength);

# Implementation of Bencode (the most common one) where the string length is expressed as a byte count.
def bdecode: _bdecode(_bytecharlength);
def bencode: _bencode(_bytecharlength);

