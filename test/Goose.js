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
    let Barn;
    let barn;
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
        Barn     = await ethers.getContractFactory("Barn");
        [owner, user1, user2, ...users] = await ethers.getSigners();
        owner_address = await owner.getAddress();
        nUsers  = users.length;
        //traits = await Traits.deploy();

        egg   = await GEgg.deploy();
        //const r = await (await egg.owner()).wait();

        croco = await CrocoDao.deploy(egg.address, 888);


        barn  = await Barn.deploy(egg.address, croco.address, 115, 20);

        
        //eggaddress = await egg.address;
        goose = await Goose.deploy(egg.address,barn.address, 50000);

        //await goose.deployed();
        


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



    describe( "Gas Consumtion", function(){

        it( "Case 1: testGas ", async function (){
            await barn.testGas_init();
            var r = await barn.gooseStake(0);
            //console.log(r)
            await barn.testGas_mod();

            r = await barn.gooseStake(0);

            //console.log(r)

            //expect())
        });
    });
    describe( "Season Related Operations", function(){

        it( "Case 1: blockNumber manipulate", async function (){
            var r = await barn.printBlockNumber();
            //console.log(r)
        })

        it( "Case 2: seasonClose need SeasonOpen first", async function(){
            await expect(barn.seasonClose()).to.be.revertedWith("Error: VM Exception while processing transaction: reverted with reason string 'Season is already Closed'");
            
        })
        
        it( "Case 3: Continuous season operations with empty players", async function(){
            barn = await Barn.deploy(egg.address, croco.address, 6, 5)
            await barn.seasonOpen();
            await sleep(4000);
            await expect( barn.seasonClose()).to.be.revertedWith("Error: VM Exception while processing transaction: reverted with reason string 'Season close time isn't arrived'");
            await sleep(3000);
            await barn.seasonClose();
            await expect(barn.seasonClose()).to.be.revertedWith("Error: VM Exception while processing transaction: reverted with reason string 'Season is already Closed'");
            const r = await barn.seasonsHistory(0);
            //console.log(r);
            const r2 = await barn.getRank(2, r['topPonds']);
            const r3 = await barn.getRank(9, r['topPonds']);
            //console.log(r2)
            // 291 means Pond 1, 2, 3 ranks as No.1, No.2 No.3.
            expect(r['topPonds']).to.be.equal(291);
            expect(r2).to.be.equal(2);
            expect(r3).to.be.equal(0);
            await expect(barn.seasonOpen()).to.be.revertedWith("Error: VM Exception while processing transaction: reverted with reason string 'Season is resting'")
            await sleep(5000);
            await barn.seasonOpen();
            await expect( barn.seasonClose()).to.be.revertedWith("Error: VM Exception while processing transaction: reverted with reason string 'Season close time isn't arrived'");
            //expect(barn.seasonsHistory(0))
            //
            
        })

    });



    describe( "Geting deploy gas used estimate.",  function(){
        it( "Cas 1: show gas used of deploying contracts", async function(){

            const gas_price = 50;

            Goose    = await ethers.getContractFactory("Goose");
            CrocoDao = await ethers.getContractFactory("CrocoDao");
            GEgg     = await ethers.getContractFactory("GEGG");
            Barn     = await ethers.getContractFactory("Barn");
    

            egg   = await GEgg.deploy();
            //const r = await (await egg.owner()).wait();
    
            croco = await CrocoDao.deploy(egg.address, 888);
    
    
            barn  = await Barn.deploy(egg.address, croco.address, 100,10);
    
            
            //eggaddress = await egg.address;
            goose = await Goose.deploy(egg.address,barn.address, 50000);
    
            const egg_r = await egg.deployTransaction.wait();
            const barn_r = await barn.deployTransaction.wait();
            const goose_r = await goose.deployTransaction.wait();
    
            console.log("Contract Deployment Gas info: ", 
            ethers.utils.formatUnits(egg_r.gasUsed * gas_price, "gwei"), 
            ethers.utils.formatUnits(barn_r.gasUsed * gas_price, "gwei"), 
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
            await barn.seasonOpen();
            console.log(nUsers, "users stakeGoose2Pool at  : ", Date.now() - start)
            for( var i = 0; i < nUsers; i++ ){
                randomInt = Math.floor(Math.random() * (Number.MAX_SAFE_INTEGER - 101 ) );
                var myTokenId = await goose.tokenOfOwnerByIndex(users[i].address,0)
                await goose.connect(users[i]).stakeGoose2Pool( randomInt % 10, [myTokenId] );
            }
            const opt_overides2 = {gasLimit: 1562664};
            console.log("seasonClose at          : ", Date.now() - start)
            await barn.seasonClose(opt_overides2);
            const s0 = await barn.seasonsHistory(0);
            const s1 = await barn.seasonsHistory(1);
            console.log("---------barn.seasonsHistory--------")
            console.log(s0,s1);

            await expect(goose.tokenOfOwnerByIndex(users[0].address,0)).to.be.revertedWith("ERC721Enumerable: owner index out of bounds");

            var barnToken = await goose.tokenOfOwnerByIndex(barn.address,0);
            var balanceOf = await goose.balanceOf(barn.address);
            console.log("barnToken: ", barnToken, "    balanceOf: ", balanceOf);
            expect(balanceOf.toNumber()).to.be.equal(nUsers)

            var ranks = new Array(3);
            for( var i = 0; i < 10; i++ ){
                const count = await barn.getGooseSetNum(i);
                const rank = await barn.getRank(i, s1['pondWinners']);
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
            console.log("genisisBlockNumber = ", await barn.genisisBlockNumber());
            const poolDrations = await barn.getTotalGooseStakeDurationPerPond(1);
            console.log("getTotalGooseStakeDurationPerPond:", poolDrations);
            var poolDrationsum = 0;
            poolDrations.forEach(v=>poolDrationsum+=v);
            console.log("getTotalGooseStakeDurationPerPond Sum:", poolDrationsum);
            var rewardSum = BigNumber.from(0);
            var durationSum = BigNumber.from(0);
            console.log(nUsers, "users gooseClaimToBalance at  : ", Date.now() - start)
            for( var i = 0; i < nUsers; i++ ){
                var myTokenId = await barn.getUserStakedGooseIds(users[i].address,0);
                const res = await barn.connect(users[i]).gooseClaimToBalance([myTokenId]);
                //console.log("res:   ",res)
                //durationSum = durationSum.add(res);
                const r = await barn.gooseStake(myTokenId);
                //console.log(r);
                rewardSum = rewardSum.add(r['unclaimedBalance']);
                console.log("Token #", myTokenId.toString(), " claimed:", r['unclaimedBalance'].toString());
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
            var myTokenId = await barn.getUserStakedGooseIds(users[i].address,0);
            await( await barn.connect(users[i]).gooseClaimToBalance([myTokenId])).wait();
            const r = await barn.gooseStake(myTokenId);
            //console.log(r);
            rewardSum = rewardSum.add(r['unclaimedBalance']);
            console.log("Token #", myTokenId.toString(), " claimed:", r['unclaimedBalance'].toString());
        }
        console.log("rewardsSum  = ", rewardSum);
        const reward = Math.floor(rewardSum.toNumber() / 100);
        return Promise.resolve(reward);
        //expect( reward).to.be.equal(9999);
        //close_flag = 0;
    }

    describe( "Staking Games Ver. 2", function(){
        it(" Case 1: Stake 97 users' Goose NFT and check rewards", async function() {
            const SEASON_DURATION = await barn.SEASON_DURATION();
            const SEASON_REST     = await barn.SEASON_REST();
            console.log("SEASON_DURATION: ", SEASON_DURATION, " SEASON_REST", SEASON_REST);
            var   genisisBlock    = 0;
            this.timeout(1000000);
            var close_flag;
            var closed = false;
            var afterStakeBlock = Number.MAX_SAFE_INTEGER;

            var checkresult = 0;

            ethers.provider.on("block", blockNumber =>{
                //console.log("Current blockNumber: ", blockNumber, " genisisBlock: ", genisisBlock);
                if( blockNumber > afterStakeBlock && genisisBlock != 0 && !closed ){
                    if ( blockNumber - genisisBlock > SEASON_DURATION ){
                        console.log("kick, off event block");
                        closed = true;
                        ethers.provider.off("block");
                        barn.seasonClose().then(tx=>{
                            console.log("seasonClose summited at block: ", tx.blockNumber);
                            return tx.wait();
                        }).then( receipt => {
                            console.log("get receipt: ", receipt.blockNumber);
                            console.log("tx status: ", receipt.status);
                            calculateRewards().then(a=>checkresult=a);
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
            
            await (await barn.seasonOpen()).wait();
            genisisBlock = await barn.genisisBlockNumber();
            console.log(nUsers, "barn.seasonOpen at : ", genisisBlock)
            var randomInt = 0;
            for( var i = 0; i < nUsers; i++ ){
                randomInt = Math.floor(Math.random() * (Number.MAX_SAFE_INTEGER - 101 ) );
                var myTokenId = await goose.tokenOfOwnerByIndex(users[i].address,0)
                //if( i != 10 ) randomInt = 0;
                await goose.connect(users[i]).stakeGoose2Pool( randomInt % 10, [myTokenId] );
            }

            afterStakeBlock = await ethers.provider.getBlockNumber();
            console.log(nUsers, " users have finished staking at ", afterStakeBlock);
            
            while ( checkresult == 0 ){
                //console.log("wait ")
                await sleep(1000);
            }
            const s0 = await barn.seasonsHistory(0);
            var ranks = new Array(3);
            for( var i = 0; i < 10; i++ ){
                const count = await barn.getGooseSetNum(i);
                const rank = await barn.getRank(i, s0['topPonds']);
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
            expect(checkNumber).to.be.equal(s0['topPonds']);
            expect( checkresult ).to.be.equal(9999);

        });
        
    });


} );

