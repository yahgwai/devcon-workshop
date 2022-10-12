# Demystifying L2 transactions

This workshop follows through sending transactions on Arbitrum, inspecting their lifecycle and how much gas they use.

## Useful links
* Arbitrum One RPC - https://arb-mainnet.g.alchemy.com/v2/cAVH7BTBvbzIucuwkjbltCH-RxNkFCe1
* Ethereum RPC - https://mainnet.infura.io/v3/6faa1b9b8d274a7f96192e868a65f6d4
* Follow along tx id if not sending your own-  `0xb6f34cb1a7ef3d6d2e062815df80b47a151cd10026227a7f5326912a257602bb`
* L1/L2 gas -https://developer.arbitrum.io/arbos/gas
* Transaction lifecycle - https://developer.arbitrum.io/tx-lifecycle
* ArbOS precompiles - https://developer.arbitrum.io/arbos/precompiles
* RLP encoding - https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/

## Prerequisites
Please install the following, if you don't have them already
* An ethereum wallet (eg metamasdk browser extension)
* [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) - version control system
* [curl](https://curl.se/) - A http request util, probably installed by default
* [Foundry](https://github.com/foundry-rs/foundry) - tools for, amongst other things, making ethereum JSON-RPC requests
    - run: `curl -L https://foundry.paradigm.xyz | bash`
    - followed by `foundryup`
* [jq](https://stedolan.github.io/jq/) - might be installed by default
    - Mac OS - `brew install jq`
    - Ubuntu - `apt get install jq` 
* [brotli](https://github.com/google/brotli) - compression algorithm
    - Mac OS - `brew install brotli`
    - Ubuntu - `apt get install brotli` 

You may need to open a new shell after installing these

## Setup
In a new shell do the following:
1. Git clone, or download, this repo
    ```
    git clone git@github.com:yahgwai/devcon-workshop.git
    ```
1. Test foundry exists - if it doesn't foundry installed properly.
    ```
    cast --version
    ```
2. Test curl exists
    ```
    curl --version
    ```
3. Test jq exists
    ```
    jq --version
    ```
2. Set the ARB_RPC env var
    ```
    ARB_RPC=https://arb-mainnet.g.alchemy.com/v2/cAVH7BTBvbzIucuwkjbltCH-RxNkFCe1
    ```
3. Set the ETH_RPC env var
    ```
    ETH_RPC=https://mainnet.infura.io/v3/6faa1b9b8d274a7f96192e868a65f6d4
    ```

## Step 1 - Send an L2 transaction
Since this workshop involves comparing L1 and L2 gas it's more informative to use the values from mainnet and Arbitrum One, rather than testnets where gas price are artificially low. This means that we'll be sending a transaction on Arbitrum One, using real ETH. At the time of writing a transaction costs around ~$0.05, however if you don't have ETH available on Arbitrum One already you can still follow on with this workshop by using the following transaction hash wherever a transaction hash is required: `0xb6f34cb1a7ef3d6d2e062815df80b47a151cd10026227a7f5326912a257602bb`


Once you've chosen a transaction hash to use, set it as an environment variable 
```
TX_ID=<tx id>
```

## Step 2 - Inpect the transaction receipt
1. Get the transaction receipt by calling the ARB_ONE rpc, and prettify with jq.
    ```
    curl -s -X POST -H "Content-Type: application/json" \
    -d '{ "jsonrpc": "2.0", "method": "eth_getTransactionReceipt", "params": [ "'$TX_ID'" ], "id": 0 }' \
    $ARB_RPC | jq
    ```
2. An Arbitrum transaction receipt has two additional properties
    - `l1BlockNumber` - The number used in the EVM if `block.number` was accessed during the transaction
    - `gasUsedForL1` - The amount of gas used to pay for l1 overheads, expressed in units of L2 gas.
3. View the `gasUsedForL1` as a decimal.
    
3. Store `gasUsedForL1` from the transaction receipt as decimal in an env var:
    ```
    GAS_USED_L1=$((<tx.gasUsedForL1>))
    ```
    And view the result:
    ```
    echo $GAS_USED_L1
    ```
    Is the value what you expected? You might have expected this value to be much lower as all we need L1 gas for is to pay for call data. Call data is only 16 gas per byte, and standard token transfer only has around 190 bytes when [RLP](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/) encoded. A quick calculation shows that we should have expected to use around 16 * 180 = 2880 units of l1 gas which probably isn't the same order of magnitude as the value you have for `gasUsedForL1`. But remember that although `gasUsedForL1` pays for L1 costs, it is in units of L2 gas. We'll explore that concept more in the nexts stepts.
4. Also store the value of blockhash and block number for later use:
    ```
    L2_BLOCKHASH=<tx.blockHash>
    L2_BLOCKNUM=<tx.blockNumber>
    ```

### Step 3 - Getting the L1 base fee estimate as seen on L2
1. Lets try to convert `gasUsedForL1` from units of L2 gas to L1 gas to see if the amount matches up with our rought estimate above. To do that we need to find out:
    - What the L1 base fee was at the time, as seen by the L2
    - What the L2 base fee was at the time
2. The L2 periodically receives information about the L1 base fee and updates it's local view. It also adjusts it based on how the accuracy of previous estimates. You can read more about this process [here]( https://developer.arbitrum.io/arbos/l1-pricing#adjusting-the-l1-gas-basefee).
3. In order to find out what the L1 base fee estimate was at the time we can query the [getL1BaseFeeEstimate](https://github.com/OffchainLabs/nitro/blob/v2.0.7/contracts/src/precompiles/ArbGasInfo.sol#L93) function on the ArbGasInfo precompile which can be found at address `0x000000000000000000000000000000000000006c`. We can use `cast` to make this call, taking care to specify that we want the value as it was at the time the transaction was sent using the `L2_BLOCKHASH` var.
    ```
    cast call --rpc-url $ARB_RPC -b $L2_BLOCKHASH 0x000000000000000000000000000000000000006c 'function getL1BaseFeeEstimate() external view returns (uint256)'
    ```
4. Store the result in an env var
    ```
    L1_BASE_FEE_EST=<l1 base fee estimate>
    ```

### Step 4 - Getting the L2 base fee at the time the tx was sent
1. In order to make the conversion we can fetch the base fee with cast:
    ```
    cast block --rpc-url $ARB_RPC $L2_BLOCKHASH baseFeePerGas
    ```
2. Gas on Arbitrum is usually much lower than on L2. It also has a hard coded minimum of 0.1 Gwei, which you may be observing now.
3. Store the result in an env var
    ```
    L2_BASE_FEE=<l2 base fee>
    ```
4. We can now calculate the `gasUsedForL1` in terms of L1 gas by multiplying by the ratio of l2 to l1 base fees.
    ```
    echo $(( $GAS_USED_L1 * $L2_BASE_FEE / $L1_BASE_FEE_EST ))
    ```
    You should get a value which is closer to the rough calculation we made in step 2.3.
5. From the gas used we can also estimate the number bytes by [dividing by 16](https://eips.ethereum.org/EIPS/eip-2028):
    ```
    echo $(( $GAS_USED_L1 * $L2_BASE_FEE / $L1_BASE_FEE_EST / 16 ))
    ```

### Step 5 - comparison to actual bytes
1. We can now [RLP](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/) encode the transaction and measure the number of bytes. Note that we don't expect this to be exactly the same due to a number of reasons:
    - The gas used for L1 includes some compression factor - this isn't as high as when we the transaction is included in a batch, but it is a factor
    - There is also a small amount L1 gas that must be paid for batch overheads
2. RLP encode the transaction:
    ```
    TX_RLP=$(cast tx -j --rpc-url $ARB_RPC $TX_ID | ./txToRaw.sh)
    echo $TX_RLP
    ```
3. Count the bytes, it should be a similar number to one calculated from gas used
    ```
    echo $(( (${#TX_RLP} - 2) / 2 ))
    ```

### Step 6 - Exploring the batch
1. The data associated with transactions is submitted to Ethereum in batches. Each of these batches is compressed using brotli compression to further reduce the on-chain footprint of Arbitrum.
2. Find the batch associated with your transaction using [findBatchContainingBlock](https://github.com/OffchainLabs/nitro/blob/v2.0.7/contracts/src/node-interface/NodeInterface.sol#L60) function on the NodeInterface contract.
    ```
    BATCH_NUM=$(cast call --rpc-url $ARB_RPC 0x00000000000000000000000000000000000000C8 "function findBatchContainingBlock(uint64 blockNum) external view returns (uint64 batch)" $L2_BLOCKNUM)

    echo $BATCH_NUM
    ```
3. The batch is only available in transaction call data, so we need to find the transaction in which this batch was submitted.

    ```
    BATCH_TX_ID=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{ "jsonrpc": "2.0", "method": "eth_getLogs", "params": [ { "fromBlock": "0x00", "toBlock": "latest", "address": "0x1c479675ad559dc151f6ec7ed3fbf8cee79582b6", "topics": [ "0x7394f4a19a13c7b92b5bb71033245305946ef78452f7b4986ac1390b5df4ebd7", "'$(cast --to-int256 $BATCH_NUM)'" ]} ], "id": 0 }' \
    $ETH_RPC | jq '.result[].transactionHash' | tr -d '"')

    echo $BATCH_TX_ID
    ```
4. The sequencer submits the batch via the [addSequencerL2BatchFromOrigin](https://github.com/OffchainLabs/nitro/blob/v2.0.0/contracts/src/bridge/SequencerInbox.sol#L143) function on the SequencerInbox. The batch is the data field in the call data. Given the fixed size of the other arguments we can be sure that the data field starts at position 458 in the call data. Let's download the data, then save everything after position 458 to file.
    ```
    BATCH_TX_DATA=$(cast tx --rpc-url $ETH_RPC $BATCH_TX_ID input)
    echo ${BATCH_TX_DATA:458} > txDataField.br
    ```
5. Open the file and take a look at the contents. You will see that it begins with `00`. This first byte specifies what type of data this is. In this case `00` means that the data has been compressed using brotli compression. Lets remove this first byte.
    ```
    tail -c +3 txDataField.br > compressedBatchData.br
    ```
    Then decompress the rest by converting this hex string, then using brotli decompression, then converting back into hex. This may output the warning `corrupt input [con]`, but you can ignore this. It's there due to trailing zeros in the input file, but doesn't affect the decompression.
    ```
    xxd -r -p compressedBatchData.br | brotli -d | xxd -c 200000000 -ps > batchData.txt
    ```
6. Now that the batch has been decoded, let's see how effective the compression was. Run the following to print the size of the files:
    ```
    ls -l
    ```
    Now compare the size of `batchData.txt` with `compressedBatchData.br`
7. Finally, open `batchData.txt` in a text editor. Can find your RLP encoded transaction - $TX_RLP - in the data?