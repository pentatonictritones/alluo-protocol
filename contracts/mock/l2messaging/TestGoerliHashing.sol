// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;


contract TestGoerliHashing {

 function decodeParams(bytes calldata data)
        public
        pure
        returns (
           bytes32 hashed, bytes memory signature, uint256 message
        )
    {
        return
            abi.decode(data, (bytes32, bytes, uint256));
    }

    function encodeParams(bytes32 hashed, bytes memory signature, uint256 message) public pure returns (bytes memory) {
        return
            abi.encode(
                hashed,
                signature,
                message
            );
    }


    function onStateReceive(bytes calldata data) public pure returns (address, uint256){
        (bytes32 hashed, bytes memory signature, uint256 message) = decodeParams(data);
        return (recoverSigner(hashed, signature), message);
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
  ) public pure returns (address signer) {
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