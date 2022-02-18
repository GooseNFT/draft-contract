// Goose.js

// We import Chai to use its asserting functions here.
const { expect } = require("chai");
const  {ethers}  = require("hardhat")


describe( "Trait Contract Test", function(){
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

    this.beforeEach( async function(){
        //Traits = await ethers.getContractFactory("Traits");
        Goose    = await ethers.getContractFactory("Goose");
        CrocoDao = await ethers.getContractFactory("CrocoDao");
        GEgg     = await ethers.getContractFactory("GEGG");
        Barn     = await ethers.getContractFactory("Barn");
        [owner, user1, user2, ...users] = await ethers.getSigners();
        owner_address = await owner.getAddress();

        //traits = await Traits.deploy();

        egg   = await GEgg.deploy();
        barn  = await Barn.deploy();
        //eggaddress = await egg.address;
        goose = await Goose.deploy(egg.address, barn.address, 50000);
        //croco = await CrocoDao.deploy();

    });

    describe( "Deployment", function(){
        it("Should set the right owner", async function(){
            expect(await goose.owner()).to.equal(owner.address);
            //console.log("owner address: ", owner_address)
        });

        var fs = require('fs');

        traits_dir = "/Users/freedomhui/Code/GooseBrowser/goosebrowser/public/traits/";

        body_traits = new Map();

        fs.readdir(traits_dir, (err, files) => {
            if (err){
                    console.error( traits_dir + " is error: ", err)
                    process.exit(1)
            }
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

            })
            //console.log(body_traits)
            //const json = Object.fromEntries(body_traits)
            //console.log(JSON.stringify(json, null, 4))

        });

        var onetrait = {name: "test1", png: "xxx"};
        var twotrait = {name:"test2", png:"yyy"};
        var arr_trait = [onetrait, twotrait];
        

        it( "uploadTraits case 1", async function(){
            var traiTypes = Array.from(body_traits.keys());
            await goose.setTraitTypes(traiTypes);
            var r = await goose.traitTypes(0);
            //console.log(r)
            expect(r).to.equal("Body");
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
                await goose.uploadTraits(i, traitIndex_arr, trait_arr);
            }

            //await goose.uploadTraits(1, [0,1], arr_trait);
            var r = await goose.traitData(1,0);
            //console.log();
            expect(r['name']).to.equal("Annoy");
            expect(r['png']).to.equal("iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAYAAABV7bNHAAAAAXNSR0IArs4c6QAAAFJJREFUeJzt0TEKwDAIAEDN///cLh0khNLBNhTuwEEFQY0AAAAAYJPjiprf9Vtk98CX1QPkot6+z+ge+JH5EH97NAAAAAAAAAAAAAAAAAAAwEMnZDQHAdOjEJMAAAAASUVORK5CYII=")
        });
        


    });



} )