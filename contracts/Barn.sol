// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;


import "./Ownable.sol";
import "./Pausable.sol";
import "./IGoose.sol";
import "./CrocoDao.sol";
import "./GEGG.sol";
import "./IBarn.sol";
import "./EnumerableSet.sol";

import "hardhat/console.sol";

contract Barn is IBarn, Ownable, Pausable {

    bool isTestRun = true;

    //// GEGG parameters
    uint constant multiplier = 1;
    uint public constant GEGG_DAILY_LIMIT = 1000000 * multiplier;

    //// SEASON parameters
    uint16 public seasonDuration = 115;
    uint16 public restDuration = 20;
    uint16 public MAX_ALLOW_SEASON_DURATION = 120;
    uint16 public MIN_ALLOW_SEASON_DURATION = 100;
    uint16 public MAX_ALLOW_SEASON_REST = 20;
    uint16 public MIN_ALLOW_SEASON_REST = 10;

    /// Event to be raised when updating season/rest duration
    event EmitSessionAndRestDurationChanged(uint16 _seasonDuration, uint16 _restDuration);

    /// Function to update season/rest duration
    function updateSessionDuration(uint16 _seasonDuration, uint16 _restDuration) external onlyOwner  {

        require( _seasonDuration >= MIN_ALLOW_SEASON_DURATION && _seasonDuration <= MAX_ALLOW_SEASON_DURATION, "season duration exceed limit allowed");
        require( _restDuration >= MIN_ALLOW_SEASON_REST && _restDuration <= MAX_ALLOW_SEASON_REST, "season rest duration exceed limit allowed");

        seasonDuration = _seasonDuration;
        restDuration = _restDuration;
        
        emit EmitSessionAndRestDurationChanged(_seasonDuration, _restDuration);
    }

    // genesis block height to prevent game forking
    uint32 public genesisSessionBlockHeight;
    // Unique identifier for a game season.
    uint32 public seasonIndex;

    /// Event to be raised when updating season/rest duration
    event EmitInitialSessions(uint16 _seasonDuration, uint16 _restDuration);

    // Initial/reset all sessions
    function initialSessions(uint16 _seasonDuration, uint16 _restDuration) public onlyOwner  {
        require(_seasonDuration >= MIN_ALLOW_SEASON_DURATION && _seasonDuration <= MAX_ALLOW_SEASON_DURATION, "season duration exceed limit allowed");
        require(_restDuration >= MIN_ALLOW_SEASON_REST && _restDuration <= MAX_ALLOW_SEASON_REST, "season rest duration exceed limit allowed");

        seasonDuration = _seasonDuration;
        restDuration = _restDuration;

        for( uint32 i = 0; i < seasonIndex; i++ ){
            delete seasonRecord[i];
        }

        genesisSessionBlockHeight = uint32(block.number);
        seasonIndex = 0;

        emit EmitInitialSessions(_seasonDuration, _restDuration);
    }

    function initialSessions(uint16 _seasonDuration, uint16 _restDuration, bool _isTestRun) public onlyOwner  {
        if (_isTestRun == false) {
            require(_seasonDuration >= MIN_ALLOW_SEASON_DURATION && _seasonDuration <= MAX_ALLOW_SEASON_DURATION, "season duration exceed limit allowed");
            require(_restDuration >= MIN_ALLOW_SEASON_REST && _restDuration <= MAX_ALLOW_SEASON_REST, "season rest duration exceed limit allowed");
        }

        seasonDuration = _seasonDuration;
        restDuration = _restDuration;

        for( uint32 i = 0; i < seasonIndex; i++ ){
            delete seasonRecord[i];
        }

        genesisSessionBlockHeight = uint32(block.number);
        seasonIndex = 0;

        emit EmitInitialSessions(_seasonDuration, _restDuration);
    }

    // History of every season's record from genesis season。
    // will get updated once season closes.
    struct SeasonRecord {
        uint32 seasonOpenBlockHeight;
        uint32 seasonCloseTriggerBlockHeight;
        uint16 seasonDuration; // in blocks
        uint16 restDuration; // in blocks
        uint16 topPondsOfSession;  // indicate top 3 Ponds.
        uint8  crocoVotedPond;
        uint32 combineCrocoVotedDuration; 
        uint32[10] combineGooseLaidEggDurationInLocation; // duration of all geese laid egg in specific location
    }

    // Maps the session to a unique identifer
    mapping( uint32 => SeasonRecord ) public seasonRecord; 

    event newSeasonOpened(uint32 seasonIndex, uint32 seasonOpenBlockHeight, uint32 seasonDuration, uint32 restDuration);

    /*
    * will be reset on seasonBegan(), and seasonEnded()
    *
    */
    uint32 public seasonOpenBlockHeight = 0; 
    uint32 public seasonCloseBlockHeight = 0; 

    bool private _seasonInProgress = false;    
    

    function getSeasonID(uint32 seasonIndex_) internal view returns (uint256) {
        return uint(keccak256(abi.encode(seasonIndex_, genesisSessionBlockHeight)));
    }
    
    struct GooseRecord {
        uint16 gooseId;
        address gooseOwner;
        uint256 unclaimedGEGGBalance;  // unclaimed balance before the time of blockNumber.
        uint32 laidEggDuringSeasonIndex;
        uint256 laidEggDuringSeasonId;
        uint32 laidEggAtBlockHeight;  // this blockNumber is when the Goose laid egg /switched to this location. 
        Location laidEggLocation;
    }

    struct CrocoRecord{
        uint16 crocoId;
        address crocoOwner;
        uint256 unclaimedGEGGBalance;
        uint32 chosePondDuringSeasonIndex;
        uint256 chosePondDuringSeasonId;
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


    IGoose goose;
    CrocoDao croco;
    GEGG gegg;

    constructor( address _gegg, address _croco, address _goose, uint16 _seasonDuration, uint16 _restDuration ){
        gegg = GEGG(_gegg);
        croco = CrocoDao(_croco);
        goose = IGoose( _goose );
        initialSessions(_seasonDuration, _restDuration, isTestRun);
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

    function gooseLayingEggInPond(  Location _location, uint16[] calldata gooseIds ) external whenNotPaused{
        require ( seasonOpenBlockHeight != 0, "GooseGame Season has not initialized." );

        for( uint8 i = 0; i < gooseIds.length; i++ ){

            require(goose.ownerOf(gooseIds[i]) == _msgSender(), "Owner mismatch");

            // user transfer his/her own Goose NFT to Barn contract, this would revert if it fails ownership check.
            goose.transferFrom(_msgSender(), address(this), gooseIds[i]); 

            // if code runs at here, it implies the NFT was belonged to _msgSender()
            gooseRecord[gooseIds[i]] = GooseRecord({
                gooseId: gooseIds[i],
                gooseOwner: _msgSender(),
                unclaimedGEGGBalance: 0,
                laidEggDuringSeasonIndex: seasonIndex,
                laidEggDuringSeasonId: getSeasonID(seasonIndex),
                laidEggAtBlockHeight: uint32(block.number),
                laidEggLocation: _location
            });
            gooseIdsLocation[_location].add(gooseIds[i]);
            ownerGooseIds[_msgSender()].add(gooseIds[i]);
        }
    }

    function gooseSwitchingPond( Location _location, uint16[] calldata gooseIds ) external whenNotPaused{
        require ( seasonOpenBlockHeight != 0, "GooseGame Season has not initialized." );
        for( uint8 i = 0; i < gooseIds.length; i++ ){
            require( gooseRecord[gooseIds[i]].gooseOwner == _msgSender(), "You are not the Goose owner!" );
            require( gooseRecord[gooseIds[i]].laidEggDuringSeasonId == getSeasonID(seasonIndex), "Invalid SeasonID");
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
                chosePondDuringSeasonIndex: seasonIndex,
                chosePondDuringSeasonId: getSeasonID(seasonIndex),
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

    function seasonOpen() external {
        require ( _seasonInProgress == false, "Season is already on-going" );

        if ( seasonIndex != 0 ){
            uint32 lastIndex = seasonIndex - 1; // last index to be valid
            require ( block.number > ( seasonRecord[lastIndex].seasonOpenBlockHeight + seasonRecord[lastIndex].seasonDuration + seasonRecord[lastIndex].restDuration ), "Season is resting" );
        }

        seasonOpenBlockHeight = uint32(block.number);
        seasonCloseBlockHeight = seasonOpenBlockHeight + seasonDuration;

        seasonRecord[seasonIndex].seasonOpenBlockHeight = seasonOpenBlockHeight;
        seasonRecord[seasonIndex].seasonDuration = seasonDuration;
        seasonRecord[seasonIndex].restDuration = restDuration;

        _seasonInProgress = true;

        emit newSeasonOpened(seasonIndex, seasonOpenBlockHeight, seasonDuration, restDuration);
    }
    function seasonCloseTrigger() external {
        require ( _seasonInProgress == true, "Season has already Closed" );
        require ( block.number > seasonCloseBlockHeight, "Season close time hasn't arrived");
        _seasonInProgress = false;

        uint32 seasonCloseTriggerBlockHeight = uint32(block.number);
        seasonRecord[seasonIndex].seasonCloseTriggerBlockHeight = seasonCloseTriggerBlockHeight;

        uint256 curSeasonId = getSeasonID(seasonIndex);

        console.log("curSeasonIndex: ", seasonIndex);
        console.log("curSeasonId: ", curSeasonId);
        console.log("seasonOpenBlockHeight: ", seasonOpenBlockHeight);
        console.log("seasonCloseBlockHeight: ", seasonCloseBlockHeight);
        console.log("seasonDuration: ", seasonDuration);
        console.log("seasonCloseTriggerBlockHeight: ", seasonCloseTriggerBlockHeight);

        uint[] memory gooseAtLocationCounter = new uint[](10);
        uint[] memory crocoPoolVoteCounter = new uint[](10);

        uint32 laidEggDuration = 0;

        for ( uint8 i = uint8(Location.Barn); i <= uint8(Location.Pond9); i++ ){
            // todo: poolRealNumber need to be reset in each round.

            for ( uint j = 0; j < gooseIdsLocation[Location(i)].length(); j++ ){
                uint16 gooseID = uint16(gooseIdsLocation[Location(i)].at(j));
                uint32 gooseLaidEggAtBlockHeight = gooseRecord[gooseID].laidEggAtBlockHeight;
                uint256 gooseLaidEggDuringSeasonId = gooseRecord[gooseID].laidEggDuringSeasonId;

                console.log("gooseID", gooseID);
                console.log("gooseRecord[gooseID].laidEggAtBlockHeight: ", gooseLaidEggAtBlockHeight);

                if( gooseLaidEggAtBlockHeight < ( seasonOpenBlockHeight - restDuration ) ){
                    gooseAtLocationCounter[uint8(Location.Barn)] += 1; 
                    seasonRecord[seasonIndex].combineGooseLaidEggDurationInLocation[uint(Location.Barn)] += seasonDuration;
                } else if( gooseLaidEggAtBlockHeight < seasonOpenBlockHeight ){
                    require( gooseLaidEggDuringSeasonId == getSeasonID(seasonIndex), "Invalid SeasonID"); //should already accounted for laid egg during rest time before season
                    gooseAtLocationCounter[i] += 1;
                    seasonRecord[seasonIndex].combineGooseLaidEggDurationInLocation[i] += seasonDuration;
                } else if ( gooseLaidEggAtBlockHeight < seasonCloseBlockHeight )
                    {
                    require( gooseLaidEggDuringSeasonId == getSeasonID(seasonIndex), "Invalid SeasonID"); //should already accounted for laid egg during rest time before season
                    laidEggDuration = seasonCloseBlockHeight - gooseLaidEggAtBlockHeight;
                    gooseAtLocationCounter[i] += 1;
                    seasonRecord[seasonIndex].combineGooseLaidEggDurationInLocation[i] += laidEggDuration;
                }
            }
           
            for( uint j = 0; j < crocoIdsLocation[Location(i)].length(); j++ ) {
                uint16 crocoID = uint16(crocoIdsLocation[Location(i)].at(j));
                require( crocoRecord[crocoID].chosePondDuringSeasonId == getSeasonID(seasonIndex), "Invalid SeasonID"); //should already accounted for chose pond during rest time before season
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
            uint32 sIndex_from = gooseRecord[gooseIds[i]].laidEggDuringSeasonIndex;
            uint32 sIndex_to   = seasonIndex; // current SessonIndex
            console.log("sIndex_from", sIndex_from);
            console.log("sIndex_to", sIndex_to);

            Location location = gooseRecord[gooseIds[i]].laidEggLocation;
            uint32 gooseLaidEggAtBlockHeight = gooseRecord[gooseIds[i]].laidEggAtBlockHeight;
            uint256 gooseunclaimedGEGGBalance = gooseRecord[gooseIds[i]].unclaimedGEGGBalance;

            for ( uint32 j = sIndex_from; j <= sIndex_to; j ++ ){
                if( checkSeasonExists(j) ){
                    console.log("tik, seasonID = #", j);
                    uint256 round_rewards;
                    uint32 rank = getRank(location, seasonRecord[j].topPondsOfSession);
                    uint32 laidEggDuration;
                    uint32 focusSeasonOpenBlockHeight = seasonRecord[j].seasonOpenBlockHeight;
                    uint32 focusSeasonDuration = seasonRecord[j].seasonDuration;
                    uint32 focusSeasonRestDuration = seasonRecord[j].restDuration;

                    // bug found(fixed): for those Goose whose Pond is in Top 3 rank, but are overdued in this Season.
                    if( rank == 0 || gooseLaidEggAtBlockHeight < (focusSeasonOpenBlockHeight - focusSeasonRestDuration) ) {
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

                    if( gooseLaidEggAtBlockHeight < (focusSeasonOpenBlockHeight - focusSeasonRestDuration) ){
                        gooseunclaimedGEGGBalance += round_rewards * focusSeasonDuration / seasonRecord[j].combineGooseLaidEggDurationInLocation[uint(Location.Barn)];
                    } else if ( gooseLaidEggAtBlockHeight < focusSeasonOpenBlockHeight ) {
                        gooseunclaimedGEGGBalance += round_rewards * focusSeasonDuration / seasonRecord[j].combineGooseLaidEggDurationInLocation[uint(location)];
                    } else if ( gooseLaidEggAtBlockHeight < ( focusSeasonOpenBlockHeight + focusSeasonDuration ) ) {
                        laidEggDuration = ( focusSeasonOpenBlockHeight + focusSeasonDuration ) - gooseLaidEggAtBlockHeight;
                        gooseunclaimedGEGGBalance += round_rewards * laidEggDuration / seasonRecord[j].combineGooseLaidEggDurationInLocation[uint(location)];
                    }
                    
                    totalDuration += laidEggDuration;
                    console.log("pool No.     = ", uint(location));
                    console.log("pool rank    = ", rank);
                    console.log("round_rewards = ", round_rewards);
                    console.log("totalDuration    = ", totalDuration);
                }
            }
            // change stake blockNumber of NFT after claim, move it from Pond to Barn.
            
            gooseRecord[gooseIds[i]].unclaimedGEGGBalance = gooseunclaimedGEGGBalance;
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

    function checkSeasonExists( uint32 i) view internal returns (bool) {
        return ( seasonRecord[i].combineCrocoVotedDuration != 0 || seasonRecord[i].topPondsOfSession != 0 );
    }

    function printBlockNumber () view public returns ( uint ) {
        return block.number;
    }

}