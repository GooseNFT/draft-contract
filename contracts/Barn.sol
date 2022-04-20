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

contract Barn is IBarn, Ownable, Pausable {

    //uint constant multiplier = 10**18;
    uint constant multiplier = 1;
    uint16 public SEASON_DURATION = 115;
    uint16 public SEASON_REST = 20;
    uint public constant GEGG_DAILY_LIMIT = 1000000 * multiplier;


    struct StakeGoose {
        Pool pool;
        uint16 gooseId;
        address owner;
        uint32 blockNumber;  // this blockNumber is when the Goose staked /switched to this pool. 
        uint256 unclaimedBalance;  // unclaimed balance before the time of blockNumber.
    }

    struct StakeCroco{
        Pool pool;
        uint16 crocoId;
        address owner;
        uint32 blockNumber;
        uint256 unclaimedBalance;
    }

    struct SeasonStats{
        uint32 seasonFirstBlockNumber;
        uint32 seasonLastBlockNumber;
        uint16 topPonds;  // indicate top 3 Ponds.
        uint8  crocoVotedPond;
        uint32 totalCrocoVoteDuration; 
        uint32[10] totalGooseStakeDurationPerPond;
    }

    // record the results of every season from genisis season。
    // will get updated once season closes.
    // todo: will change to array instead of mapping to save gas.
    mapping( uint32 => SeasonStats ) public seasonsHistory;

    /*
    * will be reset on seasonBegan(), and seasonEnded()
    *
    */
    uint32 public previousSeasonFirstBlockNumber = 0; 
    uint32 public previousSeasonLastBlockNumber = 0;
    bool private _seasonIsInProgress = false;
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

    constructor( address _gegg, address _croco, uint16 duration, uint16 rest ){
        egg = GEGG(_gegg);
        croco = CrocoDao(_croco);
        SEASON_DURATION = duration;
        SEASON_REST = rest;
    }

    function getGooseSetNum( Pool _pool ) public view returns (uint) {
        return poolGoose[_pool].length();
    }

     function testGas_init( ) external {
        for( uint16 i = 0; i < 1; i++ ){
            gooseStake[i] = StakeGoose({
                pool: Pool( i % 10 ),
                gooseId: i,
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


    function stakeGooseConfirm( address _owner, Pool _pool, uint16[] calldata gooseIds ) external whenNotPaused{
        require ( previousSeasonFirstBlockNumber != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < gooseIds.length; i++ ){
            gooseStake[gooseIds[i]] = StakeGoose({
                pool: _pool,
                gooseId: gooseIds[i],
                owner: _owner,
                blockNumber: uint32(block.number),
                unclaimedBalance: 0
            });
            poolGoose[_pool].add(gooseIds[i]);
            userGooseIds[_owner].add(gooseIds[i]);
        }
    }

    function getUserStakedGooseIds( address _owner, uint _index ) view public returns ( uint ) {
        return userGooseIds[_owner].at(_index);
    }

    function switchGoosePond( Pool _to_pool, uint16[] calldata tokenIds ) external whenNotPaused{
        require ( previousSeasonFirstBlockNumber != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            require( gooseStake[tokenIds[i]].owner == _msgSender(), "You have no token stacked" );
            require( gooseStake[tokenIds[i]].pool != _to_pool, "You are already in this pool" );
            gooseStake[tokenIds[i]].pool = _to_pool;
            gooseStake[tokenIds[i]].blockNumber = uint32(block.number);
        }
    }

    function stakeCrocoAndVote( Pool _pool, uint16[] calldata crocoIds ) external whenNotPaused{
        require ( previousSeasonFirstBlockNumber != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < crocoIds.length; i++ ){
            require( croco.ownerOf(crocoIds[i]) == _msgSender(), "Your are not Owner!" );
            croco.transferFrom( _msgSender(), address(this), crocoIds[i] );
            
            
            crocoStake[crocoIds[i]] = StakeCroco(
                {
                pool: _pool,
                crocoId: crocoIds[i],
                owner: _msgSender(),
                blockNumber: uint32(block.number),
                unclaimedBalance: 0
                }
            );
            poolCroco[_pool].add(crocoIds[i]);
        }
         
    }

    function changeCrocoVote( Pool _to_pool, uint16[] calldata crocoIds ) external whenNotPaused{
        require ( previousSeasonFirstBlockNumber != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < crocoIds.length; i++ ){
            require( crocoStake[crocoIds[i]].owner == _msgSender(), "You have no NFT stacked" );
            require( crocoStake[crocoIds[i]].pool != _to_pool, "You have already voted this pool" );
            crocoStake[crocoIds[i]].pool = _to_pool;
            crocoStake[crocoIds[i]].blockNumber = uint32(block.number);
        }
    }

    function seasonOpen() external {
        if ( previousSeasonFirstBlockNumber == 0 ){
            require ( _msgSender() == owner() );
            genisisBlockNumber = uint32(block.number);
        }
        require ( _seasonIsInProgress == false, "Season is already on-going" );
        require ( block.number >  previousSeasonLastBlockNumber + SEASON_REST, "Season is resting" );
        _seasonIsInProgress = true;
        previousSeasonFirstBlockNumber = uint32(block.number);

        
    }

    function getCurrentSeasonID()  private view returns (uint32)  {
        return ( ( uint32(block.number) - genisisBlockNumber ) / (SEASON_DURATION + SEASON_REST) );
    } 

    function getSeasonID( uint32 blockNumber )  private view returns (uint32)  {

        require( blockNumber>= genisisBlockNumber, "blockNumber >= genisisBlockNumber check fail.");
        return ( ( blockNumber - genisisBlockNumber ) / (SEASON_DURATION + SEASON_REST) );
    } 

    function seasonClose() external {
        require ( _seasonIsInProgress == true, "Season is already Closed" );
        require ( block.number > previousSeasonFirstBlockNumber + SEASON_DURATION, "Season close time isn't arrived");
        _seasonIsInProgress = false;
        previousSeasonLastBlockNumber = uint32(block.number);


        uint[] memory poolGooseCounter = new uint[](10);
        uint[] memory poolVoteCounter = new uint[](10);


        uint32 curSeasonSeq = getCurrentSeasonID(); // todo: this might be incorrect because open and close time might not be happend in time.
        console.log("curSeasonSeq: ", curSeasonSeq);
        seasonsHistory[curSeasonSeq].seasonFirstBlockNumber = previousSeasonFirstBlockNumber;
        seasonsHistory[curSeasonSeq].seasonLastBlockNumber = previousSeasonLastBlockNumber;


        for ( uint8 i = uint8(Pool.Barn); i <= uint8(Pool.Pond9); i++ ){
            // todo: poolRealNumber need to be reset in each round.

            for ( uint j = 0; j < poolGoose[Pool(i)].length(); j++ ){
                uint32 stakeDuration = previousSeasonLastBlockNumber - previousSeasonFirstBlockNumber;
                //uint32 previousOpenBlock = previousSeasonLastBlockNumber - stakeDuration;
                uint16 tokenID = uint16(poolGoose[Pool(i)].at(j));
                if( gooseStake[tokenID].blockNumber < previousSeasonFirstBlockNumber ){
                    poolGooseCounter[uint8(Pool.Barn)] += 1; 
                    seasonsHistory[curSeasonSeq].totalGooseStakeDurationPerPond[uint(Pool.Barn)] += stakeDuration;
                }else{
                    stakeDuration = previousSeasonLastBlockNumber - gooseStake[tokenID].blockNumber;
                    poolGooseCounter[i] += 1;
                    seasonsHistory[curSeasonSeq].totalGooseStakeDurationPerPond[i] += stakeDuration;
                }

            }
           

            for( uint j = 0; j < poolCroco[Pool(i)].length(); j++ ) {
                uint16 crocoID = uint16(poolCroco[Pool(i)].at(j));
                if( crocoStake[crocoID].blockNumber < previousSeasonFirstBlockNumber ){
                    poolVoteCounter[uint8(Pool.Barn)] += 1;
                }else{
                    poolVoteCounter[i] += 1;
                    seasonsHistory[curSeasonSeq].totalCrocoVoteDuration += previousSeasonLastBlockNumber - crocoStake[crocoID].blockNumber;
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
        //todo Need to notify via events.
        for ( uint8 i = uint8(Pool.Barn); i <= uint8(Pool.Pond9); i++ ){
            console.log("Pool #",i," = ",poolGooseCounter[i]);
        }
        seasonsHistory[curSeasonSeq].topPonds = winners;
        seasonsHistory[curSeasonSeq].crocoVotedPond = crocoWinner;

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
            vals[i] = seasonsHistory[index].totalGooseStakeDurationPerPond[i];
        }
        return vals;
    }

    /*
    * used by switchPond, save the unclaimed rewards to stake structs.
    *
    */

    function gooseClaimToBalance(uint16[] calldata tokenIds) public {
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
                    uint256 rank = getRank(pool, seasonsHistory[j].topPonds);
                    uint32 stakeDuration = seasonsHistory[j].seasonLastBlockNumber - seasonsHistory[j].seasonFirstBlockNumber;
                    //uint32 previousOpenBlock = seasonsHistory[j].blockNumber - stakeDuration; // previous

                    // bug found(fixed): for those Goose whose Pond is in Top 3 rank, but are overdued in this Season.
                    if( rank == 0 || gooseStake[tokenIds[i]].blockNumber < seasonsHistory[j].seasonFirstBlockNumber ) {
                        // pond_rewards = GEGG_DAILY_LIMIT * 0.3 * 1 / 7; 7 is sum of 6 Ponds and 1 Barn.
                        pond_rewards = GEGG_DAILY_LIMIT * 3 / 10 / 7;   // todo: need to float type
                        
                    }else {
                        // two conditions are required: 
                        // 1. rank is in Top 3, and 2. Goose's stake Time is within this Season.
                        // pond_rewards = GEGG_DAILY_LIMIT * 0.7 * ( 4 / 6 - rank / 6); rank is 1, 2 or 3;
                        pond_rewards = GEGG_DAILY_LIMIT * 7 / 10 * 4 / 6 -  GEGG_DAILY_LIMIT * 7 / 10 * rank / 6;
                    }

                    if ( pool == Pool(seasonsHistory[j].crocoVotedPond) ){ 
                        //pond_rewards = 0;
                    }

                    if( gooseStake[tokenIds[i]].blockNumber < seasonsHistory[j].seasonFirstBlockNumber ){
                        //stakeDuration = ( seasonsHistory[j].blockNumber - genisisBlockNumber ) % (SEASON_DURATION + SEASON_REST);
                        gooseStake[tokenIds[i]].unclaimedBalance += pond_rewards * stakeDuration / seasonsHistory[j].totalGooseStakeDurationPerPond[uint(Pool.Barn)];

                    }else{
                        require( seasonsHistory[j].seasonLastBlockNumber > gooseStake[tokenIds[i]].blockNumber, "Your NFT have't participated in the Season" );
                        stakeDuration = seasonsHistory[j].seasonLastBlockNumber - gooseStake[tokenIds[i]].blockNumber;
                        gooseStake[tokenIds[i]].unclaimedBalance += pond_rewards * stakeDuration / seasonsHistory[j].totalGooseStakeDurationPerPond[uint(pool)];

                    }
                    
                    totalDuration += stakeDuration;
                    console.log("pool No.     = ", uint(pool));
                    console.log("pool rank    = ", rank);
                    console.log("pond_rewards = ", pond_rewards);
                    console.log("stakeDuration    = ", stakeDuration);

                }
            }
            // change stake blockNumber of NFT after claim, move it from Pond to Barn.
            
            gooseStake[tokenIds[i]].blockNumber = uint32(block.number);
            if( gooseStake[tokenIds[i]].pool != Pool.Barn ){
                gooseStake[tokenIds[i]].pool = Pool.Barn;
            }
        }
        console.log("gooseClaimToBalance / totalDuration = ", totalDuration );
        
        
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
        return ( seasonsHistory[i].totalCrocoVoteDuration != 0 || seasonsHistory[i].topPonds != 0 );
    }

    function printBlockNumber () view public returns ( uint ) {
        return block.number;
    }

}