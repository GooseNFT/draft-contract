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
    uint16 public constant SEASON_DURATION  =  100;
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
    uint public lastOpenBlockNumber = 0; 
    uint public lastCloseBlockNumber = 0;
    bool private _isSeasonOpen = false;
    uint32 public genisisBlockNumber = 0;

    mapping( uint16 => StakeGoose ) public gooseStake;
    mapping( uint16 => StakeCroco ) public crocoStake;

    using EnumerableSet for EnumerableSet.UintSet;

    mapping( Pool => EnumerableSet.UintSet ) poolGoose;  // Pool to tokenIds[]
    mapping( Pool => EnumerableSet.UintSet ) poolCroco;  // Pool to tokenIds[]

    mapping( Pool => uint16 ) public poolRealNumber;
    mapping( Pool => uint16 ) public poolVotedNumber;

    Goose goose;
    address __goose;
    CrocoDao croco;
    GEGG egg;

    constructor( address _gegg, address _goose, address _croco ){
        egg = GEGG(_gegg);
        goose = Goose(_goose);
        __goose = _goose;
        croco = CrocoDao(_croco);
    }

    function getGooseSetNum( Pool _pool ) public view returns (uint, uint) {
        return (poolGoose[_pool].length(), poolRealNumber[_pool]);
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

    function stakeGoose2Pool( Pool _pool, uint16[] calldata tokenIds ) external whenNotPaused{
        require ( lastOpenBlockNumber != 0, "GooseGame Season is not open yet." );
        for( uint8 i = 0; i < tokenIds.length; i++ ){
            // todo: needs check the return to assure security.
            (bool success, bytes memory data) = __goose.delegatecall(
            abi.encodeWithSignature("transferFrom(address, address, uint256)", _msgSender(), address(this), tokenIds[i]));
            
            //goose.transferFrom( _msgSender(), address(this), tokenIds[i] );

            gooseStake[tokenIds[i]] = StakeGoose({
                pool: _pool,
                tokenId: tokenIds[i],
                owner: _msgSender(),
                blockNumber: uint32(block.number),
                unclaimedBalance: 0
            });
            poolGoose[_pool].add(tokenIds[i]);
        }
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
        lastOpenBlockNumber = block.number;

        
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
        lastCloseBlockNumber = block.number;

        uint32 curSeasonSeq = getCurrentSeasonID();
        console.log("curSeasonSeq: ", curSeasonSeq);
        seasonHistory[curSeasonSeq].blockNumber = uint32(block.number);

        for ( uint8 i = uint8(Pool.Barn); i <= uint8(Pool.Pond9); i++ ){
            poolRealNumber[Pool(i)] = 0;
            poolVotedNumber[Pool(i)] = 0;
        }
        for ( uint8 i = uint8(Pool.Barn); i <= uint8(Pool.Pond9); i++ ){
            // todo: poolRealNumber need to be reset in each round.

            for ( uint j = 0; j < poolGoose[Pool(i)].length(); j++ ){
                uint16 tokenID = uint16(poolGoose[Pool(i)].at(j));
                uint32 _seasonSeq = getSeasonID(gooseStake[tokenID].blockNumber);
                if( _seasonSeq < curSeasonSeq ){
                    // _seasonSeq is before the curSeasonSeq, indicates this Goose is not switched during this season. it should be counted in the Barn. 
                    poolRealNumber[Pool.Barn] += 1; // this info seems useless, todo: may neeed to be omitted.
                    seasonHistory[curSeasonSeq].totalGooseStakeDurationPerPond[uint(Pool.Barn)] += SEASON_DURATION;
                }else{
                    poolRealNumber[Pool(i)] += 1;
                    seasonHistory[curSeasonSeq].totalGooseStakeDurationPerPond[i] += (uint32(block.number) - gooseStake[tokenID].blockNumber);
                }
            }

            for( uint j = 0; j < poolCroco[Pool(i)].length(); j++ ) {
                uint16 tokenID = uint16(poolCroco[Pool(i)].at(j));
                uint32 _seasonSeq = getSeasonID(crocoStake[tokenID].blockNumber);
                if( _seasonSeq < curSeasonSeq ){
                    poolVotedNumber[Pool.Barn] += 1;
                }else{
                    poolVotedNumber[Pool(i)] += 1;
                    seasonHistory[curSeasonSeq].totalCrocoVoteDuratoin += (uint32(block.number) - crocoStake[tokenID].blockNumber);
                }
            }
        }

        Pool first = Pool.Pond1;
        Pool second = Pool.Pond2;
        Pool third = Pool.Pond3;
        Pool crocoWinner = Pool.Pond1;
        for ( uint8 i = uint8(Pool.Pond1); i <= uint8(Pool.Pond9); i++ ){
            if ( poolRealNumber[Pool(i)] < poolRealNumber[first]  ){
                first = Pool(i);
            }
        }
        for ( uint8 i = uint8(Pool.Pond1); i <= uint8(Pool.Pond9); i++ ){
            if( Pool(i) == first ) continue;
            if ( poolRealNumber[Pool(i)] < poolRealNumber[second] ){
                second = Pool(i);
            }else if( second == first ){
                second = Pool(i);
            }
        }
        for ( uint8 i = uint8(Pool.Pond1); i <= uint8(Pool.Pond9); i++ ){
            if( Pool(i) == second || Pool(i) == first ) continue;
            if ( poolRealNumber[Pool(i)] < poolRealNumber[third] ){
                third = Pool(i);
            }else if( third == second || third == first ){
                third = Pool(i);
            }
        }
        for ( uint8 i = uint8(Pool.Pond1); i <= uint8(Pool.Pond9); i++ ){
            if ( poolVotedNumber[Pool(i)] > poolVotedNumber[third] ){
                crocoWinner = Pool(i);
            }
        }

        uint16 winners = 0;
        winners |= uint16(first);
        winners <<= 4;
        winners |= uint16(second);
        winners <<= 4;
        winners |= uint16(third);
        console.log("first:", uint16(first));
        console.log("second:", uint16(second));
        console.log("third:", uint16(third));
        seasonHistory[curSeasonSeq].pondWinners = winners;
        seasonHistory[curSeasonSeq].crocoVotedWiner = uint8(crocoWinner);

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
                        // pond_rewards = GEGG_DAILY_LIMIT * 7 / 10 * 1 / 7;
                        pond_rewards = GEGG_DAILY_LIMIT * 3 / 10 / 7;   // todo: need to float type
                        
                    }else {
                        // pond_rewards = GEGG_DAILY_LIMIT * 0.7 * ( 1 / 2 - i / 6);
                        pond_rewards = GEGG_DAILY_LIMIT * 7 / 10 * 4 / 6 -  GEGG_DAILY_LIMIT * 7 / 10 * rank / 6;
                    }

                    if ( pool == Pool(seasonHistory[j].crocoVotedWiner) ){
                        //pond_rewards = 0;
                    }

                    uint32 iDuration = seasonHistory[j].blockNumber - gooseStake[tokenIds[i]].blockNumber;
                    totalDuration += iDuration;
                    console.log("pool No.     = ", uint(pool));
                    console.log("pool rank    = ", rank);
                    console.log("pond_rewards = ", pond_rewards);
                    console.log("iDuration    = ", iDuration);
                    if( iDuration > SEASON_DURATION + SEASON_REST ){
                        // this Goose is not moved in this Season, so it's reward share the Barn's.
                        gooseStake[tokenIds[i]].unclaimedBalance += pond_rewards * SEASON_DURATION / seasonHistory[j].totalGooseStakeDurationPerPond[uint(Pool.Barn)];
                    }else{
                        // this Goose is stake/switch to this Pond, it can share rwards from this Pond.
                        // todo: 这里出现过 panic : divided by zero
                        gooseStake[tokenIds[i]].unclaimedBalance += pond_rewards * iDuration / seasonHistory[j].totalGooseStakeDurationPerPond[uint(pool)];
                    }
                    //seasonHistory[j].totalGooseStakeDurationPerPond[uint(pool)];
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