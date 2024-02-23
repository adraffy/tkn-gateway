import {ethers} from 'ethers';

let provider = new ethers.CloudflareProvider();
let contract = new ethers.Contract('0x75C29179B30a24f2fD6cdA391d0bBdF7bd1d7cA5', [
	'function lookup(string tick) external view returns (tuple(string, string)[] calls)',
], provider);

//test('0xb3654dc3D10Ea7645f8319668E8F54d2574FBdC8.ftm');
//test('dai.ftm');
test('op');

async function test(tick) {
	const t0 = Date.now();
	try {		
		let fields = Object.fromEntries(await contract.lookup(tick.toLowerCase(), {enableCcipRead: true}));
		console.log({tick, dur: Date.now() - t0, fields});
	} catch (err) {
		console.log(err);
	}
}