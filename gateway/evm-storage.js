import {ethers} from 'ethers';
import {log, buf_from_hex, is_address} from './utils.js';
import {L2_RPC_URL, L2_CHAIN_ID, L2_STORAGE_ADDRESS, COINS} from './config.js';

const COIN_MAP = new Map(COINS.map(x => [x.type, x]));

// https://docs.tkn.xyz/developers/dataset
export const KEYS = [
	'name',
	'description',
	'avatar',
	'url',
	'notice',
	'decimals',
	'twitter',
	'github',
	'dweb',
	'version',
	...[...COIN_MAP.values()].map(x => x.key),
];

const KEY_INDEX_MAP = new Map(KEYS.map((k, i) => [k, i]));

const provider = new ethers.JsonRpcProvider(L2_RPC_URL, L2_CHAIN_ID, {staticNetwork: true});
const contract = new ethers.Contract(L2_STORAGE_ADDRESS, [
	`function getBatchData(string calldata node, string[] calldata keys) external view returns (uint256 nonce, bytes[] memory vs)`
], provider);

const cache = new Map();

class Record {
	constructor(nonce, values) {
		this.nonce = nonce;
		this.values = values;
	}
	getData(key) {
		let i = KEY_INDEX_MAP.get(key);
		return Number.isInteger(i) ? this.values[i] : null;
	}
	getAddr(type) {
		let coin = COIN_MAP.get(type);
		if (!coin) return;
		let value = this.getText(coin.key);
		if (!value) return;
		return coin.format.encoder(value);
	}
	getText(key) {
		return buf_from_hex(this.getData(key))?.toString();
	}
	getContentHash() {
		return this.getData('dweb');
	}
	entries() {
		return this.values.map((v, i) => [KEYS[i], v]);
	}
}


export async function fetch_record(labels) {
	if (/^(0x)?[0-9a-f]{40}$/.test(labels[0])) { // leading label is address-like
		labels[0] = labels[0].slice(-40); // remove "0x" (if it exists)
		let rec = await get_record(labels);
		if (!rec) return; // no record
		let alias = rec.getText('alias');
		if (!alias) return; // no alias
		labels = alias.split('.'); // replace
	}
	return get_record(labels);
} 

async function get_record(labels) {
	if (process.env.USER === 'raffy') {
		labels[labels.length-2] = 'tkn';
	}
	let node = ethers.namehash(labels.join('.'));
	let p = cache.get(node);
	if (Array.isArray(p)) {
		if (p[0] > Date.now()) return p[1];
		p = null;
	}
	if (!p) {
		p = (async () => {
			let rec;
			try {
				log('fetch()', node);
				let {nonce, vs} = await contract.getBatchData(node, KEYS);
				if (nonce) rec = new Record(nonce, vs);
				return rec;
			} finally {
				cache.set(node, [Date.now() + 5000, rec]);
			}
		})();
		cache.set(node, p);
	}
	return p;
}



