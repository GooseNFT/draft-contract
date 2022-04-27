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


    struct GooseStats {
        uint16 gooseId;
        address owner;
        uint32 blockNumber;  // this blockNumber is when the Goose staked /switched to this location. 
        uint256 unclaimedBalance;  // unclaimed balance before the time of blockNumber.
        Location location;
    }

    struct CrocoStats{
        uint16 crocoId;
        address owner;
        uint32 blockNumber;
        uint256 unclaimedBalance;
        Location location;
    }

    struct SeasonStats{
        uint32 seasonFirstBlockHeight;
        uint32 seasonLastBlockHeight;
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
    uint32 public currentSeasonFirstBlockHeight = 0; 
    uint32 public currentSeasonLastBlockHeight = 0;

    bool private _seasonIsInProgress = false;

    uint32 public genisisBlockNumber = 0;

    mapping( uint16 => GooseStats ) public gooseStake;
    mapping( uint16 => CrocoStats ) public crocoStake;

    using EnumerableSet for EnumerableSet.UintSet;

    mapping( Location => EnumerableSet.UintSet ) gooseLocation;  // Location to gooseIds[]
    mapping( Location => EnumerableSet.UintSet ) crocoLocation;  // Location to crocoIds[]

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

    function doPause() public onlyOwner{
        _pause();
    }

    function doUnpause() public onlyOwner{
        _unpause();
    }

    function getUserStakedGooseIds( address _owner, uint _index ) public view returns ( uint ) {
        return userGooseIds[_owner].at(_index);
    }

    function getGooseSetNum( Location _location )  public view returns (uint) {
        return gooseLocation[_location].length();
    }

    function stakeGooseConfirm( address _owner, Location _location, uint16[] calldata gooseIds ) external whenNotPaused{
        require ( currentSeasonFirstBlockHeight != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < gooseIds.length; i++ ){
            gooseStake[gooseIds[i]] = GooseStats({
                gooseId: gooseIds[i],
                owner: _owner,
                blockNumber: uint32(block.number),
                unclaimedBalance: 0,
                location: _location
            });
            gooseLocation[_location].add(gooseIds[i]);
            userGooseIds[_owner].add(gooseIds[i]);
        }
    }



    function switchGoosePond( Location _to_location, uint16[] calldata gooseIds ) external whenNotPaused{
        require ( currentSeasonFirstBlockHeight != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < gooseIds.length; i++ ){
            require( gooseStake[gooseIds[i]].owner == _msgSender(), "You are not the Goose owner!" );
            require( gooseStake[gooseIds[i]].location != _to_location, "You are already in this location" );
            gooseStake[gooseIds[i]].location = _to_location;
            gooseStake[gooseIds[i]].blockNumber = uint32(block.number);
        }
    }

    function stakeCrocoAndVote( Location _location, uint16[] calldata crocoIds ) external whenNotPaused{
        require ( currentSeasonFirstBlockHeight != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < crocoIds.length; i++ ){
            require( croco.ownerOf(crocoIds[i]) == _msgSender(), "Your are not the Croco owner!" );
            croco.transferFrom( _msgSender(), address(this), crocoIds[i] );
            
            
            crocoStake[crocoIds[i]] = CrocoStats(
                {
                crocoId: crocoIds[i],
                owner: _msgSender(),
                blockNumber: uint32(block.number),
                unclaimedBalance: 0,
                location: _location
                }
            );
            crocoLocation[_location].add(crocoIds[i]);
        }
         
    }

    function changeCrocoVote( Location _to_location, uint16[] calldata crocoIds ) external whenNotPaused{
        require ( currentSeasonFirstBlockHeight != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < crocoIds.length; i++ ){
            require( crocoStake[crocoIds[i]].owner == _msgSender(), "You have no NFT stacked" );
            require( crocoStake[crocoIds[i]].location != _to_location, "You have already voted this pool" );
            crocoStake[crocoIds[i]].location = _to_location;
            crocoStake[crocoIds[i]].blockNumber = uint32(block.number);
        }
    }

    function seasonOpen() external {
        if ( currentSeasonFirstBlockHeight == 0 ){
            require ( _msgSender() == owner() );
            genisisBlockNumber = uint32(block.number);
        }
        require ( _seasonIsInProgress == false, "Season is already on-going" );
        require ( block.number >  currentSeasonLastBlockHeight + SEASON_REST, "Season is resting" );
        _seasonIsInProgress = true;
        currentSeasonFirstBlockHeight = uint32(block.number);
        
    }

    function getCurrentSeasonID()  private view returns (uint32)  {
        return ( ( uint32(block.number) - genisisBlockNumber ) / (SEASON_DURATION + SEASON_REST) );
    } 

    function getSeasonID( uint32 blockNumber )  private view returns (uint32)  {

        require ( blockNumber>= genisisBlockNumber, "blockNumber >= genisisBlockNumber check fail.");
        return ( ( blockNumber - genisisBlockNumber ) / (SEASON_DURATION + SEASON_REST) );
    } 

    function seasonClose() external {
        require ( _seasonIsInProgress == true, "Season is already Closed" );
        require ( block.number > currentSeasonFirstBlockHeight + SEASON_DURATION, "Season close time isn't arrived");
        _seasonIsInProgress = false;
        currentSeasonLastBlockHeight = uint32(block.number);


        uint[] memory gooseLocationCounter = new uint[](10);
        uint[] memory poolVoteCounter = new uint[](10);


        uint32 curSeasonSeq = getCurrentSeasonID(); // todo: this might be incorrect because open and close time might not be happend in time.
        console.log("curSeasonSeq: ", curSeasonSeq);
        seasonsHistory[curSeasonSeq].seasonFirstBlockHeight = currentSeasonFirstBlockHeight;
        seasonsHistory[curSeasonSeq].seasonLastBlockHeight = currentSeasonLastBlockHeight;


        for ( uint8 i = uint8(Location.Barn); i <= uint8(Location.Pond9); i++ ){
            // todo: poolRealNumber need to be reset in each round.

            for ( uint j = 0; j < gooseLocation[Location(i)].length(); j++ ){
                uint32 stakeDuration = currentSeasonLastBlockHeight - currentSeasonFirstBlockHeight;
                //uint32 previousOpenBlock = currentSeasonLastBlockHeight - stakeDuration;
                uint16 tokenID = uint16(gooseLocation[Location(i)].at(j));
                if( gooseStake[tokenID].blockNumber < currentSeasonFirstBlockHeight ){
                    gooseLocationCounter[uint8(Location.Barn)] += 1; 
                    seasonsHistory[curSeasonSeq].totalGooseStakeDurationPerPond[uint(Location.Barn)] += stakeDuration;
                }else{
                    stakeDuration = currentSeasonLastBlockHeight - gooseStake[tokenID].blockNumber;
                    gooseLocationCounter[i] += 1;
                    seasonsHistory[curSeasonSeq].totalGooseStakeDurationPerPond[i] += stakeDuration;
                }

            }
           

            for( uint j = 0; j < crocoLocation[Location(i)].length(); j++ ) {
                uint16 crocoID = uint16(crocoLocation[Location(i)].at(j));
                if( crocoStake[crocoID].blockNumber < currentSeasonFirstBlockHeight ){
                    poolVoteCounter[uint8(Location.Barn)] += 1;
                }else{
                    poolVoteCounter[i] += 1;
                    seasonsHistory[curSeasonSeq].totalCrocoVoteDuration += currentSeasonLastBlockHeight - crocoStake[crocoID].blockNumber;
                }
            }
        }

        uint8 first = uint8(Location.Pond1);
        uint8 second = uint8(Location.Pond2);
        uint8 third = uint8(Location.Pond3);
        uint8 crocoWinner = uint8(Location.Pond1);
        for ( uint8 i = uint8(Location.Pond1); i <= uint8(Location.Pond9); i++ ){
            if ( gooseLocationCounter[i] < gooseLocationCounter[first]  ){
                first = i;
            }
        }
        for ( uint8 i = uint8(Location.Pond1); i <= uint8(Location.Pond9); i++ ){
            if( i == first ) continue;
            if ( gooseLocationCounter[i] < gooseLocationCounter[second] ){
                second = i;
            }else if( second == first ){
                second = i;
            }
        }
        for ( uint8 i = uint8(Location.Pond1); i <= uint8(Location.Pond9); i++ ){
            if( i == second || i == first ) continue;
            if ( gooseLocationCounter[i] < gooseLocationCounter[third] ){
                third = i;
            }else if( third == second || third == first ){
                third = i;
            }
        }
        for ( uint8 i = uint8(Location.Pond1); i <= uint8(Location.Pond9); i++ ){
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
        console.log("gooseLocationCounter : ");
        //todo Need to notify via events.
        for ( uint8 i = uint8(Location.Barn); i <= uint8(Location.Pond9); i++ ){
            console.log("Location Pond #",i," = ",gooseLocationCounter[i]);
        }
        seasonsHistory[curSeasonSeq].topPonds = winners;
        seasonsHistory[curSeasonSeq].crocoVotedPond = crocoWinner;

    }

    function getRank( Location location, uint16 winnerNum ) view public returns (uint32) {
        console.log("winnderNum: ", winnerNum);
        for ( uint32 i = 3; i >= 1; i -- ){
            Location winner = Location( winnerNum & 0xf );
            if( winner == location ) return i;
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

    function gooseClaimToBalance(uint16[] calldata gooseIds) public {
        uint32 totalDuration = 0;
        for( uint8 i = 0; i < gooseIds.length; i++ ){
            require( _msgSender() == gooseStake[gooseIds[i]].owner, " It's not your NFT" );
            uint32 sID_from = getSeasonID(gooseStake[gooseIds[i]].blockNumber);
            uint32 sID_to   = getCurrentSeasonID();
            console.log("sID_from", sID_from);
            console.log("sID_to", sID_to);
            for ( uint32 j = sID_from; j <= sID_to; j ++ ){
                if( checkSeasonExists(j) ){
                    console.log("tik, seasonID = #", j);
                    Location location = gooseStake[gooseIds[i]].location;
                    uint256 round_rewards;
                    uint256 rank = getRank(location, seasonsHistory[j].topPonds);
                    uint32 stakeDuration = seasonsHistory[j].seasonLastBlockHeight - seasonsHistory[j].seasonFirstBlockHeight; // Wrong? gooseStake[gooseIds[i]].blockNumber
                    //uint32 previousOpenBlock = seasonsHistory[j].blockNumber - stakeDuration; // previous

                    // bug found(fixed): for those Goose whose Pond is in Top 3 rank, but are overdued in this Season.
                    if( rank == 0 || gooseStake[gooseIds[i]].blockNumber < seasonsHistory[j].seasonFirstBlockHeight ) {
                        // round_rewards = GEGG_DAILY_LIMIT * 0.3 * 1 / 7; 7 is sum of 6 Ponds and 1 Barn.
                        round_rewards = GEGG_DAILY_LIMIT * 3 / 10 / 7;   // todo: need to float type // SAME AS BARN
                        
                    }else {
                        // two conditions are required: 
                        // 1. rank is in Top 3, and 2. Goose's stake Time is within this Season.
                        // round_rewards = GEGG_DAILY_LIMIT * 0.7 * ( 4 / 6 - rank / 6); rank (reverse for calculation) is 1, 2 or 3;
                        round_rewards = GEGG_DAILY_LIMIT * 7 / 10 * 4 / 6 -  GEGG_DAILY_LIMIT * 7 / 10 * rank / 6;
                    }

                    if ( location == Location(seasonsHistory[j].crocoVotedPond) ){ 
                        //round_rewards = 0;
                    }

                    // blockNumber to be round up as 2000 4000 6000 8000

                    if( gooseStake[gooseIds[i]].blockNumber < seasonsHistory[j].seasonFirstBlockHeight ){
                        gooseStake[gooseIds[i]].unclaimedBalance += round_rewards * stakeDuration / seasonsHistory[j].totalGooseStakeDurationPerPond[uint(Location.Barn)];

                    }else{
                        require( seasonsHistory[j].seasonLastBlockHeight > gooseStake[gooseIds[i]].blockNumber, "Your NFT have't participated in the Season" );
                        stakeDuration = seasonsHistory[j].seasonLastBlockHeight - gooseStake[gooseIds[i]].blockNumber;
                        gooseStake[gooseIds[i]].unclaimedBalance += round_rewards * stakeDuration / seasonsHistory[j].totalGooseStakeDurationPerPond[uint(location)];

                    }
                    
                    totalDuration += stakeDuration;
                    console.log("pool No.     = ", uint(location));
                    console.log("pool rank    = ", rank);
                    console.log("round_rewards = ", round_rewards);
                    console.log("stakeDuration    = ", stakeDuration);

                }
            }
            // change stake blockNumber of NFT after claim, move it from Pond to Barn.
            
            gooseStake[gooseIds[i]].blockNumber = uint32(block.number);
            if( gooseStake[gooseIds[i]].location != Location.Barn ){
                gooseStake[gooseIds[i]].location = Location.Barn;
            }
        }
        console.log("gooseClaimToBalance / totalDuration = ", totalDuration );
        
        
    }

    function crocoClaimToBalance(uint16[] calldata crocoIds) public {
        for( uint8 i = 0; i < crocoIds.length; i++ ){
            require( _msgSender() == crocoStake[crocoIds[i]].owner, " It's not your NFT" );
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
    function unGooseStats( uint16[] calldata gooseIds ) external {
        for( uint8 i = 0; i < gooseIds.length; i++ ){
            require( _msgSender() == gooseStake[gooseIds[i]].owner, " It's not your NFT" );
        }
    }

    function unCrocoStats( uint16[] calldata crocoIds ) external{
        for( uint8 i = 0; i < crocoIds.length; i++ ){
        
        }
    }

    function checkSeasonExists( uint32 i) view internal returns (bool) {
        return ( seasonsHistory[i].totalCrocoVoteDuration != 0 || seasonsHistory[i].topPonds != 0 );
    }

    function printBlockNumber () view public returns ( uint ) {
        return block.number;
    }

}