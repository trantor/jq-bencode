def log($string):
    . as $save |
    $string |
    debug |
    $save
;

def common_length($b):
    . as $a |
    ($a|length) as $len_a |
    ($b|length) as $len_b |
    ([$len_a,$len_b] | min ) as $min |
    [ range(0;$min;1) ] |
    map($a[.] == $b[.]) |
    index(false) // $min
;

# Outputs the input character length as the length of its UTF-8-encoded version in bytes
def bytecharlength:
    utf8bytelength
;

# Outputs the input character length in UTF-8 code units
def charlength:
    1
;

# Outputs the input character length in UTF-16 code units
def u16charlength:
    if utf8bytelength > 3 then 2 else 1 end
;

# Bencode to JSON decoder
# The argument is a function returning the "length" of a character
def bdecode(length_function):

    def string_process($mode;$ichar;length_function):
        if ( .[2][2] == "length" and (.[2][3]|type == "string")) then (
            if $ichar == ":" then (
                .[2][3] |= tonumber
            ) else (
                .[2][3] |= . + $ichar
            ) end |
            if ( .[2][3] == 0 ) then (
                if $mode != "key" then (
                        .[0][-1][1] =  .[2][4] |
                        del( .[2] )
                ) else (
                    .[0][-1][0] += [.[2][4]] |
                    .[2] = [ "value" ]
                ) end
            ) else (
                .
            ) end
        ) elif ( .[2][2] == "length" and (.[2][3]|type == "number")) then (
            if ( .[2][3] == 0 ) then (
                if $mode != "key" then (
                    .[0][-1][1] =  .[2][4] |
                    del( .[2] )
                ) else (
                    .
                ) end
            ) else (
                .[2][2] |= "value" |
                .[2][3] |= . - ( $ichar | length_function ) |
                .[2][4] |= . + $ichar
            ) end |
            if ( .[2][3] == 0 ) then (
                if $mode != "key" then (
                    .[0][-1][1] =  .[2][4] |
                    del( .[2] )
                ) else (
                    .[0][-1][0] += [.[2][4]] |
                    .[2] = [ "value" ]
                ) end
            ) else (
            .
            ) end
        ) elif ( .[2][2] == "value" and .[2][3] != 0 ) then (
                .[2][3] |= . - ( $ichar | length_function ) |
                .[2][4] |= . + $ichar |
                if ( .[2][3] == 0 ) then (
                    if $mode != "key" then (
                        .[0][-1][1] =  .[2][4] |
                        del( .[2] )
                    ) else (
                        .[0][-1][0] += [.[2][4]] |
                        .[2] = [ "value" ]
                    ) end
                ) else (
                .
                ) end
        ) else (
            .
        ) end
    ;

# Wrap within a list the input
    "l\(.)e" |
# Reduce character by character
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
            [[],[]]
            # Transient array (missing here) for building keys/values/scalars
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

        # TL Length == 2 -> No value to process
        if (length == 2) then (

            # .[0][0][0] == null  -> First run
            if (.[0][0][0] == null) then (

                # Start of list
                if $item == "l" then (
                    [
                        [
                            [
                                []
                            ]
                        ],
                        [[],["array"]]
                    ]

                # Start of dictionary
                ) elif $item == "d" then (
                    [
                        [
                            [
                                []
                            ]
                        ],
                        [[],["dictionary"]]
                    ]

                # Start of integer value
                ) elif $item == "i" then (
                    [
                        [
                            [
                                [],0
                            ]
                        ],
                        [[],[]],
                        [
                            "scalar",
                            "integer",
                            ""
                        ]
                    ]

                # Start of string value
                ) else (
                    [
                        [
                            [
                                [],""
                            ]
                        ],
                        [[],[]],
                        [
                            "scalar",
                            "string",
                            "length",
                            $item,
                            ""
                        ]
                    ]
                ) end

            # Inbetween values -> Second run onwards
            ) else (

                # End of dictionary or list
                if $item == "e" then (
                    $stack[-2:] as $last_two |
                    del(.[1][1][-1]) |
                    .[1][1] as $stack |
                    ( $stack | length ) as $stack_length |

                    # If a list or dictionary closed as empty, adds it as value for the previous path
                    if $old_stack_length == $stack_length and $old_stack_length < $prev_stack_length and $prev_value == null then (
                        if $last_two[-1] == "array" then (
                            .[0][-1][1] = []
                        ) else (
                            .[0][-1][1] = {}
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
                                    # The previous iteration was the end of another list/dictionary or the start of one
                                    if ( $prev_value == null ) then (
                                        $prev_path_length - 1
                                    # The previous element had a scalar leaf value
                                    ) else (
                                        $prev_path_length
                                    ) end;

                                    # E.g. If the last element was [[0,2,"a","b",0],2]
                                    # the stack would contain ["array","array","dictionary","dictionary","array"]
                                    # Closing the array would also mean removing the dictionary key from the intermediate paths, hence
                                    # [[0,2,"a","b",0]],[[0,2,"a","b"]] added at the end of this step
                                    if (($last_two|IN(["dictionary","array"],["dictionary","dictionary"])) and ($stack_length> 1)) then (
                                        $stack_length - 2
                                    # Not "closing" a key-value pair
                                    ) else (
                                        $stack_length - 1
                                    ) end;

                                    -1
                                )
                            ] |
                            # Create the list of intermediate paths in decreasing length
                            map(
                                [ $prev_path[0:.] ]
                            )[]
                    ]

                # Start of dictionary/list/kv-pair/value
                ) else (
                    if ($stack[-1] == "array") then (
                        # First element of a new array
                        if ( $prev_path_length ) < ( $stack_length ) then (
                            .[0][-1][0] += [0]
                        # Subsequent elements
                        #) elif ( $prev_path | length ) > ( $stack | length ) then (
                        ) else (
                                .[0] +=  [[
                                    $prev_path[ 0:($stack_length -1) ] +
                                    [ $prev_path[ -1 ] + 1 ]
                                ]]
                        ) end
                    ) elif ($stack[-1] == "dictionary") then (
                        if ( $prev_path_length ) > ( $stack_length ) then (
                            .[0] +=  [[
                                $prev_path[ 0:($stack_length -1) ] +
                                [ $prev_path[ -1 ] + 1 ]
                            ]]
                        ) elif ( $prev_path_length ) < ( $stack_length ) then (
                            .
                        ) else (
                            .[0] += [[
                                $prev_path[ 0:($stack_length -1) ]
                            ]]
                        ) end
                    ) else (
                        .
                    ) end |
                    if $item == "l" then (
                        .[1][-1] += ["array"]
                    ) elif $item == "d" then (
                        .[1][-1] += ["dictionary"] |
                        .[2] =  [
                                "key"
                                ]
                    ) elif $item == "i" then (
                        . +=
                            [[
                                "scalar",
                                "integer",
                                ""
                            ]]
                    ) else (
                        if ( $stack[-1] == "dictionary") then (
                            . +=
                                [[
                                    "key",
                                    "string",
                                    "length",
                                    $item,
                                    ""
                                ]]
                        ) else (
                            . +=
                                [[
                                    "scalar",
                                    "string",
                                    "length",
                                    $item,
                                    ""
                                ]]
                        ) end
                    ) end
                ) end
            ) end
# Processing of values after the first character
        ) elif (length == 3) then (
# Scalar string
            if .[2][0] == "scalar" and .[2][1] == "string" then (
                string_process("scalar";$item;length_function)
# Scalar Integer
            ) elif .[2][0] == "scalar" and .[2][1] == "integer" then (
                if $item == "e" then (
                    ( .[2][2] | tonumber ) as $value |
                    .[0][-1][1] |= $value |
                    del( .[2] )
                ) else (
                    .[2][2] |= . + $item
                ) end
# KV-pair: key
            ) elif .[2][0] == "key" then (
                if (.[2]|length == 1) then (
                    if $item == "e" then (
                        del(.[1][1][-1]) |
                        .[0][-1][1] = {} |
                        del(.[2])
                    ) else (
                        .[2] = [ "key", "string","length",$item,"" ]
                    ) end
                ) else (
                    string_process("key";$item;length_function)
                ) end
# KV-pair: value
            ) elif .[2][0] == "value" then (
                if (.[2]|length == 1) then (
                    if $item == "i" then (
                        .[2] = [ "value", "integer","" ]
                    ) elif $item == "l" then (
                        .[1][1] += ["array"] |
                        del(.[2])
                    ) elif $item == "d" then (
                        .[1][1] += ["dictionary"] |
                        del(.[2])
                    ) else (
                        .[2] = [ "value", "string","length",$item,"" ]
                    ) end
                ) else (
                    if .[2][0] == "value" and .[2][1] == "string" then (
                        string_process("value";$item;length_function)
                    ) elif .[2][0] == "value" and .[2][1] == "integer" then (
                        if $item == "e" then (
                            ( .[2][2] | tonumber ) as $value |
                            .[0][-1][1] |= $value |
                            del( .[2] )
                        ) else (
                            .[2][2] |= . + $item
                        ) end
                    ) else (
                        .
                    ) end
                ) end
            ) else (
                .
            ) end
        ) else (
            .
        ) end |
        if .[1][1] | length > 0 then (
            .[1][0] = $prev_stack
        ) else (
            .
        ) end
    ) |
    fromstream(.[0][])[]
;

# JSON to Bencode encoder
# The argument is a function returning the "length" of a character
def bencode(length_function):

    [.] |
    [tostream] |
    reduce .[] as $item (
        ["",[[]],[]];
        .[1] as $previous |
        .[1][0] as $prev_path |
        ( .[1] | length ) as $prev_length |
        ( .[1][0] | length ) as $prev_path_length |
        .[1] |= $item |
        .[2] as $previous_stack |
        ( .[2] | length ) as $prev_stack_length |
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
        .[2] as $current_stack |
        ( .[2] | length ) as $curr_stack_length |
        .[1] as $current |
        .[1][0] as $curr_path |
        ( .[1] | length ) as $curr_length |
        ( .[1][0] | length ) as $curr_path_length |
        ( $curr_path | common_length($prev_path)) as $comm_indices |
        if $prev_path_length > 0 and $comm_indices > 0 and $curr_length == 1 then (
            .[0] += (("e" * ($previous_stack[$comm_indices:]|length  ))//"" )
        ) else (
            .[3] |= $item[0] |
            if $prev_path_length > 0 then (
                if $comm_indices < $prev_path_length then (
                    .[0] += (("e" * ($previous_stack[$comm_indices:]|length -1 ))//"" )
                ) else (
                    .
                ) end
            ) else (
                .
            ) end |
            if $prev_path_length <= $curr_path_length then (
                if $current_stack[0] == "dictionary" and $comm_indices == 0 then (
                    .[0] += "d"
                ) else (
                    .
                ) end
            ) else (
                .
            ) end |
            .[3] |= $item[0][$comm_indices:] |

            .[0] += ( reduce .[3][] as $token (
                ["",0];
                .[1] += 1 |
                if ($token|type == "number" and $token == 0) then (
                    .[0] += "l"
                ) elif ($token|type == "number") then (
                .
                ) elif ($token|type == "string") then (
                    .[0] += (
                        if .[1] == 1 then "" else "d" end +
                        ($token|reduce split("")[] as $char (0; . + ($char|length_function))|tostring) + ":" + $token
                    )
                ) else (
                    empty
                ) end
            ) |.[0] ) |
            if $item|length == 2 then (
                .[0] += (
                    if $item[1]|type == "number" then (
                        "i" + ($item[1]|tostring) + "e"
                    ) elif $item[1]|type == "string" then (
                        ($item[1]|reduce split("")[] as $char (0; . + ($char|length_function))|tostring) + ":" + $item[1]
                    ) elif $item[1]|type == "boolean" then (
                        if $item[1] == true then "i1e" else "i0e" end
                    ) elif $item[1]|type == "null" then (
                        "0:"
                    ) elif $item[1]|type == "array" then (
                        "le"
                    ) elif $item[1]|type == "object" then (
                        "de"
                    ) else (
                        ""
                    ) end
                )
            ) else (
                .
            ) end
        ) end
    )|
    .[0][1:] 
;


# Implementation of Bencode where the string length is expressed as a count of UTF-16 code units.
# So every character within the Basic Multilingual Plane requires 1 code unit
# to encode, while every character in Supplementary planes requires 2 code units.
def u16strbdecode: bdecode(u16charlength);
def u16strbencode: bencode(u16charlength);

# Implementation of Bencode where the string length is expressed as a count of UTF-8 code units.
def strbdecode: bdecode(charlength);
def strbencode: bencode(charlength);

# Implementation of Bencode (the most common one) where the string length is expressed as a byte count.
def bdecode: bdecode(bytecharlength);
def bencode: bencode(bytecharlength);

