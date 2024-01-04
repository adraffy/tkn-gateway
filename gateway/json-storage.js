import {readFile} from 'node:fs/promises';
import {watch} from 'node:fs';
import {log} from './utils.js';
import {ensNormalize} from 'ethers';
import {COIN_MAP} from './config.js';

const DB_FILE = new URL('./db.json', import.meta.url);

class Record {
	constructor(obj, parent) {
		this.map = new Map(Object.entries(obj));
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

let root;
watch(DB_FILE, () => {
	root = null;
});

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
				k = ensNormalize(k);
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
		root = tree_from_json(JSON.parse(await readFile(DB_FILE)), null, []);
		log(`Database: reloaded`);
		print_tree(root);
	} catch (err) {
		log(`Database Error: ${err.message}`);
		console.log(err);
	}
}

function print_tree(node, indent = 0) {
	console.log('  '.repeat(indent) + (node.path || '[root]'));
	for (let x of node.values()) {
		print_tree(x, indent + 1);
	}
}

export async function fetch_record(labels) {
	if (labels.pop() !== 'eth') return;
	if (labels.pop() !== 't-k-n') return;
	if (!root) root = load();
	let node = root;
	await node;
	while (node && labels.length) {
		node = node.get(labels.pop());
	}
	return node?.rec;
}