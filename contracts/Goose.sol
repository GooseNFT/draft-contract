// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./Pausable.sol";
import "./ERC721Enumerable.sol";
import "./IGoose.sol";
import "./IBarn.sol";
import "./Traits.sol";
import "./GEGG.sol";


contract Goose is IGoose, Traits, ERC721Enumerable, Pausable {
    // mint price
    uint256 public constant MINT_PRICE = .08 ether;
    // max number of tokens that can be minted - 50000 in production
    uint256 public immutable MAX_TOKENS;
    // number of tokens that can be claimed for free - 20% of MAX_TOKENS
    uint256 public PAID_TOKENS;
    // number of tokens have been minted so far

    uint8   public constant AMOUNT_PER_ACCOUNT = 5;
    uint16  public minted;


    // mapping from tokenId to a struct containing the token's traits
    mapping(uint256 => Goose) public tokenTraits;

    // mapping from hashed(tokenTrait) to the tokenId it's associated with
    // used to ensure there are no duplicates
    mapping(uint256 => uint256) public existingCombinations;

      // reference to the Barn for choosing random Wolf thieves
    IBarn public barn;

    // reference to $GEGG for burning on mint
    GEGG public egg;


    constructor(address _gegg, address _barn, uint256 _maxTokens) ERC721("GooseEgg Game", "GGAME") { 
        egg = GEGG(_gegg);
        MAX_TOKENS = _maxTokens;
        PAID_TOKENS = MAX_TOKENS / 5;
    }

    function mint( uint8 amount ) external payable whenNotPaused{
        require( tx.origin == _msgSender(), "Only EOA Allowed");
        require( minted + amount <= MAX_TOKENS, "All tokens minted");
        require(amount > 0 && amount <= AMOUNT_PER_ACCOUNT, "Invalid mint amount");
        if (minted < PAID_TOKENS) {
            require(minted + amount <= PAID_TOKENS, "All tokens on-sale already sold");
            require(amount * MINT_PRICE == msg.value, "Invalid payment amount");
        } else {
            require(msg.value == 0);
        }
        uint256 totalEggCost = 0;
        uint256 seed;
        for( uint8 i = 0; i < amount; i++ ){
            minted++;
            seed = random(minted);
            generate(minted, seed);
            _safeMint( _msgSender(), minted);
            totalEggCost += mintCost(minted);
        }
        if( totalEggCost > 0 ) {
            egg.burn(_msgSender(), totalEggCost);
        }
    }


    /** 
    * the first 20% are paid in ETH
    * the next 20% are 20000 $WOOL
    * the next 40% are 40000 $WOOL
    * the final 20% are 80000 $WOOL
    * @param tokenId the ID to check the cost of to mint
    * @return the cost of the given token ID
    */
    function mintCost(uint256 tokenId) public view returns (uint256) {
        if (tokenId <= PAID_TOKENS) return 0;
        if (tokenId <= MAX_TOKENS * 2 / 5) return 20000 ether;
        if (tokenId <= MAX_TOKENS * 4 / 5) return 40000 ether;
        return 80000 ether;
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
    * @return g - a struct of traits for the given token ID
    */
    function generate(uint256 tokenId, uint256 seed) internal returns (Goose memory g) {
        g = selectTraits(seed);
        if (existingCombinations[structToHash(g)] == 0) {
            tokenTraits[tokenId] = g;
            existingCombinations[structToHash(g)] = tokenId;
            return g;
        }
        return generate(tokenId, random(seed));
    }

    /**
    * selects the species and all of its traits based on the seed value
    * @param seed a pseudorandom 256 bit number to derive traits from
    * @return t -  a struct of randomly selected traits
    */
    function selectTraits(uint256 seed) internal view returns (Goose memory t) {    
        seed >>= 16;
        t.body = selectTrait(uint16(seed & 0xFFFF), 0 );
        seed >>= 16;
        t.eye = selectTrait(uint16(seed & 0xFFFF), 1 );
        seed >>= 16;
        t.hat = selectTrait(uint16(seed & 0xFFFF), 2 );
        seed >>= 16;
        t.legs = selectTrait(uint16(seed & 0xFFFF), 3 );
        seed >>= 16;
        t.mouth = selectTrait(uint16(seed & 0xFFFF), 4 );
        seed >>= 16;
        t.mouthAcc = selectTrait(uint16(seed & 0xFFFF), 5 );
        seed >>= 16;
        t.neck = selectTrait(uint16(seed & 0xFFFF), 6 );
        return t;
    }

    /**
    * @param seed portion of the 256 bit seed to remove trait correlation
    * @param traitType the trait type to select a trait for 
    * @return the ID of the randomly selected trait
    */
    function selectTrait(uint16 seed, uint8 traitType) internal view returns (uint8) {
        console.log("traitType:", traitType, "  length: ", traitType_length[traitType]);
        return uint8((seed % uint16(traitType_length[traitType]) ));
    }

    function gettraitType_length() public view {
        for ( uint i =0; i < 7; i++ ){
            console.log("traitType_length(", i, ") = ", traitType_length[uint8(i)]);
        }
    }

    /**
    * converts a struct to a 256 bit hash to check for uniqueness
    * @param s the struct to pack into a hash
    * @return the 256 bit hash of the struct
    */
    function structToHash(Goose memory s) internal pure returns (uint256) {
        return uint256(bytes32(
        abi.encodePacked(
            s.body,
            s.eye,
            s.hat,
            s.legs,
            s.mouth,
            s.mouthAcc,
            s.neck
        )
        ));
    }

    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external pure  returns (bytes4) {
        require(from == address(0x0), "Cannot send tokens to Barn directly");
        return IERC721Receiver.onERC721Received.selector;
    }

}
