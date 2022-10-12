#!/bin/bash

json=$@ # expect json output from cast tx -j

declare -a arr=($( jq $json '.chainId, .nonce, .maxPriorityFeePerGas, .maxFeePerGas, .gas, .to, .value, .input, .accessList, .v, .r, .s' )) # use jq to select the properties we care about

delim=""
array_string=""
# format into an array, and pad zeros where necessary
for i in "${arr[@]}"
do
    p=$(echo $i | tr -d '"') # remove the quotes
    c=$(echo $p | cut -c 3-) # remove the 0x
    if [[ $p == "[]" ]]
    then
        array_string+=$delim
        array_string+=[]
    elif [[ $(( ${#c} % 2 )) == 0 ]]
    then # even - append
        echo a
        array_string+=$delim
        array_string+=\"0x$c\"
    elif [[ $c == "0"  ]] # odd - but just zero, set to 0x
    then
        echo b
        array_string+=$delim
        array_string+=\"0x\"
    else # odd - append with additional 0
        echo c
        array_string+=$delim
        array_string+=\"0x0$c\"
    fi
    delim=","
done
array_string="[$array_string]"

# use cast to rlp encode
rlp=$(cast --to-rlp $array_string | cut -c 3-)

echo 0x02$rlp # add the 2718 transaction type
