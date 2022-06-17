// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;


import "./Ownable.sol";
import "./Pausable.sol";
import "./IGoose.sol";
import "./CrocoDao.sol";
import "./GEGG.sol";
import "./IGoldenEggGame.sol";
import "./EnumerableSet.sol";

import "hardhat/console.sol";

contract GoldenEggGame is IGoldenEggGame, Ownable, Pausable {


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

    // genesis block height to prevent game forking
    uint32 public genesisSeasonBlockHeight;
    // Unique identifier for a game season.
    uint32 public seasonIndex;

    /// Event to be raised when updating season/rest duration
    event EmitSessionAndRestDurationChanged(uint16 _seasonDuration, uint16 _restDuration);

    /// Function to update season/rest duration
    function updateSessionDuration(uint16 _seasonDuration, uint16 _restDuration) public onlyOwner  {

        require( _seasonDuration >= MIN_ALLOW_SEASON_DURATION && _seasonDuration <= MAX_ALLOW_SEASON_DURATION, "season duration exceed limit allowed");
        require( _restDuration >= MIN_ALLOW_SEASON_REST && _restDuration <= MAX_ALLOW_SEASON_REST, "season rest duration exceed limit allowed");

        seasonDuration = _seasonDuration;
        restDuration = _restDuration;
        
        emit EmitSessionAndRestDurationChanged(_seasonDuration, _restDuration);
    }

    /// Event to be raised when updating season/rest duration
    event EmitInitialSessions(uint16 _seasonDuration, uint16 _restDuration);

    // Initial/reset all sessions
    function initialSessions(uint16 _seasonDuration, uint16 _restDuration) public onlyOwner  {

        updateSessionDuration(_seasonDuration, _restDuration);

        for( uint32 i = 0; i < seasonIndex; i++ ){
            delete seasonRecordIndex[i];
        }

        genesisSeasonBlockHeight = uint32(block.number);
        seasonIndex = 0;

        emit EmitInitialSessions(_seasonDuration, _restDuration);
    }

    function initialSessions(uint16 _seasonDuration, uint16 _restDuration, bool _isTestRun) public onlyOwner  {
        //needs careful attention: this action will clear out all users' unclaimed rewards.

        if (_isTestRun == false) {
            require(_seasonDuration >= MIN_ALLOW_SEASON_DURATION && _seasonDuration <= MAX_ALLOW_SEASON_DURATION, "season duration exceed limit allowed");
            require(_restDuration >= MIN_ALLOW_SEASON_REST && _restDuration <= MAX_ALLOW_SEASON_REST, "season rest duration exceed limit allowed");
        }

        if( seasonOpenBlockHeight > 0 ){
            // to make sure last Season is properly closed.
            
            require( block.number > seasonCloseBlockHeight &&  block.number < (seasonCloseBlockHeight + restDuration),
                    "reset is only allowed to happend during Season restDuration");
        }


        seasonDuration = _seasonDuration;
        restDuration = _restDuration;

        // all users' unclaimed rewards will be cleared out, need to notice 
        // and encourage user to claim and withdraw rewards before reset.
        for( uint32 i = 0; i < seasonIndex; i++ ){
            delete seasonRecordIndex[i];
        }

        genesisSeasonBlockHeight = uint32(block.number);
        seasonIndex = 0;


        // make sure the next Season cycle begains with seasonOpen();
        _seasonInProgress = false;
        seasonCloseBlockHeight = 0;
        seasonOpenBlockHeight = 0;

        // after initialSessions(reset), all NFTs still resides in contracts and recorded by gooseRecordIndex, and etc.
        // we need to take care when calculate rewards.

        emit EmitInitialSessions(_seasonDuration, _restDuration);


    }

    // History of every season's record from genesis season。
    // will get updated once season closes.
    struct SeasonRecord {
        uint32 seasonOpenBlockHeight;
        uint32 seasonCloseTriggerBlockHeight; // no need?
        uint16 seasonDuration; // in blocks
        uint16 restDuration; // in blocks
        uint16 topPondsOfSession;  // indicate top 3 Ponds.
        uint8  crocoVotedPond;
        uint32 combineCrocoVotedDuration; 
        uint32[10] combineGooseLaidEggDurationInLocation; // duration of all geese laid egg in specific location
    }

    // Maps the session to a unique identifer
    mapping( uint32 => SeasonRecord ) public seasonRecordIndex; 

    /*
    * will be reset on seasonBegan(), and seasonEnded()
    *
    */
    uint32 public seasonOpenBlockHeight = 0; 
    uint32 public seasonCloseBlockHeight = 0; 

    bool private _seasonInProgress = false;    

    struct UserRecord {
        uint8 moveAllowed; // amount of NFT + bonus
        uint8 moveCount;
        uint256 lastMoveSeasonId;
    }
    
    struct GooseRecord {
        uint16 gooseId;
        address gooseOwner;
        uint256 unclaimedGEGGBalance;  // todo: this will be eliminated. unclaimed balance before the time of blockNumber. 
        uint32 layEggDuringSeasonIndex;
        uint32 layEggAtBlockHeight;  // this blockNumber is when the Goose laid egg /switched to this location. 
        Location layEggLocation;
    }

    struct CrocoRecord{
        uint16 crocoId;
        address crocoOwner;
        uint256 unclaimedGEGGBalance;
        uint32 choosePondDuringSeasonIndex;
        uint32 choosePondAtBlockHeight;
        Location chooseLocation;
    }

    mapping( uint32 => UserRecord ) public userRecordIndex;
    mapping( uint32 => GooseRecord ) public gooseRecordIndex;
    mapping( uint32 => CrocoRecord ) public crocoRecordIndex;

    using EnumerableSet for EnumerableSet.UintSet;

    mapping( Location => EnumerableSet.UintSet ) gooseIdsInLocation;
    mapping( Location => EnumerableSet.UintSet ) crocoIdsInLocation;

    // Mapping from owner address to their (enumerable) set of owned Geese
    mapping( address => EnumerableSet.UintSet ) gooseIdsInOwnerAddress; // Address to gooseIds[]

    // Mapping from owner address to their (enumerable) set of owned Crocos
    mapping( address => EnumerableSet.UintSet ) crocoIdsInOwnerAddress; // Address to crocoIds[]


    IGoose goose;

    
    GEGG gegg;

    
    CrocoDao croco;

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

    function getGooseIdsFromOwnerAddressAndIndex( address _user, uint _index ) public view returns ( uint ) {
        return gooseIdsInOwnerAddress[_user].at(_index);
    }

    function getNumberOfGooseInLocation( Location _location ) public view returns ( uint ) {
        return gooseIdsInLocation[_location].length();
    }

    function gooseEnterGame( Location _location, uint16[] calldata gooseIdsCallData ) external whenNotPaused{
        require ( genesisSeasonBlockHeight != 0, "GooseGame has not initialized." );
        
        for( uint8 i = 0; i < gooseIdsCallData.length; i++ ){
            require(goose.ownerOf(gooseIdsCallData[i]) == _msgSender(), "Owner mismatch");

            // user transfer his/her own Goose NFT to Barn contract, this would revert if it fails ownership check.
            goose.transferFrom(_msgSender(), address(this), gooseIdsCallData[i]); 
            gooseRecordIndex[gooseIdsCallData[i]] = GooseRecord({
                gooseId: gooseIdsCallData[i],
                gooseOwner: _msgSender(),
                unclaimedGEGGBalance: 0,
                layEggDuringSeasonIndex: seasonIndex,
                layEggAtBlockHeight: uint32(block.number),
                layEggLocation: _location
            });

            gooseIdsInLocation[_location].add(gooseIdsCallData[i]);
            gooseIdsInOwnerAddress[_msgSender()].add(gooseIdsCallData[i]);
        }
    }

    function gooseSwitchLocation( Location _location, uint16[] calldata gooseIds ) external whenNotPaused{
        require ( gooseRecordIndex[gooseIds[0]].gooseOwner == _msgSender(), "You are not the Goose owner!" );
        // for( uint8 i = 0; i < gooseIds.length; i++ ){
        //  ...
        // } 
        gooseClaimToBalance(gooseIds);

        gooseRecordIndex[gooseIds[0]].layEggDuringSeasonIndex = seasonIndex;
        gooseRecordIndex[gooseIds[0]].layEggAtBlockHeight = uint32(block.number);

        Location oldLocation = gooseRecordIndex[gooseIds[0]].layEggLocation;
        gooseIdsInLocation[oldLocation].remove(gooseIds[0]);

        gooseRecordIndex[gooseIds[0]].layEggLocation = _location;
        gooseIdsInLocation[_location].add(gooseIds[0]);
    }

    function crocoEnterGame( address _user, Location _location, uint16[] calldata crocoIds ) external whenNotPaused{
        require ( genesisSeasonBlockHeight != 0, "GooseGame has not initialized." );
        for( uint8 i = 0; i < crocoIds.length; i++ ){            
            crocoRecordIndex[crocoIds[i]] = CrocoRecord({
                crocoId: crocoIds[i],
                crocoOwner: _user,
                unclaimedGEGGBalance: 0,
                choosePondDuringSeasonIndex: seasonIndex,
                choosePondAtBlockHeight: uint32(block.number),
                chooseLocation: _location
                }
            );
            crocoIdsInLocation[_location].add(crocoIds[i]);
            crocoIdsInOwnerAddress[_user].add(crocoIds[i]);
        }
    }

    function crocoSwitchLocation( Location _location, uint16[] calldata crocoIds ) external whenNotPaused{
        for( uint8 i = 0; i < crocoIds.length; i++ ){
            require( crocoRecordIndex[crocoIds[i]].crocoOwner == _msgSender(), "You are not the Croco owner!" );
            crocoRecordIndex[crocoIds[i]].choosePondDuringSeasonIndex = seasonIndex;
            crocoRecordIndex[crocoIds[i]].choosePondAtBlockHeight = uint32(block.number);

            Location oldLocation = crocoRecordIndex[crocoIds[i]].chooseLocation;
            crocoIdsInLocation[oldLocation].remove(crocoIds[i]);

            crocoRecordIndex[crocoIds[i]].chooseLocation = _location;
            crocoIdsInLocation[_location].add(crocoIds[i]);
        }
    }

    function seasonOpen() external {
        require ( _seasonInProgress == false, "Season is already on-going" );

        if ( seasonIndex != 0 ){
            uint32 lastIndex = seasonIndex - 1; // last index to be valid
            require ( block.number > ( seasonRecordIndex[lastIndex].seasonOpenBlockHeight + seasonRecordIndex[lastIndex].seasonDuration + seasonRecordIndex[lastIndex].restDuration ), "Season is resting" );
        }

        seasonOpenBlockHeight = uint32(block.number);
        seasonCloseBlockHeight = seasonOpenBlockHeight + seasonDuration;

        seasonRecordIndex[seasonIndex].seasonOpenBlockHeight = seasonOpenBlockHeight;
        seasonRecordIndex[seasonIndex].seasonDuration = seasonDuration;
        seasonRecordIndex[seasonIndex].restDuration = restDuration;

        _seasonInProgress = true;
    }
    function seasonCloseTrigger() external {
        require ( _seasonInProgress == true, "Season has already Closed" );
        require ( block.number > seasonCloseBlockHeight, "Season close time hasn't arrived");
        _seasonInProgress = false;

        uint32 seasonCloseTriggerBlockHeight = uint32(block.number);
        seasonRecordIndex[seasonIndex].seasonCloseTriggerBlockHeight = seasonCloseTriggerBlockHeight;


        console.log("curSeasonIndex: ", seasonIndex);
        console.log("seasonOpenBlockHeight: ", seasonOpenBlockHeight);
        console.log("seasonCloseBlockHeight: ", seasonCloseBlockHeight);
        console.log("seasonDuration: ", seasonDuration);
        console.log("seasonCloseTriggerBlockHeight: ", seasonCloseTriggerBlockHeight);

        uint[] memory gooseAtLocationCounter = new uint[](10);
        uint[] memory crocoPoolVoteCounter = new uint[](10);

        uint32 layEggDuration = 0;

        for ( uint8 i = uint8(Location.Barn); i <= uint8(Location.Pond9); i++ ){
            // todo: poolRealNumber need to be reset in each round.

            for ( uint j = 0; j < gooseIdsInLocation[Location(i)].length(); j++ ){
                uint16 gooseID = uint16(gooseIdsInLocation[Location(i)].at(j));
                uint32 gooseLaidEggAtBlockHeight = gooseRecordIndex[gooseID].layEggAtBlockHeight;

                console.log("gooseID", gooseID);
                console.log("gooseRecordIndex[gooseID].layEggAtBlockHeight: ", gooseLaidEggAtBlockHeight);

                if( gooseLaidEggAtBlockHeight < ( seasonOpenBlockHeight - restDuration ) ){
                    gooseAtLocationCounter[uint8(Location.Barn)] += 1; 
                    seasonRecordIndex[seasonIndex].combineGooseLaidEggDurationInLocation[uint(Location.Barn)] += seasonDuration;
                } else if( gooseLaidEggAtBlockHeight < seasonOpenBlockHeight ){ // during rest period
                    gooseAtLocationCounter[i] += 1;
                    seasonRecordIndex[seasonIndex].combineGooseLaidEggDurationInLocation[i] += seasonDuration;
                } else if ( gooseLaidEggAtBlockHeight < seasonCloseBlockHeight ){
                    gooseAtLocationCounter[i] += 1;
                    layEggDuration = seasonCloseBlockHeight - gooseLaidEggAtBlockHeight;
                    seasonRecordIndex[seasonIndex].combineGooseLaidEggDurationInLocation[i] += layEggDuration;
                }
            }

            for( uint j = 0; j < crocoIdsInLocation[Location(i)].length(); j++ ) {
                uint16 crocoID = uint16(crocoIdsInLocation[Location(i)].at(j));
                uint32 crocoChoosePondAtBlockHeight = crocoRecordIndex[crocoID].choosePondAtBlockHeight;
                if( crocoRecordIndex[crocoID].choosePondAtBlockHeight < seasonOpenBlockHeight ){
                    crocoPoolVoteCounter[uint8(Location.Barn)] += 1;
                }else{
                    uint32 votedDuration = seasonCloseBlockHeight - crocoRecordIndex[crocoID].choosePondAtBlockHeight;
                    crocoPoolVoteCounter[i] += 1;
                    seasonRecordIndex[seasonIndex].combineCrocoVotedDuration += votedDuration;
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
            if( i == first ) {
                continue;
            }else if( second == first ){
                // code runs at here implies i != first, so let second = i, to make sure second and first is different.
                second = i;
            }
            if ( gooseAtLocationCounter[i] < gooseAtLocationCounter[second] ){
                second = i;
            }
        }
        for ( uint8 i = uint8(Location.Pond1); i <= uint8(Location.Pond9); i++ ){
            if( i == second || i == first ) {
                continue;
            } else if ( third == second || third == first ){
                third = i;
            }
            if ( gooseAtLocationCounter[i] < gooseAtLocationCounter[third] ){
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
        console.log("winners: ", winners);
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
        seasonRecordIndex[seasonIndex].topPondsOfSession = winners;
        seasonRecordIndex[seasonIndex].crocoVotedPond = crocoWinner;

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
            vals[i] = seasonRecordIndex[_seasonIndex].combineGooseLaidEggDurationInLocation[i];
        }
        return vals;
    }

    /*
    * used by gooseSwitchLocation, save the unclaimed rewards to stake structs.
    *
    */

    function gooseClaimToBalance(uint16[] calldata gooseIds) public {
        for( uint8 i = 0; i < gooseIds.length; i++ ){
            require( _msgSender() == gooseRecordIndex[gooseIds[i]].gooseOwner, " It's not your NFT" );
            uint32 layEggDuringSeasonIndex = gooseRecordIndex[gooseIds[i]].layEggDuringSeasonIndex;
            uint32 currentSeasonIndex = seasonIndex; // current SessonIndex
            console.log("layEggDuringSeasonIndex", layEggDuringSeasonIndex);
            console.log("currentSeasonIndex", currentSeasonIndex);

            Location layEggLocation = gooseRecordIndex[gooseIds[i]].layEggLocation;
            uint32 layEggAtBlockHeight = gooseRecordIndex[gooseIds[i]].layEggAtBlockHeight;
            uint256 gooseunclaimedGEGGBalance = gooseRecordIndex[gooseIds[i]].unclaimedGEGGBalance;

            for ( uint32 j = layEggDuringSeasonIndex; j <= currentSeasonIndex; j ++ ){
                if( checkSeasonExists(j) ){
                    console.log("seasonID = #", j);
                    uint256 round_rewards = 0;
                    uint32 rankOfPond = getRank(layEggLocation, seasonRecordIndex[j].topPondsOfSession);
                    uint32 layEggDuration;
                    uint32 focusSeasonOpenBlockHeight = seasonRecordIndex[j].seasonOpenBlockHeight;
                    uint32 focusSeasonDuration = seasonRecordIndex[j].seasonDuration;
                    uint32 focusSeasonCloseBlockHeight = focusSeasonOpenBlockHeight + focusSeasonDuration;
                    uint32 focusSeasonRestDuration = seasonRecordIndex[j].restDuration;

                    // for those Goose whose Pond is not in Top 3 rank, or are overdued in this Season.
                    if( rankOfPond == 0 || layEggAtBlockHeight < (focusSeasonOpenBlockHeight - focusSeasonRestDuration) ) {
                        round_rewards = GEGG_DAILY_LIMIT * 3 / 10 / 7;   // todo: need to float type // SAME AS BARN
                        
                    } else if( layEggAtBlockHeight <= focusSeasonOpenBlockHeight || layEggAtBlockHeight <= focusSeasonCloseBlockHeight) { // including during rest period and season
                        // two conditions are required: 
                        // 1. rank is in Top 3, and 2. Goose's stake Time is within this Season.
                        // round_rewards = GEGG_DAILY_LIMIT * 0.7 * ( 4 / 6 - rank / 6); rank (reverse for calculation) is 1, 2 or 3;
                        round_rewards = GEGG_DAILY_LIMIT * 7 / 10 * 4 / 6 -  GEGG_DAILY_LIMIT * 7 / 10 * rankOfPond / 6;
                    }

                    // TODO: Croco
                    if ( layEggLocation == Location(seasonRecordIndex[j].crocoVotedPond) ){ 
                        //round_rewards = 0;
                    }

                    // TODO: blockNumber to be round up as 2000 4000 6000 8000

                    if( layEggAtBlockHeight < (focusSeasonOpenBlockHeight - focusSeasonRestDuration) ){
                        gooseunclaimedGEGGBalance += round_rewards * focusSeasonDuration / seasonRecordIndex[j].combineGooseLaidEggDurationInLocation[uint(Location.Barn)];
                    } else if ( layEggAtBlockHeight < focusSeasonOpenBlockHeight ) {
                        gooseunclaimedGEGGBalance += round_rewards * focusSeasonDuration / seasonRecordIndex[j].combineGooseLaidEggDurationInLocation[uint(layEggLocation)];
                    } else if ( layEggAtBlockHeight < ( focusSeasonOpenBlockHeight + focusSeasonDuration ) ) {
                        layEggDuration = ( focusSeasonOpenBlockHeight + focusSeasonDuration ) - layEggAtBlockHeight;
                        gooseunclaimedGEGGBalance += round_rewards * layEggDuration / seasonRecordIndex[j].combineGooseLaidEggDurationInLocation[uint(layEggLocation)];
                    }
                    
                    console.log("Pond No.     = ", uint(layEggLocation));
                    console.log("Pond Rank    = ", rankOfPond);
                    console.log("Round Reward = ", round_rewards);
                }
            }
            // change stake blockNumber of NFT after claim, move it from Pond to Barn.
            
            gooseRecordIndex[gooseIds[i]].unclaimedGEGGBalance = gooseunclaimedGEGGBalance;
            gooseRecordIndex[gooseIds[i]].layEggAtBlockHeight = uint32(block.number);
            gooseRecordIndex[gooseIds[i]].layEggDuringSeasonIndex = currentSeasonIndex; // avoid duplicate rewards.

            if( gooseRecordIndex[gooseIds[i]].layEggLocation != Location.Barn ){
                gooseRecordIndex[gooseIds[i]].layEggLocation = Location.Barn;
            }

            //todo: the arg gooseunclaimedGEGGBalance should be carefully verified and tested.
            gegg.mint(_msgSender(), gooseunclaimedGEGGBalance);

        }        
        
    }

    function crocoClaimToBalance(uint16[] calldata crocoIds) public view {
        for( uint8 i = 0; i < crocoIds.length; i++ ){
            require( _msgSender() == crocoRecordIndex[crocoIds[i]].crocoOwner, " It's not your NFT" );
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
            require( _msgSender() == gooseRecordIndex[gooseIds[i]].gooseOwner, " It's not your NFT" );
        }
    }

    function crocoUnstaking( uint16[] calldata crocoIds ) external pure{
        for( uint8 i = 0; i < crocoIds.length; i++ ){
        
        }
    }

    function checkSeasonExists( uint32 i) view internal returns (bool) {
        return ( seasonRecordIndex[i].combineGooseLaidEggDurationInLocation[0] != 0 || seasonRecordIndex[i].topPondsOfSession != 0 );
    }

    function printBlockNumber () view public returns ( uint ) {
        return block.number;
    }

}