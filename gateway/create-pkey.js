// generate cool d00d address

import {ethers} from 'ethers';

let wallet;
let n = 0;
while (true) {
	++n;
	wallet = ethers.Wallet.createRandom();
	if (wallet.address.slice(2, 6).toLowerCase() === 'd00d') {
		break;
	}
}

console.log({
	t: performance.now(),
	n,
	p: wallet.privateKey,
	a: wallet.address
});
