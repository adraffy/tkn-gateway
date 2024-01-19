import {ethers} from 'ethers';
import {log, buf_from_hex} from './utils.js';
import {L2_RPC_URL, L2_CHAIN_ID, L2_STORAGE_ADDRESS, COINS} from './config.js';

const COIN_MAP = new Map(COINS.map(x => [x.type, x]));

const CACHE_MS = 5000;

const ALIAS_KEY = 'alias';
const CONTENTHASH_KEY = 'dweb';
		
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

const provider = new ethers.JsonRpcProvider(L2_RPC_URL, L2_CHAIN_ID, {staticNetwork: true});
const contract = new ethers.Contract(L2_STORAGE_ADDRESS, [
	`function getBatchData(string calldata node, string[] calldata keys) external view returns (uint256 nonce, bytes[] memory vs)`
], provider);

const cache = new Map();

class Record {
	constructor(nonce, map) {
		this.nonce = nonce;
		this.map = map;
	}
	getData(key) {
		return this.map.get(key);
	}
	getAddr(type) {
		let coin = COIN_MAP.get(type);
		if (!coin) return;
		let value = this.getText(coin.key);
		if (!value) return;
		return coin.format.encoder(value);
	}
	getText(key) {
		let hex = this.getData(key);
		return hex ? buf_from_hex(hex).toString() : null;
	}
	getContentHash() {
		return this.getData(CONTENTHASH_KEY);
	}
	entries() {
		return [...this.map];
	}
}


export async function fetch_record(labels) {
	let first = labels[0];
	if (/^(0x)?[0-9a-f]{40}$/.test(first)) { // leading label is address-like
		if (!first.startsWith('0x')) labels[0] = `0x${first}`; // add if missing
		let rec = await get_record(labels, [ALIAS_KEY]);
		if (!rec) return; // no record
		let alias = rec.getText(ALIAS_KEY);
		if (!alias) return; // no alias
		labels = alias.split('.'); // replace
	}
	return get_record(labels, KEYS);
} 

async function get_record(labels, keys) {
	if (process.env.USER === 'raffy') {
		labels[labels.length-2] = 'tkn';
	}
	let name = labels.join('.');
	let node = ethers.namehash(name);
	let p = cache.get(node);
	if (Array.isArray(p)) {
		if (p[0] > Date.now()) return p[1];
		p = null;
	}
	if (!p) {
		p = (async () => {
			let rec;
			try {
				log('fetch()', name, node);
				let {nonce, vs} = await contract.getBatchData(node, keys);
				if (nonce) rec = new Record(nonce, new Map(keys.map((k, i) => [k, vs[i]])));
				return rec;
			} finally {
				cache.set(node, [Date.now() + CACHE_MS, rec]);
			}
		})();
		cache.set(node, p);
	}
	return p;
}



