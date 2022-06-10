// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;


interface IAnyCallExecutor {
    struct Context {
        address from;
        uint256 fromChainID;
        uint256 nonce;
    }
  function context() external returns (Context memory);
}
contract PolygonChild {
    uint256 public lastMessage;
    address public constant owner = 0xABfE4d45c6381908F09EF7c501cc36E38D34c0d4;
    address public constant callProxy = 0xD7c295E399CA928A3a14b01D760E794f1AdF8990;
    address public lastCaller;
    address public lastData;
    uint256 public lastChainID;
    uint256 public lastNonce;

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

 function anyExecute(bytes memory _data) external returns (bool success, bytes memory result){
      (bytes32 hashed, bytes memory signature, uint256 message) = decodeParams(_data);
      require(recoverSigner(hashed, signature) == owner, "Isn't owner");
      lastMessage = message;
      lastCaller = owner;
      lastData = IAnyCallExecutor(0xe3aee52608Db94F2691a7F9Aba30235B14B7Bb70).context().from;
      lastChainID =  IAnyCallExecutor(0xe3aee52608Db94F2691a7F9Aba30235B14B7Bb70).context().fromChainID;
      lastNonce =  IAnyCallExecutor(0xe3aee52608Db94F2691a7F9Aba30235B14B7Bb70).context().nonce;
      success=true;
      result="";
    }


 function decodeParams(bytes memory data)
        public
        pure
        returns (
           bytes32 hashed, bytes memory signature, uint256 message
        )
    {
        return
            abi.decode(data, (bytes32, bytes, uint256));
    }

    

 /**
   * @notice Recover the signer of hash, assuming it's an EOA account
   * @dev Only for EthSign signatures
   * @param _hash       Hash of message that was signed
   * @param _signature  Signature encoded as (bytes32 r, bytes32 s, uint8 v)
   */
  function recoverSigner(
    bytes32 _hash,
    bytes memory _signature
  ) internal pure returns (address signer) {
    require(_signature.length == 65, "SignatureValidator#recoverSigner: invalid signature length");

    // Variables are not scoped in Solidity.
    bytes32 r;
    bytes32 s;
    uint8 v;

    assembly {
        // first 32 bytes, after the length prefix
        r := mload(add(_signature, 32))
        // second 32 bytes
        s := mload(add(_signature, 64))
        // final byte (first byte of the next 32 bytes)
        v := byte(0, mload(add(_signature, 96)))
    }

    if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
      revert("SignatureValidator#recoverSigner: invalid signature 's' value");
    }

    if (v != 27 && v != 28) {
      revert("SignatureValidator#recoverSigner: invalid signature 'v' value");
    }

    // Recover ECDSA signer
    signer = ecrecover(
      keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash)),
      v,
      r,
      s
    );
    
    // Prevent signer from being 0x0
    require(
      signer != address(0x0),
      "SignatureValidator#recoverSigner: INVALID_SIGNER"
    );

    return signer;
  }
}