# tkn-gateway
tkn.eth Gateway

1. Goerli: register `t-k-n.eth`
1. Goerli: deploy [`L1Resolver.sol`]('./L1Resolver.sol) → [`0xF2C43c6389638Fc07b31FC78Ba06928a029bFCAB`](https://goerli.etherscan.io/address/0xF2C43c6389638Fc07b31FC78Ba06928a029bFCAB)
1. Base: deploy [`L2Storage.sol`](./L2Storage.sol) → [`0x0d3e01829E8364DeC0e7475ca06B5c73dbA33ef6`](https://sepolia.basescan.org/address/0x0d3e01829E8364DeC0e7475ca06B5c73dbA33ef6)
1. `node gateway/app.js`
