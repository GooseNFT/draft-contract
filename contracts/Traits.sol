// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "hardhat/console.sol";


abstract contract Traits is  Ownable{

    struct Trait {
        string name;
        string png;
    }

    // traitType => ( traitIndex => Trait ) Stroage of index to trait PNG data.
    mapping(uint8 => mapping(uint8 => Trait)) public traitData;
    mapping(uint8 => uint8) public traitType_length;

      // mapping from trait type (index) to its name
    string[] public traitTypes;


   // 
   function setTraitTypes( string[] calldata _traitTypes ) external onlyOwner {
       require( traitTypes.length == 0, "traitTypes is already set");
       for (uint i = 0; i < _traitTypes.length; i++) {
           traitTypes.push(_traitTypes[i]);
       }
   }

   /**
   * administrative to upload the names and images associated with each trait
   * @param traitType the trait type to upload the traits for (see traitTypes for a mapping)
   * @param traits the names and base64 encoded PNGs for each trait
   */
    function uploadTraits( uint8 traitType, uint8[] calldata traitIds, Trait[] calldata traits) external onlyOwner {
        require( traitIds.length == traits.length, "Mismatched inputs" );
        require( traitTypes.length > 0, "traitTypes is not set yet" );
        require( traitType <= traitTypes.length - 1, "traitType is out of range" );
        traitType_length[traitType] = uint8(traits.length);
        //console.log("traitType: ", traitType, " => traits.length:", uint8(traits.length));
        for (uint i = 0; i < traits.length; i++) {
            require( bytes(traitData[traitType][traitIds[i]].name).length == 0, "modification traitData is not allowed" );
            traitData[traitType][traitIds[i]] = Trait(
                traits[i].name,
                traits[i].png
            );
        }
    }

      /** RENDER */

    function gettraitType_length_base() public view {
        for ( uint i =0; i < 7; i++ ){
            console.log("traitType_length(", i, ") = ", traitType_length[uint8(i)]);
        }
    }

  /**
   * generates an <image> element using base64 encoded PNGs
   * @param trait the trait storing the PNG data
   * @return the <image> element
   */
  function drawTrait(Trait memory trait) internal pure returns (string memory) {
    return string(abi.encodePacked(
      '<image x="4" y="4" width="72" height="72" image-rendering="pixelated" preserveAspectRatio="xMidYMid" xlink:href="data:image/png;base64,',
      trait.png,
      '"/>'
    ));
  }

  /** BASE 64 - Written by Brech Devos */
  
  string internal constant TABLE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  function base64(bytes memory data) internal pure returns (string memory) {
    if (data.length == 0) return '';
    
    // load the table into memory
    string memory table = TABLE;

    // multiply by 4/3 rounded up
    uint256 encodedLen = 4 * ((data.length + 2) / 3);

    // add some extra buffer at the end required for the writing
    string memory result = new string(encodedLen + 32);

    assembly {
      // set the actual output length
      mstore(result, encodedLen)
      
      // prepare the lookup table
      let tablePtr := add(table, 1)
      
      // input ptr
      let dataPtr := data
      let endPtr := add(dataPtr, mload(data))
      
      // result ptr, jump over length
      let resultPtr := add(result, 32)
      
      // run over the input, 3 bytes at a time
      for {} lt(dataPtr, endPtr) {}
      {
          dataPtr := add(dataPtr, 3)
          
          // read 3 bytes
          let input := mload(dataPtr)
          
          // write 4 characters
          mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F)))))
          resultPtr := add(resultPtr, 1)
          mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F)))))
          resultPtr := add(resultPtr, 1)
          mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr( 6, input), 0x3F)))))
          resultPtr := add(resultPtr, 1)
          mstore(resultPtr, shl(248, mload(add(tablePtr, and(        input,  0x3F)))))
          resultPtr := add(resultPtr, 1)
      }
      
      // padding with '='
      switch mod(mload(data), 3)
      case 1 { mstore(sub(resultPtr, 2), shl(240, 0x3d3d)) }
      case 2 { mstore(sub(resultPtr, 1), shl(248, 0x3d)) }
    }
    
    return result;
  }



}