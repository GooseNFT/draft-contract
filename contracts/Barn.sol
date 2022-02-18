// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;


import "./Ownable.sol";
import "./Pausable.sol";
import "./Goose.sol";
import "./CrocoDao.sol";
import "./GEGG.sol";
import "./IBarn.sol";
import "./EnumerableSet.sol";

contract Barn is IBarn, Ownable,  Pausable {

    uint16 public constant SEASON_DURATION  =  8000;
    uint16 public constant SEASON_REST  =  800;
    uint32 public constant GEGG_DAILY_LIMIT = 1000000;


    //
    struct StakeGoose {
        Pool pool;
        uint16 tokenId;
        address owner;
        uint blockNumber;
        uint256 unclaimedBalance;
    }



    struct StakeCroco{
        Pool pool;
        uint16 tokenId;
        address owner;
        uint blockNumber;
        uint256 unclaimedBalance;
    }

    /*
    * will be reset on seasonOpen(), and seasonClose()
    *
    */
    uint public lastOpenBlockNumber = 0; 
    uint public lastCloseBlockNumber = 0;
    bool private _isSeasonOpen = false;

    mapping( uint16 => StakeGoose ) public gooseStake;
    mapping( uint16 => StakeCroco ) public crocoStake;

    uint8[]  sorted;

    using EnumerableSet for EnumerableSet.UintSet;

    mapping( Pool => EnumerableSet.UintSet ) poolGoose;  // Pool to tokenIds[]
    mapping( Pool => EnumerableSet.UintSet ) poolCroco;  // Pool to tokenIds[]

    Goose goose;
    CrocoDao croco;

    GEGG egg;

    function stakeGoose2Pool( Pool _pool, uint16[] calldata tokenIds ) external whenNotPaused{
        require ( lastOpenBlockNumber == 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( goose.ownerOf(tokenIds[i]) == _msgSender(), "Your are not Owner!" );
            goose.transferFrom( _msgSender(), address(this), tokenIds[i] );

            gooseStake[tokenIds[i]] = StakeGoose({
                pool: _pool,
                tokenId: tokenIds[i],
                owner: _msgSender(),
                blockNumber: block.number,
                unclaimedBalance: 0
            });
            poolGoose[_pool].add(tokenIds[i]);
        }
    }

    function switchGoosePond( Pool _to_pool, uint16[] calldata tokenIds ) external whenNotPaused{
        require ( lastOpenBlockNumber == 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( gooseStake[tokenIds[i]].owner == _msgSender(), "You have no token stacked" );
            require( gooseStake[tokenIds[i]].pool != _to_pool, "You are already in this pool" );
            gooseStake[tokenIds[i]].pool = _to_pool;
            gooseStake[tokenIds[i]].blockNumber = block.number;
        }
    }

    function stakeCrocoAndVote( Pool _pool, uint16[] calldata tokenIds ) external whenNotPaused{
        require ( lastOpenBlockNumber == 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( croco.ownerOf(tokenIds[i]) == _msgSender(), "Your are not Owner!" );
            croco.transferFrom( _msgSender(), address(this), tokenIds[i] );
            
            
            crocoStake[tokenIds[i]] = StakeCroco({
                pool: _pool,
                tokenId: tokenIds[i],
                owner: _msgSender(),
                blockNumber: block.number,
                unclaimedBalance: 0
            });
            poolCroco[_pool].add(tokenIds[i]);
        }
         
    }

    function changeCrocoVote( Pool _to_pool, uint16[] calldata tokenIds ) external whenNotPaused{
        require ( lastOpenBlockNumber == 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( crocoStake[tokenIds[i]].owner == _msgSender(), "You have no NFT stacked" );
            require( crocoStake[tokenIds[i]].pool != _to_pool, "You have already voted this pool" );
            crocoStake[tokenIds[i]].pool = _to_pool;
            crocoStake[tokenIds[i]].blockNumber = block.number;
        }
    }

    function seasonOpen() external {
        if ( lastOpenBlockNumber == 0 ){
            require ( _msgSender() == owner() );
        }
        require ( _isSeasonOpen == false, "Season is already Open" );
        require ( block.number >  lastCloseBlockNumber + SEASON_REST, "Season is resting" );
        _isSeasonOpen = true;
        lastOpenBlockNumber = block.number;

        
    }

    function seasonClose() external {
        require ( _isSeasonOpen == true, "Season is already Closed" );
        require ( block.number > lastOpenBlockNumber + SEASON_DURATION, "Season close time isn't arrived");
        _isSeasonOpen = false;
        lastCloseBlockNumber = block.number;

        // sort Pool by number of staked tokens.
        // uint8[] memory sorted = new uint8[](10); // [todo] what if we use memory, how is the gas difference.
        //uint8[] memory sortedx = new uint8[](0);
        sorted.push(uint8(Pool.Pond1));

        // [todo] This code snippet of sorting need to be optimized to save gas. 
        for ( uint8 i = uint8(Pool.Pond2); i <= uint8(Pool.Pond9); i++ ){
            bool isFound  = false;
            for ( uint8 j = 0; j < sorted.length; j++ ){
                if( sorted[j] == i ) continue; // Pool(i) is alread pushed.
                if( poolGoose[Pool(i)].length() < poolGoose[Pool(sorted[j])].length()  || 
                  ( poolGoose[Pool(i)].length() == poolGoose[Pool(sorted[j])].length() && i < sorted[j] ) ) {
                    // found a position(j) bigger than me, move the array one step forward, 
                    sorted.push(sorted[sorted.length-1]); // extend the last one.
                    uint256 k = sorted.length - 2;
                    for ( ; k > j; k-- ){
                        sorted[k] = sorted[k-1];
                    }
                    // and add to where before j
                    sorted[k] = i;
                    isFound = true;
                    break;
                }
            }
            if( isFound == false ) sorted.push(i);
        }
        require( sorted.length == 9, "Internal Error" );


        


        uint8 winner_pond = uint8(Pool.Pond1);
        for ( uint8 i = uint8(Pool.Pond2); i <= uint8(Pool.Pond9); i++ ){
            if ( poolCroco[Pool(winner_pond)].length() > poolCroco[Pool(i)].length() ){
                winner_pond = i;
            }
        }
        uint32 winner_rewards = 0;


        // distribute $GEGG to Goose Barn / Pond, the fewest 3 ponds get 70% of the new issued token.

        /*
        * Rules: 
        * 1. rewards are calculated from your block-duration proportional to the sum of all Goose’s block-duration；
        * 2. block-duration： the start time would be the later one of  the time which put in POND , and the time of season beginning.
        */ 

        sorted.push(uint8(Pool.Barn)); // put Pool.Barn to the end.
        for ( uint8 i = 0; i < sorted.length; i++ ){
            uint32 pond_rewards;
            uint   sum_blockduration;
            if( i <= 2 ) {
                // pond_rewards = GEGG_DAILY_LIMIT * 0.7 * ( 1 / 2 - i / 6);
                pond_rewards = GEGG_DAILY_LIMIT * 7 / 10 / 2 -  GEGG_DAILY_LIMIT * 7 / 10 * i / 6;
            }else {
                // pond_rewards = GEGG_DAILY_LIMIT * 7 / 10 * 1 / 7;
                pond_rewards = GEGG_DAILY_LIMIT  / 10 ;
            }
            for( uint16 j = 0; j < poolGoose[Pool(sorted[i])].length(); j++ ){
                uint16 tokenId = uint16(poolGoose[Pool(sorted[i])].at(j));
                if ( gooseStake[tokenId].blockNumber >= lastOpenBlockNumber ) {
                    require( gooseStake[tokenId].blockNumber < lastCloseBlockNumber, "This couldn't happen" );
                    sum_blockduration += (lastCloseBlockNumber - gooseStake[tokenId].blockNumber);
                }else{
                    if( sorted[i] != uint8(Pool.Barn) ) {
                        // move to Pool.Barn
                        // this is very costly, just to see how much gas would be burned.
                        poolGoose[Pool(sorted[i])].remove(tokenId);
                        poolGoose[Pool.Barn].add(tokenId);
                        gooseStake[tokenId].pool = Pool.Barn;
                    }
                    sum_blockduration += SEASON_DURATION;
                }
            }
            if( sorted[i] == winner_pond ){
                    winner_rewards = pond_rewards; // This unfortunate Goolse Pond have no rewards.
            }else{
                for( uint16 j = 0; j < poolGoose[Pool(sorted[i])].length(); j++ ){
                    uint16 tokenId = uint16(poolGoose[Pool(sorted[i])].at(j));
                    if ( gooseStake[tokenId].blockNumber >= lastOpenBlockNumber ) {
                        gooseStake[tokenId].unclaimedBalance = pond_rewards * (lastCloseBlockNumber - gooseStake[tokenId].blockNumber) / sum_blockduration;
                    }else{
                        gooseStake[tokenId].unclaimedBalance = pond_rewards * SEASON_DURATION / sum_blockduration;
                    }                    
                }
            }
        }

        // distributed rewards stolen from winner pond to $CrocoNFT holder, do not count blocktime duration of voting.

        for( uint16 i = 0; i < poolCroco[Pool(winner_pond)].length(); i ++ ){
            uint16 tokenId = uint16(poolCroco[Pool(winner_pond)].at(i));
            crocoStake[tokenId].unclaimedBalance += ( winner_rewards / poolCroco[Pool(winner_pond)].length() );
        }


    }

    function unstakeGoose( uint16[] calldata tokenIds ) external {
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( _msgSender() == gooseStake[tokenIds[i]].owner, " It's not your NFT" );
        }
    }

    function unstakeCroco( uint16[] calldata tokenIds ) external{
        for( uint8 i = 0; i < tokenIds.length; i++ ){
        
        }
    }

}