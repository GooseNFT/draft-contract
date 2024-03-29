// Goose.js

// We import Chai to use its asserting functions here.
const { expect } = require("chai");
const { ethers }  = require("hardhat");
const { waitForDebugger } = require("inspector");

const { BigNumber, BigNumberish } = require( "@ethersproject/bignumber");

function sleep(ms) {
    return new Promise((resolve) => {
        setTimeout(resolve, ms);
    });
}

describe( "GooseNFT Contracts Test", function(){
    let Traits;
    let traits;
    let Goose;
    let goose;
    let CrocoDao;
    let croco;
    let GEgg;
    let egg;
    let GoldenEggGame;
    let goldenegggame;
    let owner;
    let user1;
    let user2;
    let users;
    let owner_address;
    let nUsers
  

    this.beforeEach( async function(){
        this.timeout(100000);
        //Traits = await ethers.getContractFactory("Traits");
        Goose    = await ethers.getContractFactory("Goose");
        CrocoDao = await ethers.getContractFactory("CrocoDao");
        GEgg     = await ethers.getContractFactory("GEGG");
        GoldenEggGame     = await ethers.getContractFactory("GoldenEggGame");
        [owner, user1, user2, ...users] = await ethers.getSigners();
        owner_address = await owner.getAddress();
        nUsers  = users.length;
        //traits = await Traits.deploy();

        egg   = await GEgg.deploy();
        //const r = await (await egg.owner()).wait();

        croco = await CrocoDao.deploy(egg.address, 888);
        goose = await Goose.deploy(egg.address, 50000);
        await goose.deployed();


        goldenegggame  = await GoldenEggGame.deploy(egg.address, croco.address, goose.address, 115, 20);
        await goldenegggame.deployed();
        await goose.setBarn(goldenegggame.address);
        
        //eggaddress = await egg.address;

   
        


        //console.log("run once of beforeEach");

        var fs = require('fs');

        traits_dir = "resources/traits-png/";

        body_traits = new Map();

        files = fs.readdirSync(traits_dir);
        files.forEach( (file, index) => {
            if (file.includes('_') ){
                    splits = file.split('_')
                    //body_traits.set(splits[0], splits[1])
                    if( body_traits.has(splits[0]) ){
                            body_traits.get(splits[0]).push(splits[1])
                    }else{
                            body_traits.set(splits[0], [ splits[1] ])
                    }
            }

        });
        //console.log(body_traits)
        //const json = Object.fromEntries(body_traits)
        //console.log(JSON.stringify(json, null, 4))

        const gas_price = 50;
        var upload_fee = 0;

        var traiTypes = Array.from(body_traits.keys());
        //console.log(traiTypes);
        await goose.setTraitTypes(traiTypes);

        var traiTypes = Array.from(body_traits.keys());
        //traiTypes.forEach( (v, i) => {
        for ( var i = 0; i < traiTypes.length; i++ ){
            var v = traiTypes[i];
        
            var trait_arr = [];
            var len = body_traits.get(v).length;
            traitIndex_arr = [...Array(len).keys()];
            traitIndex_arr.forEach( j => {
                var trait_path = traits_dir + v + "_" + body_traits.get(v)[j];
                var data;
                try {
                    data = fs.readFileSync(trait_path)
                    //console.log(data)
                } catch (err) {
                    console.error(err)
                }
                var Trait = { name: body_traits.get(v)[j].split('.')[0], png: data.toString('base64') };
                trait_arr.push(Trait)
            });
            //console.log("TraitType is " + v + "(Index:" + i);
            //console.log(trait_arr);
            const r = await (await goose.uploadTraits(i, traitIndex_arr, trait_arr)).wait();
            upload_fee += r.gasUsed * gas_price;
        }

        //console.log("gas cost: ", ethers.utils.formatUnits(upload_fee, "gwei"))

    });



    describe( "Deployment", function(){
        it("Should set the right owner", async function(){
            expect(await goose.owner()).to.equal(owner.address);
            //console.log("owner address: ", owner_address)
        });


        it( "case 1: setTraitTypes", async function(){
            
            var r = await goose.traitTypes(0);
            //console.log(r)
            expect(r).to.equal("Body");
        })

        it( "Case 2: uploadTraits ", async function(){
            await goose.gettraitType_length();

            //await goose.uploadTraits(1, [0,1], arr_trait);
            var r = await goose.traitData(1,0);
            //console.log();
            expect(r['name']).to.equal("Annoy");
            expect(r['png']).to.equal("iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAYAAABV7bNHAAAAAXNSR0IArs4c6QAAAFJJREFUeJzt0TEKwDAIAEDN///cLh0khNLBNhTuwEEFQY0AAAAAYJPjiprf9Vtk98CX1QPkot6+z+ge+JH5EH97NAAAAAAAAAAAAAAAAAAAwEMnZDQHAdOjEJMAAAAASUVORK5CYII=")
        });
    });


/*
    describe( "Gas Consumption", function(){

        it( "Case 1: testGas ", async function (){
            await goldenegggame.testGas_init();
            var r = await goldenegggame.gooseRecordIndex(0);
            //console.log(r)
            await goldenegggame.testGas_mod();

            r = await goldenegggame.gooseRecordIndex(0);

            //console.log(r)

            //expect())
        });
    });
 */   

    describe( "Season Related Operations", function(){

        it( "Case 1: blockNumber manipulate", async function (){
            var r = await goldenegggame.printBlockNumber();
            //console.log(r)
        })

        it( "Case 2: seasonCloseTrigger need SeasonOpen first", async function(){
            await expect(goldenegggame.seasonCloseTrigger()).to.be.revertedWith("Error: VM Exception while processing transaction: reverted with reason string 'Season has already Closed'");
            
        })
        
        it( "Case 3: Continuous season operations with empty players", async function(){
            goldenegggame = await GoldenEggGame.deploy(egg.address, croco.address, goose.address, 6, 5)
            await goldenegggame.seasonOpen();
            await sleep(4000);
            await expect(goldenegggame.seasonCloseTrigger()).to.be.revertedWith("Error: VM Exception while processing transaction: reverted with reason string 'Season close time hasn't arrived'");
            await sleep(3000);
            await goldenegggame.seasonCloseTrigger();
            await expect(goldenegggame.seasonCloseTrigger()).to.be.revertedWith("Error: VM Exception while processing transaction: reverted with reason string 'Season has already Closed'");
            const r = await goldenegggame.seasonRecordIndex(0);
            const r2 = await goldenegggame.getRank(2, r['topPondsOfSession']);
            const r3 = await goldenegggame.getRank(9, r['topPondsOfSession']);
//             console.log(r);
//             console.log(r2)
//             console.log(r3)
            // 291 means Pond 1, 2, 3 ranks as No.1, No.2 No.3.
            expect(r['topPondsOfSession']).to.be.equal(291);
            expect(r2).to.be.equal(2);
            expect(r3).to.be.equal(0);
            await expect(goldenegggame.seasonOpen()).to.be.revertedWith("Error: VM Exception while processing transaction: reverted with reason string 'Season is resting'");
            await sleep(5000);
            await goldenegggame.seasonOpen();
            await expect(goldenegggame.seasonCloseTrigger()).to.be.revertedWith("Error: VM Exception while processing transaction: reverted with reason string 'Season close time hasn't arrived'");
            //expect(goldenegggame.seasonRecordIndex(0))
            //
            
        })

    });



    describe( "Geting deploy gas used estimate.",  function(){
        it( "Cas 1: show gas used of deploying contracts", async function(){

            const gas_price = 50;

            Goose    = await ethers.getContractFactory("Goose");
            CrocoDao = await ethers.getContractFactory("CrocoDao");
            GEgg     = await ethers.getContractFactory("GEGG");
            GoldenEggGame     = await ethers.getContractFactory("GoldenEggGame");
    

            egg   = await GEgg.deploy();
            //const r = await (await egg.owner()).wait();
    
            croco = await CrocoDao.deploy(egg.address, 888);
    
    
            goose = await Goose.deploy(egg.address, 50000);   

            goldenegggame  = await GoldenEggGame.deploy(egg.address, croco.address, goose.address, 100,10);
    
    
            const egg_r = await egg.deployTransaction.wait();
            const goldenegggame_r = await goldenegggame.deployTransaction.wait();
            const goose_r = await goose.deployTransaction.wait();
    
            console.log("Contract Deployment Gas info: ", 
            ethers.utils.formatUnits(egg_r.gasUsed * gas_price, "gwei"), 
            ethers.utils.formatUnits(goldenegggame_r.gasUsed * gas_price, "gwei"), 
            ethers.utils.formatUnits(goose_r.gasUsed * gas_price, "gwei"));
            //expect(1).to.be.equal(1);
        });

    });


    describe( "Minting Related", function(){
        it( "Case 1: Goose Mint", async function(){
            await goose.gettraitType_length();
            await goose.gettraitType_length_base();
            const opt_overides = {value: ethers.utils.parseEther("0.08")}
            //console.log(ethers.utils.parseEther("0.08"));
            const balance_before = await user1.getBalance();
            const account_balance_before = await ethers.provider.getBalance(goose.address);
            //console.log("balance_before: ", balance_before);
            const r1 = await (await  goose.connect(user1).mint(1, opt_overides)).wait();
            await  goose.connect(user2).mint(3, {value: ethers.utils.parseEther("0.24")  })
            const r2 = await (await  goose.connect(user1).mint(1, opt_overides)).wait();
            //console.log( r1,r2)

            // Get notified when a transaction is mined
 
            //ethers.providers.Provider.



            const balance_after  = await user1.getBalance();
            const account_balance_after = await ethers.provider.getBalance(goose.address);
            //console.log("balance_after: ", balance_after);
            
            // NOTICE: the diff bellow is not always equals to 0, use diff2 instead.
            let diff = balance_before - BigNumber.from(r1.gasUsed * r1.effectiveGasPrice) - BigNumber.from(r2.gasUsed * r2.effectiveGasPrice) - ethers.utils.parseEther("0.16") - balance_after;
            
            //console.log(diff);
            //console.log(balance_before, "-", BigNumber.from(r1.gasUsed * r1.effectiveGasPrice),  "-", BigNumber.from(r2.gasUsed * r2.effectiveGasPrice), "-", ethers.utils.parseEther("0.16"), "-", balance_after);

            let diff2 = balance_before.sub(r1.gasUsed * r1.effectiveGasPrice).sub(r2.gasUsed * r2.effectiveGasPrice).sub(ethers.utils.parseEther("0.16")).sub(balance_after);
            //console.log("diff2 = ", diff2);
            expect(diff2.toNumber()).to.be.equal(0);

            const r3 = await goose.balanceOf(user1.address);
            expect(r3).to.be.equal(2);
            //const r2 = await goose.getApproved(user1.address);
            const r4 = await goose.tokenOfOwnerByIndex(user1.address,1);
            expect(r4).to.be.equal(5);
            const token1 = await goose.tokenURI(r4);
            const token2 = await goose.tokenURI(await goose.tokenOfOwnerByIndex(user1.address,0))
            var fs = require('fs');
            for( var i = 0; i < 5; i++ ){
                fs.writeFileSync('./output/'+i+".svg", await goose.drawSVG(i));
            }
            //console.log(token1)
            //console.log(token2)
            //console.log(ethers.provider);
            expect(account_balance_before).to.be.equal(ethers.utils.parseEther("0"));
            expect(account_balance_after).to.be.equal(ethers.utils.parseEther("0.4"));

            await expect(goose.connect(user1).withdraw()).to.be.revertedWith("Ownable: caller is not the owner");
            owner_balance_before = await owner.getBalance();
            const r6 = await (await goose.withdraw()).wait();

            owner_balance_after  = await owner.getBalance();
            let diff3 = owner_balance_after.sub(owner_balance_before).add(r6.gasUsed * r6.effectiveGasPrice)
            expect(diff3).to.be.equal(ethers.utils.parseEther("0.4"));
            //console.log(r5);
            //console.log(r2);
            //console.log(r3);
        });
    });


     /*
    describe( "Staking Games", function(){
        it( "Case 1: Goose Stake", async function(){
            this.timeout(100000);

            const opt_overides = {value: ethers.utils.parseEther("0.08")};
            //nUsers  = 1;
            for ( var i = 0; i < nUsers; i++ ){
                var r1 = await (await  goose.connect(users[i]).mint(1, opt_overides)).wait();
            }
            var fs = require('fs');
            console.log("User Amount:", users.length);

            for( var i = 0; i < nUsers; i++ ){
                //fs.writeFileSync('./output/staking-'+i+".svg", await goose.drawSVG(i));
            }

            await expect(goose.tokenOfOwnerByIndex(user1.address,0)).to.be.revertedWith("ERC721Enumerable: owner index out of bounds");


            var randomInt = 0;
            const start = Date.now();
            console.log("seasonOpen at          : ", Date.now() - start)
            await goldenegggame.seasonOpen();
            console.log(nUsers, "users gooseEnterGame at  : ", Date.now() - start)
            for( var i = 0; i < nUsers; i++ ){
                randomInt = Math.floor(Math.random() * (Number.MAX_SAFE_INTEGER - 101 ) );
                var myTokenId = await goose.tokenOfOwnerByIndex(users[i].address,0)
                await goose.connect(users[i]).gooseEnterGame( randomInt % 10, [myTokenId] );
            }
            const opt_overides2 = {gasLimit: 1562664};
            console.log("seasonCloseTrigger at          : ", Date.now() - start)
            await goldenegggame.seasonCloseTrigger(opt_overides2);
            const s0 = await goldenegggame.seasonRecordIndex(0);
            const s1 = await goldenegggame.seasonRecordIndex(1);
            console.log("---------goldenegggame.seasonRecordIndex--------")
            console.log(s0,s1);

            await expect(goose.tokenOfOwnerByIndex(users[0].address,0)).to.be.revertedWith("ERC721Enumerable: owner index out of bounds");

            var goldenegggameToken = await goose.tokenOfOwnerByIndex(goldenegggame.address,0);
            var balanceOf = await goose.balanceOf(goldenegggame.address);
            console.log("goldenegggameToken: ", goldenegggameToken, "    balanceOf: ", balanceOf);
            expect(balanceOf.toNumber()).to.be.equal(nUsers)

            var ranks = new Array(3);
            for( var i = 0; i < 10; i++ ){
                const count = await goldenegggame.getNumberOfGooseInLocation(i);
                const rank = await goldenegggame.getRank(i, s1['pondWinners']);
                if (rank != 0 ){
                    ranks[rank-1] = i;
                }
                console.log("Pool #", i, " = ", count);
            }
            console.log("ranks: ", ranks);
            var checkNumber;
            ranks.forEach((v,i)=>{
                checkNumber |= v;
                if ( i < 2 ){
                    checkNumber <<= 4;
                }
            })
            expect(checkNumber).to.be.equal(s1['pondWinners']);
            console.log("genesisSeasonBlockHeight = ", await goldenegggame.genesisSeasonBlockHeight());
            const poolDrations = await goldenegggame.getCombineGooseLaidEggDurationPerLocationOfSeason(1);
            console.log("getCombineGooseLaidEggDurationPerLocationOfSeason:", poolDrations);
            var poolDrationsum = 0;
            poolDrations.forEach(v=>poolDrationsum+=v);
            console.log("getCombineGooseLaidEggDurationPerLocationOfSeason Sum:", poolDrationsum);
            var rewardSum = BigNumber.from(0);
            var durationSum = BigNumber.from(0);
            console.log(nUsers, "users gooseClaimToBalance at  : ", Date.now() - start)
            for( var i = 0; i < nUsers; i++ ){
                var myTokenId = await goldenegggame.getGooseIdsFromOwnerAddressAndIndex(users[i].address,0);
                const res = await goldenegggame.connect(users[i]).gooseClaimToBalance([myTokenId]);
                //console.log("res:   ",res)
                //durationSum = durationSum.add(res);
                const r = await goldenegggame.gooseRecordIndex(myTokenId);
                //console.log(r);
                rewardSum = rewardSum.add(r['unclaimedGEGGBalance']);
                console.log("Token #", myTokenId.toString(), " claimed:", r['unclaimedGEGGBalance'].toString());
            }
            console.log("Done at                     : ", Date.now() - start)
            console.log("rewardsSum  = ", rewardSum);
            expect(rewardSum.toString().slice(0,-2)).to.be.equal("9".repeat(22));
            //console.log("durationSum = ", durationSum)

        });
    });
*/

    async function calculateRewards(){
        var rewardSum = BigNumber.from(0);
        for( var i = 0; i < nUsers; i++ ){
            var myTokenId = await goldenegggame.getGooseIdsFromOwnerAddressAndIndex(users[i].address,0);
            await( await goldenegggame.connect(users[i]).gooseClaimToBalance([myTokenId])).wait();
            //const r = await goldenegggame.gooseRecordIndex(myTokenId);
            //console.log(r);
            const r = await egg.balanceOf(users[i].address);
            //console.log("balanceOf = ", r);
            rewardSum = rewardSum.add(r);
            console.log("Token #", myTokenId.toString(), " claimed:", r.toString());
        }
        console.log("rewardsSum  = ", rewardSum);
        //const reward = Math.floor(rewardSum.toNumber() / 100);
        return Promise.resolve(rewardSum.toNumber());
    }

    describe( "Staking Games Ver. 2", function(){
        it(" Case 1: Stake 97 users' Goose NFT and check rewards", async function() {
            const SEASON_DURATION = await goldenegggame.seasonDuration();
            const SEASON_REST     = await goldenegggame.restDuration();
            console.log("SEASON_DURATION: ", SEASON_DURATION, " SEASON_REST", SEASON_REST);
            var genisisBlock = 0;
            this.timeout(1000000);
            var close_flag;
            var closed = false;
            var afterStakeBlock = Number.MAX_SAFE_INTEGER;

            var checkRewards = 0;

            egg.addController(goldenegggame.address);

            ethers.provider.on("block", blockNumber =>{
                if( blockNumber > afterStakeBlock && genisisBlock != 0 && !closed ){
                    if ( blockNumber - genisisBlock > SEASON_DURATION ){
                        console.log("kick, off event block");
                        closed = true;
                        ethers.provider.off("block");
                        goldenegggame.seasonCloseTrigger().then(tx=>{
                            console.log("seasonCloseTrigger summited at block: ", tx.blockNumber);
                            return tx.wait();
                        }).then( receipt => {
                            console.log("get receipt: ", receipt.blockNumber);
                            console.log("tx status: ", receipt.status);
                            calculateRewards().then(a=>checkRewards=a);
                        });
                        
                    }
                }
            });

            const opt_overides = {value: ethers.utils.parseEther("0.08")};
            

            for ( var i = 0; i < nUsers; i++ ){
                var r1 = await (await  (goose.connect(users[i]).mint(1, opt_overides) ) ).wait();
            }
            var fs = require('fs');
            console.log("User Amount:", users.length);
            
            await (await goldenegggame.seasonOpen()).wait();
            genisisBlock = await goldenegggame.genesisSeasonBlockHeight();
            console.log(nUsers, "goldenegggame.seasonOpen at : ", genisisBlock)
            var randomInt = 0;
            for( var i = 0; i < nUsers; i++ ){
                randomInt = Math.floor(Math.random() * (Number.MAX_SAFE_INTEGER - 101 ) );
                var myTokenId = await goose.tokenOfOwnerByIndex(users[i].address,0)
                //if( i != 10 ) randomInt = 0;
                console.log("goldenegggame.address=",goldenegggame.address);
                console.log("user address=", users[i].address);
                await goose.connect(users[i]).approveBarn([myTokenId]);

                await goldenegggame.connect(users[i]).gooseEnterGame( randomInt % 10, [myTokenId] );
            }

            afterStakeBlock = await ethers.provider.getBlockNumber();
            console.log(nUsers, " users have finished staking at ", afterStakeBlock);
            
            while ( checkRewards == 0 ){
                console.log("wait ...")
                await sleep(1000);
            }
            const s0 = await goldenegggame.seasonRecordIndex(0);
            var ranks = new Array(3);
            for( var i = 0; i < 10; i++ ){
                const count = await goldenegggame.getNumberOfGooseInLocation(i);
                const rank = await goldenegggame.getRank(i, s0['topPondsOfSession']);
                if (rank != 0 ){
                    ranks[rank-1] = i;
                }
                console.log("Pool #", i, " = ", count);
            }
            console.log("ranks: ", ranks);
            var checkTopNumber;
            ranks.forEach((v,i)=>{
                checkTopNumber |= v;
                if ( i < 2 ){
                    checkTopNumber <<= 4;
                }
            })
            var total = await egg.totalSupply();
            console.log("gegg minted supply: ", total);
            
            expect(checkRewards).to.be.equal(total);

            expect(checkTopNumber).to.be.equal(s0['topPondsOfSession']);
            
            // will fail if there is at least one empty Pond.
            expect( Math.floor(checkRewards/ 100) ).to.be.equal(9999); 

        });
        
    });


} );
