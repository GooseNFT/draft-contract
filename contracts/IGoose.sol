// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface IGoose {

  // struct to store each token's traits
  struct GooseTraits {
    uint8 body;
    uint8 eye;
    uint8 hat;
    uint8 legs;
    uint8 mouth;
    uint8 mouthAcc;
    uint8 neck;
  }

/*
  function getPaidTokens() external view returns (uint256);
  function getTokenTraits(uint256 tokenId) external view returns (Goose memory);
*/
}