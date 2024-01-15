import {readFile} from 'node:fs/promises';
import {watch} from 'node:fs';
import {log} from './utils.js';
import {ethers} from 'ethers';
import {COINS} from './config.js';

const DB_FILE = new URL('./db.json', import.meta.url);
const COIN_MAP = new Map(COINS.map(x => [x.key, x]));

class Node extends Map {
	constructor(parent, label) {
		super();
		this.parent = parent;
		this.label = label;
	}
	create(label) {
		if (this.has(label)) throw new Error(`duplicate node: ${this.path} => ${label}`);
		let node = new Node(this, label);
		this.set(label, node);
		return node;
	}
	import_from_json(json) {
		if (typeof json !== 'object' || Array.isArray(json)) throw new Error('expected object');
		let rec = json['.'];
		if (rec) {
			this.rec = new Record(rec);
			for (let [ks, v] of Object.entries(json)) {
				ks = ks.trim();
				if (!ks || ks === '.') continue;
				for (let k of ks.split(/\s+/)) {
					k = ethers.ensNormalize(k);
					this.create(k).import_from_json(v);
				}
			}
		} else {
			this.rec = new Record(json);
		}
	}
	*find(predicate) {
		let stack = [this];
		while (stack.length) {
			let node = stack.pop();
			let {rec} = node;
			if (rec && (!predicate || predicate(rec))) yield rec;
			stack.push(...node.values());
		}
	}
	get path() {
		let v = [];
		for (let node = this; node.parent; node = node.parent) {
			v.push(node.label);
		}
		return v.join('.');
	}
	print(indent = 0) {
		console.log('  '.repeat(indent) + this.label);
		for (let x of this.values()) {
			x.print(indent + 1);
		}
	}
}

class Record {
	constructor(obj, parent) {
		this.map = new Map(Object.entries(obj).map(([k, v]) => {
			let coin = COIN_MAP.get(k);
			if (coin) {
				k = coin.type;
				v = coin.format.decoder(v);
			}
			return [k, v];
		}));
		this.parent = parent;
	}
	getAddr(coin) {
		return this.map.get(coin);
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

function tree_from_names(names) {
	let root = new Map();
	for (let name of names) {
		let node = root;
		for (let label of ethers.ensNormalize(name).split('.').reverse()) {
			let next = node.get(label);
			if (!next) {
				next = new Map();
				node.set(label, next);
			}
			node = next;
		}
	}
	return root;
}

async function load() {
	try {
		let {basenames, root} = JSON.parse(await readFile(DB_FILE));

		let base = tree_from_names(basenames);

		// build tree from json
		let root_node = new Node(null, '[root]');
		root_node.import_from_json(root);

		// create reverse for each chain
		let reverse_node = root_node.create('addr');
		let records = [...root_node.find()];
		for (let coin of COINS) {
			if (!coin.chain) continue;
			let node = reverse_node.create(`${coin.chain}`);
			for (let rec of records) {
				let address = rec.map.get(coin.type);
				if (!address) continue;
				let label = address.toString('hex');
				if (!node.has(label)) { // use the first match
					node.create(label).rec = rec;
				}
			}
		}

		db = {base, node: root_node};
		log(`Database: reloaded`);
		console.log('Basenames: ', basenames);
		root_node.print();

	} catch (err) {
		log('Database Error', err);
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