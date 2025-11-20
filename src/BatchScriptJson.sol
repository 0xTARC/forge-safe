// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

// 💬 ABOUT
// Gnosis Safe transaction batching script - JSON file output version

// 🧩 MODULES
import {Script, console2, StdChains, stdJson, stdMath, StdStorage, stdStorageSafe, VmSafe} from "forge-std/Script.sol";

// ⭐️ SCRIPT
abstract contract BatchScriptJson is Script {
    using stdJson for string;

    // Hash constants
    // Safe version for this script, hashes below depend on this
    string private constant VERSION = "1.3.0";

    // keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

    // keccak256(
    //     "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
    // );
    bytes32 private constant SAFE_TX_TYPEHASH =
        0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8;

    // Deterministic deployment address of the Gnosis Safe Multisend contract, configured by chain.
    address private SAFE_MULTISEND_ADDRESS;

    // Chain ID, configured by chain.
    uint256 private chainId;

    // Address to send transaction from
    address private safe;

    // Filename for JSON output
    string private outputFilename;

    enum Operation {
        CALL,
        DELEGATECALL
    }

    struct Batch {
        address to;
        uint256 value;
        bytes data;
        Operation operation;
        uint256 safeTxGas;
        uint256 baseGas;
        uint256 gasPrice;
        address gasToken;
        address refundReceiver;
        uint256 nonce;
        bytes32 txHash;
        bytes signature;
    }

    bytes[] public encodedTxns;

    // Modifiers

    modifier isBatch(address safe_, string memory filename_) {
        // Set the chain ID
        chainId = block.chainid;

        // Set the multisend address based on chain
        if (chainId == 1) {
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        } else if (chainId == 5) {
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        } else if (chainId == 42161) {
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        } else if (chainId == 43114) {
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        } else if (chainId == 81457 ) {
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        } else if (chainId == 11155111) {
            SAFE_MULTISEND_ADDRESS = 0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761;
        }
        else {
            revert("Unsupported chain");
        }

        // Store the provided safe address and output filename
        safe = safe_;
        outputFilename = filename_;

        // Run batch
        _;
    }

    // Functions to consume in a script

    // Adds an encoded transaction to the batch.
    function addToBatch(
        address to_,
        uint256 value_,
        bytes memory data_
    ) internal returns (bytes memory) {
        // Add transaction to batch array
        encodedTxns.push(abi.encodePacked(Operation.CALL, to_, value_, data_.length, data_));

        // Simulate transaction and get return value
        vm.prank(safe);
        (bool success, bytes memory data) = to_.call{value: value_}(data_);
        if (success) {
            return data;
        } else {
            revert(string(data));
        }
    }

    // Convenience function to add an encoded transaction to the batch
    function addToBatch(address to_, bytes memory data_) internal returns (bytes memory) {
        // Add transaction to batch array
        encodedTxns.push(abi.encodePacked(Operation.CALL, to_, uint256(0), data_.length, data_));

        // Simulate transaction and get return value
        vm.prank(safe);
        (bool success, bytes memory data) = to_.call(data_);
        if (success) {
            return data;
        } else {
            revert(string(data));
        }
    }

    // Create batch and dump to JSON file
    function executeBatch(uint256 nonce_) internal {
        Batch memory batch = _createBatch(safe, nonce_);
        _dumpBatchToJson(safe, batch);
    }

    // Private functions

    // Encodes the stored encoded transactions into a single Multisend transaction
    function _createBatch(address safe_, uint256 nonce_) private view returns (Batch memory batch) {
        // Set initial batch fields
        batch.to = SAFE_MULTISEND_ADDRESS;
        batch.value = 0;
        batch.operation = Operation.DELEGATECALL;

        // Encode the batch calldata. The list of transactions is tightly packed.
        bytes memory data;
        uint256 len = encodedTxns.length;
        for (uint256 i; i < len; ++i) {
            data = bytes.concat(data, encodedTxns[i]);
        }
        batch.data = abi.encodeWithSignature("multiSend(bytes)", data);

        batch.nonce = nonce_;

        // Get the transaction hash
        batch.txHash = _getTransactionHash(safe_, batch);
    }

    function _dumpBatchToJson(address safe_, Batch memory batch_) private {
        // Create json payload
        string memory placeholder = "";
        placeholder.serialize("contractTransactionHash", batch_.txHash);
        placeholder.serialize("safe", safe_);
        placeholder.serialize("value", batch_.value);
        placeholder.serialize("safeTxGas", batch_.safeTxGas);
        placeholder.serialize("baseGas", batch_.baseGas);
        placeholder.serialize("gasPrice", batch_.gasPrice);
        placeholder.serialize("nonce", batch_.nonce);
        placeholder.serialize("to", batch_.to);
        placeholder.serialize("data", batch_.data);
        placeholder.serialize("operation", uint256(batch_.operation));
        placeholder.serialize("gasToken", address(0));
        placeholder.serialize("refundReceiver", address(0));
        placeholder.serialize("chainId", chainId);
        string memory payload = placeholder.serialize("sender", msg.sender);

        // Write to JSON file in leafs directory
        string memory filepath = string.concat("leafs/", outputFilename, ".json");
        vm.writeJson(payload, filepath);
        
        console2.log("Batch transaction dumped to:", filepath);
        console2.log("Transaction hash:", vm.toString(batch_.txHash));
    }

    // Computes the EIP712 hash of a Safe transaction.
    function _getTransactionHash(
        address safe_,
        Batch memory batch_
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    hex"1901",
                    keccak256(
                        abi.encode(DOMAIN_SEPARATOR_TYPEHASH, chainId, safe_)
                    ),
                    keccak256(
                        abi.encode(
                            SAFE_TX_TYPEHASH,
                            batch_.to,
                            batch_.value,
                            keccak256(batch_.data),
                            batch_.operation,
                            batch_.safeTxGas,
                            batch_.baseGas,
                            batch_.gasPrice,
                            address(0),
                            address(0),
                            batch_.nonce
                        )
                    )
                )
            );
    }
}