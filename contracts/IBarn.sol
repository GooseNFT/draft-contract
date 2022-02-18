// SPDX-License-Identifier: MIT LICENSE 

pragma solidity ^0.8.0;

interface IBarn {
    enum Pool { 
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

/*
  function stakeGoose2Pool( Pool _pool, uint16[] calldata tokenIds ) external;
  function switchGoosePond( Pool _to_pool, uint16[] calldata tokenIds ) external;
  function stakeCrocoAndVote( Pool _pool, uint16[] calldata tokenIds ) external;
  function changeCrocoVote( Pool _to_pool, uint16[] calldata tokenIds ) external;
  function seasonClose() external;
  function seasonOpen() external;
  function unstakeGoose( uint16[] calldata tokenIds ) external;
  function unstakeCroco( uint16[] calldata tokenIds ) external;
*/

}