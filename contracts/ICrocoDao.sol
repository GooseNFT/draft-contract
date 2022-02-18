// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface ICrocoDao {

  // struct to store each token's traits
  struct Croco {
    uint8 body;
    uint8 eye;
    uint8 legs;
    uint8 mouth;
  }

/*
  function getPaidTokens() external view returns (uint256);
  function getTokenTraits(uint256 tokenId) external view returns (Croco memory);
*/
}