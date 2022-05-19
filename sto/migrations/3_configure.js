var RegulatedTokenERC1404 = artifacts.require("./RegulatedTokenERC1404.sol");
var RegulatorService = artifacts.require("./RegulatorService.sol");
var ServiceRegistry = artifacts.require("./ServiceRegistry.sol");
const HDWalletProvider = require('truffle-hdwallet-provider');
const fs = require('fs');
//var Web3 = require('web3');
//const mnemonic = fs.readFileSync("../.secret").toString().trim();
const mnemonic = require('./libs/mnemonic');
const rinkebyProvider = new HDWalletProvider(mnemonic, "https://rinkeby.infura.io/v3/d75f1cc2885c410b8d59febf36986c9d"); //'https://rinkeby.infura.io');
const providerMainnet = new HDWalletProvider(mnemonic, "https://mainnet.infura.io/v3/d75f1cc2885c410b8d59febf36986c9d");//'https://mainnet.infura.io');
const ropstenProvider = new HDWalletProvider(mnemonic, "https://ropsten.infura.io/v3/d75f1cc2885c410b8d59febf36986c9d");
//console.log(provider);
module.exports = async function(deployer, network, accounts) {
  let from, newOwner;
  console.log("Network %s", network)
  if(network == 'local' || network == 'development') {
    from = accounts[0],
    newOwner = accounts[1]
  } else if (network == 'rinkeby' || network == 'rinkeby-fork') {
    newOwner = "0x75Cb7cc29Cc9489A85E14744391Df17Dc8cA3746"
    //0xa8836881DCACE8bF1DaAC141A3dAbD9A4884dBFB
    //var web3 = new Web3(new Web3.providers.HttpProvider(provider));
    //console.log(provider.addresses[0]);
    from = rinkebyProvider.addresses[0]
    //from = await web3.eth.getAccounts();
  } else if (network == 'ropsten' || network == 'ropsten-fork') {
    // client wallet
    newOwner = "0x75Cb7cc29Cc9489A85E14744391Df17Dc8cA3746"
    from = ropstenProvider.addresses[0]
    //from = await web3.eth.getAccounts();
  } else if (network == 'mainnet' || network == 'mainnet-fork') {
    //var web3 = new Web3(new Web3.providers.HttpProvider(provider));
    // client wallet
    newOwner = "0x75Cb7cc29Cc9489A85E14744391Df17Dc8cA3746"
    from = providerMainnet.addresses[0]
    //from = await web3.eth.getAccounts();
  }//ADD WALLET CONTRACT
//No transactions yet

  let rtoken = await RegulatedTokenERC1404.deployed();

  initSupply = "5000000000"
  console.log("Minting initial supply of %s ...", initSupply)
  let tx = await rtoken.contract.methods.mint(newOwner, web3.utils.toWei(initSupply, 'ether')).send({from: from, gas: 150000})
  let balance = await rtoken.contract.methods.balanceOf(newOwner).call()
  console.log("Address %s, balance: %i", newOwner, web3.utils.fromWei(balance, 'ether'))

  console.log("RegulatedTokenERC1404 transferOwnership to...")
  await rtoken.contract.methods.transferOwnership(newOwner).send({from: from, gas: 150000})
  let owner = await rtoken.contract.methods.owner().call()
  console.log(owner)


  let regulatorService = await RegulatorService.deployed();

  console.log("Setting transfer permission for newOwner...")
  tx = await regulatorService.contract.methods.setPermission(rtoken.address, newOwner, 3).send({from: from, gas: 150000})
  console.log("Address: %s, Permission: %i", tx.events.LogPermissionSet.returnValues.participant, tx.events.LogPermissionSet.returnValues.permission)

  console.log("Setting partial transfer to true...")
  tx = await regulatorService.contract.methods.setPartialTransfers(rtoken.address, true).send({from: from, gas: 150000})
  console.log("Token: %s, Partial transfert enabled: %s", tx.events.LogPartialTransferSet.returnValues.token, tx.events.LogPartialTransferSet.returnValues.enabled)


  console.log("RegulatorService transferOwnership to...")
  await regulatorService.contract.methods.transferOwnership(newOwner).send({from: from, gas: 150000})
  owner = await regulatorService.contract.methods.owner().call()
  console.log(owner)


  let serviceRegistry = await ServiceRegistry.deployed();
  console.log("ServiceRegistry transferOwnership to...")
  tx = await serviceRegistry.contract.methods.transferOwnership(newOwner).send({from: from, gas: 150000})
  owner = await serviceRegistry.contract.methods.owner().call()
  console.log(owner)


};
