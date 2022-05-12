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

    uint constant multiplier = 1;
    uint public constant GEGG_DAILY_LIMIT = 1000000 * multiplier;

    event newSeasonOpened(uint256 seasonIndex, uint32 seasonOpenBlockHeight, uint32 seasonDuration);

    // Event to be raised when updating season duration duration
    event EmitSessionDurationChanged(uint16 _seasonDuration, uint16 _seasonRest);

    // season duration
    uint16 public seasonDuration = 115;
    uint16 public seasonRest = 20;
    uint16 public MAX_ALLOW_SEASON_DURATION = 115;
    uint16 public MAX_ALLOW_SEASON_REST = 20;

    // History of every season's record from genesis season。
    // will get updated once season closes.
    struct SeasonRecord{
        uint32 seasonOpenBlockHeight;
        uint32 seasonCloseTriggerBlockHeight;
        uint16 seasonDuration; // in blocks
        uint16 seasonRest; // in blocks
        uint16 topPondsOfSession;  // indicate top 3 Ponds.
        uint8  crocoVotedPond;
        uint32 combineCrocoVotedDuration; 
        uint32[10] combineGooseLaidEggDurationInLocation; // duration of all geese laid egg in specific location
    }

    // Unique identifier for a game season.
    uint256 public seasonIndex;
    // Maps the session to a unique identifer
    mapping( uint256 => SeasonRecord ) public seasonRecord; 

    /*
    * will be reset on seasonBegan(), and seasonEnded()
    *
    */
    uint32 public seasonOpenBlockHeight = 0; 
    uint32 public seasonCloseBlockHeight = 0; 

    bool private _seasonInProgress = false;    
    
    struct GooseRecord {
        uint16 gooseId;
        address gooseOwner;
        uint256 unclaimedGEGGBalance;  // unclaimed balance before the time of blockNumber.
        uint256 laidEggDuringSeasonId;
        uint32 laidEggAtBlockHeight;  // this blockNumber is when the Goose laid egg /switched to this location. 
        Location laidEggLocation;
    }

    struct CrocoRecord{
        uint16 crocoId;
        address crocoOwner;
        uint256 unclaimedGEGGBalance;
        uint256 choseDuringSeasonId;
        uint32 choseAtBlockHeight;
        Location choseLocation;
    }

    mapping( uint16 => GooseRecord ) public gooseRecord;
    mapping( uint16 => CrocoRecord ) public crocoRecord;

    using EnumerableSet for EnumerableSet.UintSet;

    mapping( Location => EnumerableSet.UintSet ) gooseIdsLocation;  // Location to gooseIds[]
    mapping( Location => EnumerableSet.UintSet ) crocoIdsLocation;  // Location to crocoIds[]

    // Mapping from owner address to their (enumerable) set of owned Geese
    mapping( address => EnumerableSet.UintSet ) ownerGooseIds; // Address to gooseIds[]

    // Mapping from owner address to their (enumerable) set of owned Crocos
    mapping( address => EnumerableSet.UintSet ) ownerCrocosIds; // Address to crocoIds[]


    Goose goose;
    CrocoDao croco;
    GEGG gegg;

    constructor( address _gegg, address _croco, uint16 _seasonDuration, uint16 _seasonRest ){
        gegg = GEGG(_gegg);
        croco = CrocoDao(_croco);
        seasonDuration = _seasonDuration;
        seasonRest = _seasonRest;
    }

    function doPause() public onlyOwner{ // TODO: Should we add optional duration?
        _pause();
    }

    function doUnpause() public onlyOwner{
        _unpause();
    }

    function getGooseIdsFromOwnerAndIndex( address _user, uint _index ) public view returns ( uint ) {
        return ownerGooseIds[_user].at(_index);
    }

    function getNumberOfGooseInLocation( Location _location ) public view returns ( uint ) {
        return gooseIdsLocation[_location].length();
    }

    function gooseLayingEggInPond( address _user, Location _location, uint16[] calldata gooseIds ) external whenNotPaused{
        require ( seasonOpenBlockHeight != 0, "GooseGame Season has not initialized." );
        for( uint8 i = 0; i < gooseIds.length; i++ ){
            gooseRecord[gooseIds[i]] = GooseRecord({
                gooseId: gooseIds[i],
                gooseOwner: _user,
                unclaimedGEGGBalance: 0,
                laidEggDuringSeasonId: seasonIndex,
                laidEggAtBlockHeight: uint32(block.number),
                laidEggLocation: _location
            });
            gooseIdsLocation[_location].add(gooseIds[i]);
            ownerGooseIds[_user].add(gooseIds[i]);
        }
    }

    function gooseSwitchingPond( Location _location, uint16[] calldata gooseIds ) external whenNotPaused{
        require ( seasonOpenBlockHeight != 0, "GooseGame Season has not initialized." );
        for( uint8 i = 0; i < gooseIds.length; i++ ){
            require( gooseRecord[gooseIds[i]].gooseOwner == _msgSender(), "You are not the Goose owner!" );
            require( gooseRecord[gooseIds[i]].laidEggDuringSeasonId == seasonIndex, "Invalid SeasonID");
            require( gooseRecord[gooseIds[i]].laidEggLocation != _location, "Your goose is already laying egg at the location" );
            gooseRecord[gooseIds[i]].laidEggAtBlockHeight = uint32(block.number);
            gooseRecord[gooseIds[i]].laidEggLocation = _location;
        }
    }

    function crocoChoosingPond( address _user, Location _location, uint16[] calldata crocoIds ) external whenNotPaused{
        require ( seasonOpenBlockHeight != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < crocoIds.length; i++ ){            
            crocoRecord[crocoIds[i]] = CrocoRecord({
                crocoId: crocoIds[i],
                crocoOwner: _user,
                unclaimedGEGGBalance: 0,
                choseDuringSeasonId: seasonIndex,
                choseAtBlockHeight: uint32(block.number),
                choseLocation: _location
                }
            );
            crocoIdsLocation[_location].add(crocoIds[i]);
            ownerCrocosIds[_user].add(crocoIds[i]);
        }
    }

    // [Goose Rules update_20220421] not allowed for Croco changing votes

    // function changeCrocoVote( Location _to_location, uint16[] calldata crocoIds ) external whenNotPaused{
    //     require ( seasonOpenBlockHeight != 0, "GooseGame Season is not open yet." );
    //     for( uint8 i = 0; i < crocoIds.length; i++ ){
    //         require( crocoRecord[crocoIds[i]].crocoOwner == _msgSender(), "You are not the Croco owner!" );
    //         require( crocoRecord[crocoIds[i]].choseLocation != _to_location, "Your Croco have already voted this pool" );
    //         crocoRecord[crocoIds[i]].choseLocation = _to_location;
    //         crocoRecord[crocoIds[i]].choseAtBlockHeight = uint32(block.number);
    //     }
    // }

    // Update duration
    function updateSessionDuration(uint16 _seasonDuration, uint16 _seasonRest) external onlyOwner  {
        require(_seasonDuration != 0 && _seasonDuration <= MAX_ALLOW_SEASON_DURATION, "season duration not allowed");
        require(_seasonRest != 0 && _seasonRest <= MAX_ALLOW_SEASON_REST, "season rest duration not allowed");
        seasonDuration = _seasonDuration;
        seasonRest = _seasonRest;
        emit EmitSessionDurationChanged(_seasonDuration, _seasonRest);
    }

    function seasonOpen() external {
        require ( _seasonInProgress == false, "Season is already on-going" );

        if ( seasonIndex == 0 ){
            require ( _msgSender() == owner() );
        } else {
            uint256 lastIndex = seasonIndex - 1; // last index to be valid
            require ( block.number > ( seasonRecord[lastIndex].seasonOpenBlockHeight + seasonRecord[lastIndex].seasonDuration + seasonRecord[lastIndex].seasonRest ), "Season is resting" );
        }

        seasonOpenBlockHeight = uint32(block.number);
        seasonCloseBlockHeight = seasonOpenBlockHeight + seasonDuration;

        seasonRecord[seasonIndex].seasonOpenBlockHeight = seasonOpenBlockHeight;
        seasonRecord[seasonIndex].seasonDuration = seasonDuration;
        seasonRecord[seasonIndex].seasonRest = seasonRest;

        _seasonInProgress = true;

        emit newSeasonOpened(seasonIndex, seasonOpenBlockHeight, seasonDuration);
    }
    function seasonCloseTrigger() external {
        require ( _seasonInProgress == true, "Season has already Closed" );
        require ( block.number > seasonCloseBlockHeight, "Season close time hasn't arrived");
        _seasonInProgress = false;

        uint32 seasonCloseTriggerBlockHeight = uint32(block.number);
        seasonRecord[seasonIndex].seasonCloseTriggerBlockHeight = seasonCloseTriggerBlockHeight;

        console.log("curSeasonIndex: ", seasonIndex);
        console.log("seasonOpenBlockHeight: ", seasonOpenBlockHeight);
        console.log("seasonCloseBlockHeight: ", seasonCloseBlockHeight);
        console.log("seasonDuration: ", seasonDuration);
        console.log("seasonCloseTriggerBlockHeight: ", seasonCloseTriggerBlockHeight);

        uint[] memory gooseAtLocationCounter = new uint[](10);
        uint[] memory crocoPoolVoteCounter = new uint[](10);

        for ( uint8 i = uint8(Location.Barn); i <= uint8(Location.Pond9); i++ ){
            // todo: poolRealNumber need to be reset in each round.

            for ( uint j = 0; j < gooseIdsLocation[Location(i)].length(); j++ ){
                uint16 gooseID = uint16(gooseIdsLocation[Location(i)].at(j));
                require( gooseRecord[gooseID].laidEggDuringSeasonId == seasonIndex, "Invalid SeasonID"); //should already accounted for laid egg during rest time before season
                if( gooseRecord[gooseID].laidEggAtBlockHeight < seasonOpenBlockHeight ){
                    gooseAtLocationCounter[uint8(Location.Barn)] += 1; 
                    seasonRecord[seasonIndex].combineGooseLaidEggDurationInLocation[uint(Location.Barn)] += seasonDuration;
                }else{
                    uint32 laidEggDuration = seasonCloseBlockHeight - gooseRecord[gooseID].laidEggAtBlockHeight;
                    gooseAtLocationCounter[i] += 1;
                    seasonRecord[seasonIndex].combineGooseLaidEggDurationInLocation[i] += laidEggDuration;
                }
            }
           
            for( uint j = 0; j < crocoIdsLocation[Location(i)].length(); j++ ) {
                uint16 crocoID = uint16(crocoIdsLocation[Location(i)].at(j));
                require( crocoRecord[crocoID].choseDuringSeasonId == seasonIndex, "Invalid SeasonID"); //should already accounted for chose pond during rest time before season
                if( crocoRecord[crocoID].choseAtBlockHeight < seasonOpenBlockHeight ){
                    crocoPoolVoteCounter[uint8(Location.Barn)] += 1;
                }else{
                    uint32 votedDuration = seasonCloseBlockHeight - crocoRecord[crocoID].choseAtBlockHeight;
                    crocoPoolVoteCounter[i] += 1;
                    seasonRecord[seasonIndex].combineCrocoVotedDuration += votedDuration;
                }
            }
        }

        uint8 first = uint8(Location.Pond1);
        uint8 second = uint8(Location.Pond2);
        uint8 third = uint8(Location.Pond3);
        uint8 crocoWinner = uint8(Location.Pond1);
        for ( uint8 i = uint8(Location.Pond1); i <= uint8(Location.Pond9); i++ ){
            if ( gooseAtLocationCounter[i] < gooseAtLocationCounter[first] ){
                first = i;
            }
        }
        for ( uint8 i = uint8(Location.Pond1); i <= uint8(Location.Pond9); i++ ){
            if( i == first ) continue;
            if ( gooseAtLocationCounter[i] < gooseAtLocationCounter[second] ){
                second = i;
            }else if( second == first ){
                second = i;
            }
        }
        for ( uint8 i = uint8(Location.Pond1); i <= uint8(Location.Pond9); i++ ){
            if( i == second || i == first ) continue;
            if ( gooseAtLocationCounter[i] < gooseAtLocationCounter[third] ){
                third = i;
            }else if( third == second || third == first ){
                third = i;
            }
        }
        for ( uint8 i = uint8(Location.Pond1); i <= uint8(Location.Pond9); i++ ){
            if ( crocoPoolVoteCounter[i] > crocoPoolVoteCounter[crocoWinner] ){
                crocoWinner = i;
            }
        }

        uint16 winners = 0;
        winners |= first;
        winners <<= 4;
        winners |= second;
        winners <<= 4;
        winners |= third;
        console.log("first: ", first);
        console.log("second: ", second);
        console.log("third: ", third);
        console.log("gooseAtLocationCounter: ");
        //todo Need to notify via events.
        for ( uint8 i = uint8(Location.Barn); i <= uint8(Location.Pond9); i++ ){
            console.log("Location Pond #",i," = ",gooseAtLocationCounter[i]);
        }
        console.log("topPondsOfSession: ", winners);
        console.log("crocoVotedPondCounter: ");
        //todo Need to notify via events.
        for ( uint8 i = uint8(Location.Barn); i <= uint8(Location.Pond9); i++ ){
            console.log("Voted Pond #",i," = ",crocoPoolVoteCounter[i]);
        }
        console.log("crocoVotedPond: ", crocoWinner);
        seasonRecord[seasonIndex].topPondsOfSession = winners;
        seasonRecord[seasonIndex].crocoVotedPond = crocoWinner;

        seasonIndex = seasonIndex + 1; // next season need to set here in order to cover incoming rest as next season
    }

    function getRank( Location location, uint16 winnerNum ) view public returns (uint32) {
        console.log("winnerNum: ", winnerNum);
        for ( uint32 i = 3; i >= 1; i -- ){
            Location winner = Location( winnerNum & 0xf );
            if( winner == location ) return i;
            winnerNum >>= 4;
        }
        return 0;
    }

    function getCombineGooseLaidEggDurationPerLocationOfSeason( uint32 _seasonIndex ) view public returns ( uint32[] memory ){
        uint32[] memory vals = new uint32[](10);
        for( uint i = 0; i < 10; i++ ){
            vals[i] = seasonRecord[_seasonIndex].combineGooseLaidEggDurationInLocation[i];
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
            require( _msgSender() == gooseRecord[gooseIds[i]].gooseOwner, " It's not your NFT" );
            uint256 sID_from = gooseRecord[gooseIds[i]].laidEggDuringSeasonId;
            uint256 sID_to   = seasonIndex; // current SessonIndex
            console.log("sID_from", sID_from);
            console.log("sID_to", sID_to);
            for ( uint256 j = sID_from; j <= sID_to; j ++ ){
                if( checkSeasonExists(j) ){
                    console.log("tik, seasonID = #", j);
                    Location location = gooseRecord[gooseIds[i]].laidEggLocation;
                    uint256 round_rewards;
                    uint256 rank = getRank(location, seasonRecord[j].topPondsOfSession);
                    uint32 laidEggDuration;

                    // bug found(fixed): for those Goose whose Pond is in Top 3 rank, but are overdued in this Season.
                    if( rank == 0 || gooseRecord[gooseIds[i]].laidEggAtBlockHeight < seasonRecord[j].seasonOpenBlockHeight ) {
                        // round_rewards = GEGG_DAILY_LIMIT * 0.3 * 1 / 7; 7 is sum of 6 Ponds and 1 Barn.
                        round_rewards = GEGG_DAILY_LIMIT * 3 / 10 / 7;   // todo: need to float type // SAME AS BARN
                        
                    }else {
                        // two conditions are required: 
                        // 1. rank is in Top 3, and 2. Goose's stake Time is within this Season.
                        // round_rewards = GEGG_DAILY_LIMIT * 0.7 * ( 4 / 6 - rank / 6); rank (reverse for calculation) is 1, 2 or 3;
                        round_rewards = GEGG_DAILY_LIMIT * 7 / 10 * 4 / 6 -  GEGG_DAILY_LIMIT * 7 / 10 * rank / 6;
                    }

                    // TODO: Croco
                    if ( location == Location(seasonRecord[j].crocoVotedPond) ){ 
                        //round_rewards = 0;
                    }

                    // TODO: blockNumber to be round up as 2000 4000 6000 8000

                    if( gooseRecord[gooseIds[i]].laidEggAtBlockHeight < seasonRecord[j].seasonOpenBlockHeight ){
                        laidEggDuration = seasonRecord[j].seasonDuration;
                        gooseRecord[gooseIds[i]].unclaimedGEGGBalance += round_rewards * laidEggDuration / seasonRecord[j].combineGooseLaidEggDurationInLocation[uint(Location.Barn)];

                    }else{
                        require( ( seasonRecord[j].seasonOpenBlockHeight + seasonRecord[j].seasonDuration ) > gooseRecord[gooseIds[i]].laidEggAtBlockHeight, "Your NFT have't participated in the Season" );
                        laidEggDuration = ( seasonRecord[j].seasonOpenBlockHeight + seasonRecord[j].seasonDuration) - gooseRecord[gooseIds[i]].laidEggAtBlockHeight;
                        gooseRecord[gooseIds[i]].unclaimedGEGGBalance += round_rewards * laidEggDuration / seasonRecord[j].combineGooseLaidEggDurationInLocation[uint(location)];

                    }
                    
                    totalDuration += laidEggDuration;
                    console.log("pool No.     = ", uint(location));
                    console.log("pool rank    = ", rank);
                    console.log("round_rewards = ", round_rewards);
                    console.log("totalDuration    = ", totalDuration);

                }
            }
            // change stake blockNumber of NFT after claim, move it from Pond to Barn.
            
            gooseRecord[gooseIds[i]].laidEggAtBlockHeight = uint32(block.number);
            gooseRecord[gooseIds[i]].laidEggDuringSeasonId = 0;

            if( gooseRecord[gooseIds[i]].laidEggLocation != Location.Barn ){
                gooseRecord[gooseIds[i]].laidEggLocation = Location.Barn;
            }
        }        
        
    }

    function crocoClaimToBalance(uint16[] calldata crocoIds) public view {
        for( uint8 i = 0; i < crocoIds.length; i++ ){
            require( _msgSender() == crocoRecord[crocoIds[i]].crocoOwner, " It's not your NFT" );
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
    function gooseUnstaking( uint16[] calldata gooseIds ) external view {
        for( uint8 i = 0; i < gooseIds.length; i++ ){
            require( _msgSender() == gooseRecord[gooseIds[i]].gooseOwner, " It's not your NFT" );
        }
    }

    function crocoUnstaking( uint16[] calldata crocoIds ) external pure{
        for( uint8 i = 0; i < crocoIds.length; i++ ){
        
        }
    }

    function checkSeasonExists( uint256 i) view internal returns (bool) {
        return ( seasonRecord[i].combineCrocoVotedDuration != 0 || seasonRecord[i].topPondsOfSession != 0 );
    }

    function printBlockNumber () view public returns ( uint ) {
        return block.number;
    }
}