import {ethers} from 'ethers';
import {log, buf_from_hex} from './utils.js';
import {L2_STORAGE_ADDRESS, COINS} from './config.js';

const COIN_MAP = new Map(COINS.map(x => [x.type, x.key]));

// https://docs.tkn.xyz/developers/dataset
const KEYS = [
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
	...COIN_MAP.values(),
];

//const HASHED_KEYS = KEYS.map(k => ethers.id(k));
const KEY_INDEX_MAP = new Map(KEYS.map((k, i) => [k, i]));

const provider = new ethers.JsonRpcProvider('https://sepolia.base.org', 84532, {staticNetwork: true});
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
	getAddr(coinType) {
		return this.getData(COIN_MAP.get(coinType));
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
	if (labels.pop() !== 'eth') return;
	if (labels.pop() !== 't-k-n') return;
	//let node = ethers.id(labels.join('.'));	
	let node = labels.join('.');
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