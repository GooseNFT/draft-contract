// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./Pausable.sol";
import "./ERC721Enumerable.sol";
import "./ICrocoDao.sol";
import "./IGoldenEggGame.sol";
import "./Traits.sol";
import "./GEGG.sol";


// Noice: this contract is not finised.

contract CrocoDao is ICrocoDao, Traits, ERC721Enumerable, Pausable {
    // mint price
    uint256 public constant MINT_PRICE = .15 ether;
    // max number of tokens that can be minted - 50000 in production
    uint256 public immutable MAX_TOKENS;
    // number of tokens that can be claimed for free - 20% of MAX_TOKENS


    uint8   public constant AMOUNT_PER_ACCOUNT = 3;
    uint16  public minted;


    // mapping from tokenId to a struct containing the token's traits
    mapping(uint256 => CrocoTraits ) public tokenTraits;

    // mapping from hashed(tokenTrait) to the tokenId it's associated with
    // used to ensure there are no duplicates
    mapping(uint256 => uint256) public existingCombinations;

      // reference to the GoldenEggGame for choosing random Wolf thieves
    IGoldenEggGame public goldenegggame;

    // reference to $GEGG for burning on mint
    GEGG public gegg;


    constructor(address _gegg, uint256 _maxTokens) ERC721("GooseEgg Game", "GGAME") { 
        gegg = GEGG(_gegg);
        MAX_TOKENS = _maxTokens;
    }

    function mint( uint8 amount ) external payable whenNotPaused{
        require( tx.origin == _msgSender(), "Only EOA Allowed");
        require( minted + amount <= MAX_TOKENS, "All tokens minted");
        require(amount > 0 && amount <= AMOUNT_PER_ACCOUNT, "Invalid mint amount");
        require(amount * MINT_PRICE == msg.value, "Invalid payment amount");

        uint256 seed;
        for( uint8 i = 0; i < amount; i++ ){
            minted++;
            seed = random(minted);
            generate(minted, seed);
            _safeMint( _msgSender(), minted);
        }

    }



      /**
   * generates a pseudorandom number
   * @param seed a value ensure different outcomes for different sources in the same block
   * @return a pseudorandom value
   */
    function random(uint256 seed) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
        tx.origin,
        blockhash(block.number - 5),
        block.timestamp,
        seed
        )));
    }

    /**
    * generates traits for a specific token, checking to make sure it's unique
    * @param tokenId the id of the token to generate traits for
    * @param seed a pseudorandom 256 bit number to derive traits from
    * @return c - a struct of traits for the given token ID
    */
    function generate(uint256 tokenId, uint256 seed) internal returns (CrocoTraits memory c) {
        c = selectTraits(seed);
        if (existingCombinations[structToHash(c)] == 0) {
            tokenTraits[tokenId] = c;
            existingCombinations[structToHash(c)] = tokenId;
            return c;
        }
        return generate(tokenId, random(seed));
    }

    /**
    * selects the species and all of its traits based on the seed value
    * @param seed a pseudorandom 256 bit number to derive traits from
    * @return t -  a struct of randomly selected traits
    */
    function selectTraits(uint256 seed) internal view returns (CrocoTraits memory t) {    
        seed >>= 16;
        t.body = selectTrait(uint16(seed & 0xFFFF), 0 );
        seed >>= 16;
        t.eye = selectTrait(uint16(seed & 0xFFFF), 1 );
        seed >>= 16;
        t.legs = selectTrait(uint16(seed & 0xFFFF), 3 );
        seed >>= 16;
        t.mouth = selectTrait(uint16(seed & 0xFFFF), 4 );
        return t;
    }

    /**
    * @param seed portion of the 256 bit seed to remove trait correlation
    * @param traitType the trait type to select a trait for 
    * @return the ID of the randomly selected trait
    */
    function selectTrait(uint16 seed, uint8 traitType) internal view returns (uint8) {
        return (uint8(seed) % traitType_length[traitType] );
    }

    /**
    * converts a struct to a 256 bit hash to check for uniqueness
    * @param s the struct to pack into a hash
    * @return the 256 bit hash of the struct
    */
    function structToHash(CrocoTraits memory s) internal pure returns (uint256) {
        return uint256(bytes32(
        abi.encodePacked(
            s.body,
            s.eye,
            s.legs,
            s.mouth
        )
        ));
    }

        function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external pure  returns (bytes4) {
        require(from == address(0x0), "Cannot send tokens to GoldenEggGame directly");
        return IERC721Receiver.onERC721Received.selector;
    }

    function stakeCroco2Game(IGoldenEggGame.Location _at_location, uint16[] calldata crocoIds)
        external
        whenNotPaused
    {
        goldenegggame.crocoEnterGame(_msgSender(), _at_location, crocoIds);
        for (uint8 i = 0; i < crocoIds.length; i++) {
            // todo: needs check the return to assure security.
            transferFrom(_msgSender(), address(goldenegggame), crocoIds[i]);
        }
    }    

}
