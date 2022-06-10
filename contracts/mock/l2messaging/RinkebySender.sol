// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface CallProxy{
    function anyCall(
        address _to,
        bytes calldata _data,
        address _fallback,
        uint256 _toChainID,
        uint256 _flags

    ) external;
}

  
contract RinkebySender {
    address owner;
    // Anycall v6
    address constant anyCallAddress = 0x273a4fFcEb31B8473D51051Ad2a2EdbB7Ac8Ce02;
    address public child = 0x59DC254b68856A2578E496F668BF4E612f96a449;
    uint256 public count = 0;
    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only owner");
        _;
    }
    function setChild(address _newAddress) public {
        child = _newAddress;
    }
    function encodeParams(bytes32 hashed, bytes memory signature, uint256 message) public pure returns (bytes memory) {
        return
            abi.encode(
                hashed,
                signature,
                message
            );
    }
    function step1_initiateAnyCallSimple(bytes calldata _data) public onlyOwner {
        count += 1;
        CallProxy(anyCallAddress).anyCall(
            // Address of contract on L2
            child,
            // Already encoded data to be decoded in the actual L2 Contract
            _data,
            // 0x as fallback address because we don't have a fallback function
            address(0),
            // chainid of Fantom testnet
            4002,
            // Using 0 flag to pay fee on destination chain
            0
            );
        }
            
}