// SPDX-License-Identifier: MIT LICENSE 

pragma solidity ^0.8.0;

interface IGoldenEggGame {
    enum Location { 
      Barn, 
      Pond1, 
      Pond2, 
      Pond3, 
      Pond4, 
      Pond5, 
      Pond6,
      Pond7,
      Pond8,
      Pond9
    }  

  function gooseEnterGame( address _user, Location _location, uint16[] calldata gooseIds ) external;
  function crocoEnterGame( address _user, Location _location, uint16[] calldata crocoIds ) external;

}