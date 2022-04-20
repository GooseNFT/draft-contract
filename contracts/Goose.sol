// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./Pausable.sol";
import "./ERC721Enumerable.sol";
import "./IGoose.sol";
import "./Barn.sol";
import "./IBarn.sol";
import "./Traits.sol";
import "./GEGG.sol";


contract Goose is IBarn, IGoose, Traits, ERC721Enumerable, Pausable {
    // mint price
    uint256 public constant MINT_PRICE = .08 ether;
    // max number of Goose that can be minted - 50000 in production
    uint256 public immutable MAX_GOOSES;

    // number of Goose that can be bought with ETH - 20% of MAX_GOOSE
    uint256 public MAX_PAID_GOOSES;
    uint8   public constant AMOUNT_PER_ACCOUNT = 5;

    // number of Goose have been minted so far
    uint16  public mintedGoose;

    // mapping from gooseId to a struct containing the goose's traits
    mapping(uint256 => GooseTraits) public gooseIdToGooseTraits;

    // mapping from hashed(gooseTrait) to the gooseId it's associated with
    // used to ensure there are no duplicates
    mapping(uint256 => uint256) public existingCombinations;


    Barn public barn;

    // reference to $GEGG for burning on mint
    GEGG public egg;


    constructor(address _gegg, address _barn, uint256 _maxGooses) ERC721("Goose", "GOOSE") { 
        egg = GEGG(_gegg);
        barn = Barn(_barn);
        MAX_GOOSES = _maxGooses;
        MAX_PAID_GOOSES = MAX_GOOSES / 5;
    }

    function mint( uint8 amount ) external payable whenNotPaused{
        require( tx.origin == _msgSender(), "Only EOA Allowed");
        require( mintedGoose + amount <= MAX_GOOSES, "All gooses minted");
        require( amount > 0 && amount <= AMOUNT_PER_ACCOUNT, "Invalid mint amount");
        if (mintedGoose < MAX_PAID_GOOSES) {
            require(mintedGoose + amount <= MAX_PAID_GOOSES, "All gooses on-sale already sold");
            require(amount * MINT_PRICE == msg.value, "Invalid payment amount");
        } else {
            require(msg.value == 0);
        }
        uint256 totalEggCost = 0;
        uint256 seed;
        for ( uint8 i = 0; i < amount; i++ ){
            mintedGoose++;
            seed = random(mintedGoose);
            generate(mintedGoose, seed);
            _safeMint( _msgSender(), mintedGoose);
            totalEggCost += mintCost(mintedGoose);
        }
        if( totalEggCost > 0 ) {
            egg.burn(_msgSender(), totalEggCost);
        }
    }


    /** 
    * the first 20% are paid in ETH
    * the next 20% are 20000 $GEGG
    * the next 40% are 40000 $GEGG
    * the final 20% are 80000 $GEGG
    * @param gooseId the ID to check the cost of to mint
    * @return the cost of the given token ID
    */
    function mintCost(uint256 gooseId) public view returns (uint256) {
        if (gooseId <= MAX_PAID_GOOSES) return 0;
        if (gooseId <= MAX_GOOSES * 2 / 5) return 20000 ether; // GEGG
        if (gooseId <= MAX_GOOSES * 4 / 5) return 40000 ether; // GEGG
        return 80000 ether; // GEGG
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
    * @param gooseId the id of the Goose to generate traits for
    * @param seed a pseudorandom 256 bit number to derive traits from
    * @return g - a struct of traits for the given token ID
    */
    function generate(uint256 gooseId, uint256 seed) internal returns (GooseTraits memory g) {
        g = selectTraits(seed);
        if (existingCombinations[traitsStructToHash(g)] == 0) {
            gooseIdToGooseTraits[gooseId] = g;
            existingCombinations[traitsStructToHash(g)] = gooseId;
            return g;
        }
        return generate(gooseId, random(seed));
    }

    /**
    * selects the species and all of its traits based on the seed value
    * @param seed a pseudorandom 256 bit number to derive traits from
    * @return t -  a struct of randomly selected traits
    */
    function selectTraits(uint256 seed) internal view returns (GooseTraits memory t) {    
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
    * converts goose traits struct to a 256 bit hash to check for uniqueness
    * @param s the struct to pack into a hash
    * @return the 256 bit hash of the struct
    */
    function traitsStructToHash(GooseTraits memory s) internal pure returns (uint256) {
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
        require(from == address(0x0), "Cannot send Goose to Barn directly");
        return IERC721Receiver.onERC721Received.selector;
    }


    function getGooseTraits(uint256 gooseId) public view returns (GooseTraits memory) {
    return gooseIdToGooseTraits[gooseId];
  }

    function drawSVG(uint256 gooseId) public view returns (string memory) {
    GooseTraits memory s = getGooseTraits(gooseId);
    string memory svgString = string(abi.encodePacked(
      drawTrait(traitData[0][s.body]),
      drawTrait(traitData[1][s.eye]),
      drawTrait(traitData[2][s.hat]),
      drawTrait(traitData[3][s.legs]),
      drawTrait(traitData[4][s.mouth]),
      drawTrait(traitData[5][s.mouthAcc]),
      drawTrait(traitData[6][s.neck])
    ));

    return string(abi.encodePacked(
      '<svg id="Goose" width="100%" height="100%" version="1.1" viewBox="0 0 72 72" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">',
      svgString,
      "</svg>"
    ));
  }

    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
function tokenURI(uint256 tokenId) public view override returns (string memory) {
    require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");


    string memory metadata = string(abi.encodePacked(
      '{"name":  "Goose #"',toString(tokenId),',', 
      '"description": "Golden Egg World", "image": "data:image/svg+xml;base64,',
      base64(bytes(drawSVG(tokenId))),
      '", "attributes":',
      compileAttributes(tokenId),
      "}"
    ));

    return string(abi.encodePacked(
      "data:application/json;base64,",
      base64(bytes(metadata))
    ));
  }

    function attributeForTypeAndValue(string memory traitType, string memory value) internal pure returns (string memory) {
    return string(abi.encodePacked(
      '{"trait_type":"',
      traitType,
      '","value":"',
      value,
      '"}'
    ));
  }

  function getGeneration( uint gooseId ) internal view returns (uint){
        if (gooseId <= MAX_PAID_GOOSES) return 0;
        if (gooseId <= MAX_GOOSES * 2 / 5) return 1;
        if (gooseId <= MAX_GOOSES * 4 / 5) return 2;
        return 3;
  }

  /**
   * generates an array composed of all the individual traits and values
   * @param gooseID the ID of the token to compose the metadata for
   * @return a JSON array of all of the attributes for given token ID
   */
  function compileAttributes(uint256 gooseID) public view returns (string memory) {
    GooseTraits memory s = getGooseTraits(gooseID);
    string memory traits;
      traits = string(abi.encodePacked(
        attributeForTypeAndValue(traitTypes[0], traitData[0][s.body].name),',',
        attributeForTypeAndValue(traitTypes[1], traitData[1][s.eye].name),',',
        attributeForTypeAndValue(traitTypes[2], traitData[2][s.hat].name),',',
        attributeForTypeAndValue(traitTypes[3], traitData[3][s.legs].name),',',
        attributeForTypeAndValue(traitTypes[4], traitData[4][s.mouth].name),',',
        attributeForTypeAndValue(traitTypes[5], traitData[5][s.mouthAcc].name),',',
        attributeForTypeAndValue(traitTypes[6], traitData[7][s.neck].name),','
      ));

    return string(abi.encodePacked(
      '[',
      traits,
      '{"trait_type":"Generation","value":',
      getGeneration(gooseID),
      '}]'
    ));
  }

   /**
   * allows owner to withdraw funds from minting
   */
  function withdraw() external onlyOwner {
    payable(owner()).transfer(address(this).balance);
  }



  function stakeGoose2Pool( Pool _pool, uint16[] calldata tokenIds ) external whenNotPaused{
    barn.stakeGooseConfirm( _msgSender(), _pool, tokenIds);
    for( uint8 i = 0; i < tokenIds.length; i++ ){
        // todo: needs check the return to assure security.
        transferFrom( _msgSender(), address(barn), tokenIds[i] );
    }
  }

}
