// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;


import "./Ownable.sol";
import "./Pausable.sol";
import "./Goose.sol";
import "./CrocoDao.sol";
import "./GEGG.sol";
import "./IBarn.sol";
import "./EnumerableSet.sol";

import "hardhat/console.sol";

contract Barn is IBarn, Ownable,  Pausable {

    uint constant multiplier = 10**18;
    //uint constant multiplier = 1;
    uint16 public constant SEASON_DURATION  =  120;
    uint16 public constant SEASON_REST  =  10;
    uint public constant GEGG_DAILY_LIMIT = 1000000 * multiplier;


    //
    struct StakeGoose {
        Pool pool;
        uint16 tokenId;
        address owner;
        uint32 blockNumber;  // this blockNumber is when the Goose stacked /switched to this pool. 
        uint256 unclaimedBalance;  // unclaimed balance before the time of blockNumber.
    }



    struct StakeCroco{
        Pool pool;
        uint16 tokenId;
        address owner;
        uint32 blockNumber;
        uint256 unclaimedBalance;
    }

    struct SeasonStats{
        uint32 blockNumber;
        uint16 pondWinners;  // indicate top 3 Ponds.
        uint8  crocoVotedWiner;
        uint32 totalCrocoVoteDuratoin;
        uint32[10] totalGooseStakeDurationPerPond;
    }

    // record the results of every season from genisis season。
    // will be get updated once season close.
    // todo: will change to array instead of mapping to save gas.
    mapping( uint32 => SeasonStats ) public seasonHistory;

    /*
    * will be reset on seasonOpen(), and seasonClose()
    *
    */
    uint32 public lastOpenBlockNumber = 0; 
    uint32 public lastCloseBlockNumber = 0;
    bool private _isSeasonOpen = false;
    uint32 public genisisBlockNumber = 0;

    mapping( uint16 => StakeGoose ) public gooseStake;
    mapping( uint16 => StakeCroco ) public crocoStake;

    using EnumerableSet for EnumerableSet.UintSet;

    mapping( Pool => EnumerableSet.UintSet ) poolGoose;  // Pool to tokenIds[]
    mapping( Pool => EnumerableSet.UintSet ) poolCroco;  // Pool to tokenIds[]

    mapping( address => EnumerableSet.UintSet ) userGooseIds;
    mapping( address => EnumerableSet.UintSet ) userCrocoIds;


    Goose goose;
    address __goose;
    CrocoDao croco;
    GEGG egg;

    constructor( address _gegg, address _croco ){
        egg = GEGG(_gegg);

        croco = CrocoDao(_croco);
    }

    function getGooseSetNum( Pool _pool ) public view returns (uint) {
        return poolGoose[_pool].length();
    }

     function testGas_init( ) external {
        for( uint16 i = 0; i < 1; i++ ){
            gooseStake[i] = StakeGoose({
                pool: Pool( i % 10 ),
                tokenId: i,
                owner: _msgSender(),
                blockNumber: uint32(block.number) + i,
                unclaimedBalance: 0
            });
        }
    }

    function testGas_mod( ) external {
        for( uint16 i = 0; i < 1; i++ ){
            gooseStake[i].blockNumber += 2;
            gooseStake[i].unclaimedBalance += 100;
        }
    }


    function stakeGooseConfirm( address _owner, Pool _pool, uint16[] calldata tokenIds ) external whenNotPaused{
        require ( lastOpenBlockNumber != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            gooseStake[tokenIds[i]] = StakeGoose({
                pool: _pool,
                tokenId: tokenIds[i],
                owner: _owner,
                blockNumber: uint32(block.number),
                unclaimedBalance: 0
            });
            poolGoose[_pool].add(tokenIds[i]);
            userGooseIds[_owner].add(tokenIds[i]);
        }
    }

    function getUserStakedGooseIds( address _owner, uint _index ) view public returns ( uint ) {
        return userGooseIds[_owner].at(_index);
    }

    function switchGoosePond( Pool _to_pool, uint16[] calldata tokenIds ) external whenNotPaused{
        require ( lastOpenBlockNumber != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( gooseStake[tokenIds[i]].owner == _msgSender(), "You have no token stacked" );
            require( gooseStake[tokenIds[i]].pool != _to_pool, "You are already in this pool" );
            gooseStake[tokenIds[i]].pool = _to_pool;
            gooseStake[tokenIds[i]].blockNumber = uint32(block.number);
        }
    }

    function stakeCrocoAndVote( Pool _pool, uint16[] calldata tokenIds ) external whenNotPaused{
        require ( lastOpenBlockNumber != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( croco.ownerOf(tokenIds[i]) == _msgSender(), "Your are not Owner!" );
            croco.transferFrom( _msgSender(), address(this), tokenIds[i] );
            
            
            crocoStake[tokenIds[i]] = StakeCroco({
                pool: _pool,
                tokenId: tokenIds[i],
                owner: _msgSender(),
                blockNumber: uint32(block.number),
                unclaimedBalance: 0
            });
            poolCroco[_pool].add(tokenIds[i]);
        }
         
    }

    function changeCrocoVote( Pool _to_pool, uint16[] calldata tokenIds ) external whenNotPaused{
        require ( lastOpenBlockNumber != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( crocoStake[tokenIds[i]].owner == _msgSender(), "You have no NFT stacked" );
            require( crocoStake[tokenIds[i]].pool != _to_pool, "You have already voted this pool" );
            crocoStake[tokenIds[i]].pool = _to_pool;
            crocoStake[tokenIds[i]].blockNumber = uint32(block.number);
        }
    }

    function seasonOpen() external {
        if ( lastOpenBlockNumber == 0 ){
            require ( _msgSender() == owner() );
            genisisBlockNumber = uint32(block.number);
        }
        require ( _isSeasonOpen == false, "Season is already Open" );
        require ( block.number >  lastCloseBlockNumber + SEASON_REST, "Season is resting" );
        _isSeasonOpen = true;
        lastOpenBlockNumber = uint32(block.number);

        
    }

    function getCurrentSeasonID()  private view returns (uint32)  {
        return ( ( uint32(block.number) - genisisBlockNumber ) / (SEASON_DURATION + SEASON_REST) );
    } 

    function getSeasonID( uint32 blockNumber )  private view returns (uint32)  {

        require( blockNumber>= genisisBlockNumber, "blockNumber >= genisisBlockNumber check fail.");
        return ( ( blockNumber - genisisBlockNumber ) / (SEASON_DURATION + SEASON_REST) );
    } 

    function seasonClose() external {
        require ( _isSeasonOpen == true, "Season is already Closed" );
        require ( block.number > lastOpenBlockNumber + SEASON_DURATION, "Season close time isn't arrived");
        _isSeasonOpen = false;
        lastCloseBlockNumber = uint32(block.number);


        uint[] memory poolGooseCounter = new uint[](10);
        uint[] memory poolVoteCounter = new uint[](10);


        uint32 curSeasonSeq = getCurrentSeasonID();
        console.log("curSeasonSeq: ", curSeasonSeq);
        seasonHistory[curSeasonSeq].blockNumber = lastCloseBlockNumber;


        for ( uint8 i = uint8(Pool.Barn); i <= uint8(Pool.Pond9); i++ ){
            // todo: poolRealNumber need to be reset in each round.

            for ( uint j = 0; j < poolGoose[Pool(i)].length(); j++ ){
                uint32 iDuration = ( lastCloseBlockNumber - genisisBlockNumber ) % (SEASON_DURATION + SEASON_REST);
                uint32 nearestOpenBlock = lastCloseBlockNumber - iDuration;
                uint16 tokenID = uint16(poolGoose[Pool(i)].at(j));
                if( gooseStake[tokenID].blockNumber < nearestOpenBlock ){
                    poolGooseCounter[uint8(Pool.Barn)] += 1; 
                    seasonHistory[curSeasonSeq].totalGooseStakeDurationPerPond[uint(Pool.Barn)] += iDuration;
                }else{
                    iDuration = lastCloseBlockNumber - gooseStake[tokenID].blockNumber;
                    poolGooseCounter[i] += 1;
                    seasonHistory[curSeasonSeq].totalGooseStakeDurationPerPond[i] += iDuration;

                }

            }
           

            for( uint j = 0; j < poolCroco[Pool(i)].length(); j++ ) {
                uint16 tokenID = uint16(poolCroco[Pool(i)].at(j));
                uint32 _seasonSeq = getSeasonID(crocoStake[tokenID].blockNumber);
                if( _seasonSeq < curSeasonSeq ){
                    poolVoteCounter[uint8(Pool.Barn)] += 1;
                }else{
                    poolVoteCounter[i] += 1;
                    seasonHistory[curSeasonSeq].totalCrocoVoteDuratoin += lastCloseBlockNumber - gooseStake[tokenID].blockNumber;
                }
            }
        }

        uint8 first = uint8(Pool.Pond1);
        uint8 second = uint8(Pool.Pond2);
        uint8 third = uint8(Pool.Pond3);
        uint8 crocoWinner = uint8(Pool.Pond1);
        for ( uint8 i = uint8(Pool.Pond1); i <= uint8(Pool.Pond9); i++ ){
            if ( poolGooseCounter[i] < poolGooseCounter[first]  ){
                first = i;
            }
        }
        for ( uint8 i = uint8(Pool.Pond1); i <= uint8(Pool.Pond9); i++ ){
            if( i == first ) continue;
            if ( poolGooseCounter[i] < poolGooseCounter[second] ){
                second = i;
            }else if( second == first ){
                second = i;
            }
        }
        for ( uint8 i = uint8(Pool.Pond1); i <= uint8(Pool.Pond9); i++ ){
            if( i == second || i == first ) continue;
            if ( poolGooseCounter[i] < poolGooseCounter[third] ){
                third = i;
            }else if( third == second || third == first ){
                third = i;
            }
        }
        for ( uint8 i = uint8(Pool.Pond1); i <= uint8(Pool.Pond9); i++ ){
            if ( poolVoteCounter[i] > poolVoteCounter[third] ){
                crocoWinner = i;
            }
        }

        uint16 winners = 0;
        winners |= first;
        winners <<= 4;
        winners |= second;
        winners <<= 4;
        winners |= third;
        console.log("first:", first);
        console.log("second:", second);
        console.log("third:", third);
        console.log("poolGooseCounter : ");
        for ( uint8 i = uint8(Pool.Barn); i <= uint8(Pool.Pond9); i++ ){
            console.log("Pool #",i," = ",poolGooseCounter[i]);
        }
        seasonHistory[curSeasonSeq].pondWinners = winners;
        seasonHistory[curSeasonSeq].crocoVotedWiner = crocoWinner;

    }

    function getRank( Pool pool, uint16 winnerNum ) view public returns (uint32) {
        console.log("winnderNum: ", winnerNum);
        for ( uint32 i = 3; i >= 1; i -- ){
            Pool winner = Pool( winnerNum & 0xf );
            if( winner == pool ) return i;
            winnerNum >>= 4;
        }
        return 0;
    }

    function getTotalGooseStakeDurationPerPond( uint32 index ) view public returns ( uint32[] memory ){
        uint32[]    memory vals = new uint32[](10);
        for( uint i = 0; i < 10; i++ ){
            vals[i] = seasonHistory[index].totalGooseStakeDurationPerPond[i];
        }
        return vals;
    }

    /*
    * used by switchPond, save the unclaimed rewards to stake structs.
    *
    */

    function gooseClaimToBalance(uint16[] calldata tokenIds) public returns (uint32) {
        uint32 totalDuration = 0;
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( _msgSender() == gooseStake[tokenIds[i]].owner, " It's not your NFT" );
            uint32 sID_from = getSeasonID(gooseStake[tokenIds[i]].blockNumber);
            uint32 sID_to   = getCurrentSeasonID();
            console.log("sID_from", sID_from);
            console.log("sID_to", sID_to);
            for ( uint32 j = sID_from; j <= sID_to; j ++ ){
                if( checkSeasonExists(j) ){
                    console.log("tik, seasonID = #", j);
                    Pool pool = gooseStake[tokenIds[i]].pool;
                    uint256 pond_rewards;
                    uint256 rank = getRank(pool, seasonHistory[j].pondWinners);
                    if( rank == 0 ) {
                        // pond_rewards = GEGG_DAILY_LIMIT * 0.3 * 1 / 7; 7 is sum of 6 Ponds and 1 Barn.
                        pond_rewards = GEGG_DAILY_LIMIT * 3 / 10 / 7;   // todo: need to float type
                        
                    }else {
                        // pond_rewards = GEGG_DAILY_LIMIT * 0.7 * ( 4 / 6 - rank / 6); rank is 1, 2 or 3;
                        pond_rewards = GEGG_DAILY_LIMIT * 7 / 10 * 4 / 6 -  GEGG_DAILY_LIMIT * 7 / 10 * rank / 6;
                    }

                    if ( pool == Pool(seasonHistory[j].crocoVotedWiner) ){
                        //pond_rewards = 0;
                    }
                    uint32 iDuration = ( seasonHistory[j].blockNumber - genisisBlockNumber ) % (SEASON_DURATION + SEASON_REST);
                    uint32 nearestOpenBlock = seasonHistory[j].blockNumber - iDuration;

                    if( gooseStake[tokenIds[i]].blockNumber < nearestOpenBlock ){
                        //iDuration = ( seasonHistory[j].blockNumber - genisisBlockNumber ) % (SEASON_DURATION + SEASON_REST);
                        gooseStake[tokenIds[i]].unclaimedBalance += pond_rewards * iDuration / seasonHistory[j].totalGooseStakeDurationPerPond[uint(Pool.Barn)];

                    }else{
                        iDuration = seasonHistory[j].blockNumber - gooseStake[tokenIds[i]].blockNumber;
                        gooseStake[tokenIds[i]].unclaimedBalance += pond_rewards * iDuration / seasonHistory[j].totalGooseStakeDurationPerPond[uint(pool)];

                    }
                    
                    totalDuration += iDuration;
                    console.log("pool No.     = ", uint(pool));
                    console.log("pool rank    = ", rank);
                    console.log("pond_rewards = ", pond_rewards);
                    console.log("iDuration    = ", iDuration);

                }
                
            }
            
        }
        console.log("gooseClaimToBalance / totalDuration = ", totalDuration );
        return totalDuration;
        
    }

    function crocoClaimToBalance(uint16[] calldata tokenIds) public {
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( _msgSender() == crocoStake[tokenIds[i]].owner, " It's not your NFT" );
        }
    }

    /*
    * Call claimToBalance() and clear the umclaimedBalance, and widraw to user's account
    */
    function claimToAccount() public{

    }

    /*
    * Call claimToAccount() and unstake NFT to their own account.
    */
    function unstakeGoose( uint16[] calldata tokenIds ) external {
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( _msgSender() == gooseStake[tokenIds[i]].owner, " It's not your NFT" );
        }
    }

    function unstakeCroco( uint16[] calldata tokenIds ) external{
        for( uint8 i = 0; i < tokenIds.length; i++ ){
        
        }
    }

    function checkSeasonExists( uint32 i) view internal returns (bool) {
        return ( seasonHistory[i].totalCrocoVoteDuratoin != 0 || seasonHistory[i].pondWinners != 0 );
    }

    function printBlockNumber () view public returns ( uint ) {
        return block.number;
    }

}