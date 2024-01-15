import {readFile} from 'node:fs/promises';
import {watch} from 'node:fs';
import {log} from './utils.js';
import {ethers} from 'ethers';
import {COIN_MAP, REVERSE_COIN_MAP} from './config.js';
import {formatsByCoinType} from '@ensdomains/address-encoder';

const DB_FILE = new URL('./db.json', import.meta.url);

class Record {
	constructor(obj, parent) {
		this.map = new Map(Object.entries(obj).map(([k, v]) => {
			let coin = REVERSE_COIN_MAP.get(k);
			if (Number.isInteger(coin)) {
				let format = formatsByCoinType[coin];
				if (!format) throw new Error(`unknown coin type: ${k} => ${coin}`);
				v = format.decoder(v);
			}
			return [k, v];
		}));
		this.parent = parent;
	}
	getAddr(coinType) {
		return this.map.get(COIN_MAP.get(coinType));
	}
	getText(key) {
		return this.map.get(key);
	}
	getContentHash() {
		return this.map.get('dweb');
	}
}

let db;
watch(DB_FILE, () => {
	db = null;
}).unref();

await load(); // preload database

function tree_from_json(obj, parent, path) {
	if (typeof obj !== 'object' || Array.isArray(obj)) return;	
	let rec = obj['.'];
	let node = new Map();
	node.parent = parent;
	node.path = path.join('.');
	if (rec) {
		node.rec = new Record(rec);
		for (let [ks, v] of Object.entries(obj)) {
			ks = ks.trim();
			if (!ks || ks === '.') continue;
			for (let k of ks.split(/\s+/)) {
				k = ethers.ensNormalize(k);
				path.push(k);
				node.set(k, tree_from_json(v, node, path));
				path.pop();
			}
		}
	} else {
		node.rec = new Record(obj);
	}
	return node;
}

async function load() {
	try {
		let {basenames, root} = JSON.parse(await readFile(DB_FILE));
		let base = new Map();
		for (let name of basenames) {
			let node = base;
			for (let label of ethers.ensNormalize(name).split('.').reverse()) {
				let next = node.get(label);
				if (!next) {
					next = new Map();
					node.set(label, next);
				}
				node = next;
			}
		}
		let node = tree_from_json(root, null, [])
		db = {base, node};
		log(`Database: reloaded`);
		console.log('Basenames: ', basenames);
		print_tree(node);
	} catch (err) {
		log('Database Error', err);
	}
}

function print_tree(node, indent = 0) {
	console.log('  '.repeat(indent) + (node.path || '[root]'));
	for (let x of node.values()) {
		print_tree(x, indent + 1);
	}
}

export async function fetch_record(labels) {
	if (!db) db = load();
	await db;
	let {node, base} = db;
	while (base.size && labels.length) {
		base = base.get(labels.pop());
		if (!base) return; // no basename match
	}
	while (labels.length) {
		node = node.get(labels.pop());
		if (!node) return; // no record match
	}
	return node.rec;
}