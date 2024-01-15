import {convertEVMChainIdToCoinType, formatsByCoinType} from '@ensdomains/address-encoder';

export const PRIVATE_KEY = '0xbd1e630bd00f12f0810083ea3bd2be936ead3b2fa84d1bd6690c77da043e9e02';
export const HTTP_PORT = 8014;
export const L1_RESOLVER_ADDRESS = '0xF2C43c6389638Fc07b31FC78Ba06928a029bFCAB';
export const L2_STORAGE_ADDRESS = '0x0d3e01829E8364DeC0e7475ca06B5c73dbA33ef6';

// https://github.com/satoshilabs/slips/blob//master/slip-0044.md
export const COINS = [
	{type: 60, chain: 1, key: 'contractAddress'},
	{type: 0, key: 'btc_address'},
	{type: 2, key: 'ltc_address'},
	{type: 3, key: 'doge_address'},
	{chain: 10, key: 'op_address'},
	{chain: 56, key: 'bnb_address'},
	{chain: 139, key: 'poly_address'},
	{chain: 501, key: 'solana_address'},
	{chain: 42161, key: 'arb1_address'}
];
for (let coin of COINS) {	
	try {
		if (!Number.isInteger(coin.type)) {
			if (coin.chain) {
				coin.type = convertEVMChainIdToCoinType(coin.chain);
			} else {
				throw new Error('unable to derive coin type');
			}
		}
		coin.format = formatsByCoinType[coin.type];
		if (!coin.format) {
			throw new Error('missing coin format');
		}
	} catch (err) {
		console.log(coin);
		throw err;
	}
}
