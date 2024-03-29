import {createServer} from 'node:http';
import './http.js';
import {ethers} from 'ethers';
import {log, is_address, labels_from_dns_name, safe_str} from './utils.js';
//import {fetch_record} from './evm-storage.js';
import {fetch_record} from './json-storage.js';
import {HTTP_PORT, PRIVATE_KEY, L1_RESOLVER_ADDRESS, COINS} from './config.js';

const SIGNING_KEY = new ethers.SigningKey(PRIVATE_KEY);
const EXP_SEC = 60;
const MULTICALL_MAX_DEPTH = 1;
const COIN_MAP = new Map(COINS.map(x => [x.type, x]));
const ABI_CODER = ethers.AbiCoder.defaultAbiCoder();

const CCIP_ABI = new ethers.Interface([
	'function resolve(bytes name, bytes data) external view returns (bytes)',
	'function multicall(bytes[] calls) external view returns (bytes[])',
]);

const RESOLVER_ABI = new ethers.Interface([
	'function addr(bytes32 node) external view returns (address)',
	'function addr(bytes32 node, uint256 coinType) external view returns (bytes)',
	'function text(bytes32 node, string key) external view returns (string)',
	'function contenthash(bytes32 node) external view returns (bytes)',
	'function multicall(bytes[] calls) external view returns (bytes[])'	
]);
RESOLVER_ABI.forEachFunction(func => func._name = func.name + func.inputs.length);

class History {
	constructor(depth) {
		this.depth = depth;
		this.actions = [];
		this.children = [];
	}
	add(s) {
		this.actions.push(s);
	}
	next() {
		let {depth} = this;
		if (depth > MULTICALL_MAX_DEPTH) throw new Error('too deep');
		let child = new History(depth+1);
		this.children.push(child);
		return child;
	}
	toString() {
		let desc = this.actions.join('.');
		if (this.error) {
			desc += `<${this.error}>`;
		} else if (this.children.length) {
			desc += `[${this.children.join(',')}]`;
		}
		return desc;
	}
}

const http = createServer(async (req, reply) => {
	try {
		let url = new URL(req.url, 'http://a');
		reply.setHeader('access-control-allow-origin', '*');
		switch (req.method) {
			case 'GET': {
				return reply.end('TKN Gateway');
			}
			case 'OPTIONS': {
				reply.setHeader('access-control-allow-headers', '*');
				return reply.end();
			}
			case 'POST': {
				if (url.pathname === '/ccip') {
					return handle_ccip(req, reply);
				} else {
					reply.statusCode = 404;
					return reply.end('file not found');
				}
			}
			default: {
				reply.statusCode = 400;
				return reply.end('unsupported http method');
			}
		}
	} catch (err) {
		log(req.method, req.url, err);
		reply.statusCode = 500;
		return reply.end(err.message);
	}
});

await http.start_listen(HTTP_PORT);
log(`Listening on ${http.address().port}`);

// https://eips.ethereum.org/EIPS/eip-3668
async function handle_ccip(req, reply) {
	try {
		let {sender, data} = await req.read_json();
		if (!is_address(sender)) throw new Error('invalid sender');
		let history = new History(0);
		let result = await handle_ccip_call(sender.toLowerCase(), data.toLowerCase(), history);
		let expires = Math.floor(Date.now() / 1000) + EXP_SEC;
		let hash = ethers.solidityPackedKeccak256(
			['address', 'uint64', 'bytes32', 'bytes32'],
			[L1_RESOLVER_ADDRESS, expires, ethers.keccak256(data), ethers.keccak256(result)]
		);
		let sig = SIGNING_KEY.sign(hash);
		let sig_data = ethers.concat([sig.r, sig.s, Uint8Array.of(sig.v)]);
		data = ABI_CODER.encode(['bytes', 'uint64', 'bytes'], [sig_data, expires, result]);
		log(history.toString());
		return reply.json({data});
	} catch (err) {
		console.log(err);
		reply.statusCode = 500;
		return reply.json({message: 'invalid request'});
	}
}

async function handle_ccip_call(sender, data, history) {
	try {
		let method = data.slice(0, 10);
		let func = CCIP_ABI.getFunction(method);
		if (!func) throw new Error(`unsupported ccip method: ${method}`);
		let args = CCIP_ABI.decodeFunctionData(func, data);
		switch (func.name) {
			case 'resolve': {
				let labels = labels_from_dns_name(ethers.getBytes(args.name));
				history.add(`resolve(${safe_str(labels.join('.'))})`);
				let record = await fetch_record(labels); 
				return await handle_resolve(record, args.data, history);
				// returns without additional encoding
			}
			case 'multicall': {
				history.add(`multicall`);
				args = [await Promise.all(args.calls.map(x => handle_ccip_call(sender, x, history.next()).catch(() => '0x')))];
				break;
			}
			default: new Error('unreachable');
		}
		return CCIP_ABI.encodeFunctionResult(func, args);
	} catch (err) {
		history.error = err;
		throw err;
	}
}

async function handle_resolve(record, calldata, history) {	
	try {
		let method = calldata.slice(0, 10);
		let func = RESOLVER_ABI.getFunction(method);
		if (!func) throw new Error(`unsupported resolve() method: ${method}`);
		let args = RESOLVER_ABI.decodeFunctionData(func, calldata);
		switch (func._name) {
			case 'addr1': {
				history.add(`addr()`);
				let value = await record?.getAddr(60);
				args = [value ? ethers.hexlify(value) : ethers.ZeroAddress];
				break;
			}
			case 'addr2': {
				let type = Number(args.coinType);
				let coin = COIN_MAP.get(type); // note: could return 0x if null
				history.add(`addr(${coin ? coin.key : `0x${args.coinType.toString(16)}`})`);
				let value = await record?.getAddr(type, coin);
				args = [value || '0x'];
				break;
			}
			case 'text2': {
				history.add(`text(${safe_str(args.key)})`);
				let value = await record?.getText(args.key);
				args = [value || ''];
				break;
			}
			case 'contenthash1': {
				history.add('contenthash()');
				let hash = await record?.getContentHash();
				args = [hash || '0x'];
				break;
			}
			case 'multicall1': {
				history.add(`multicall`);
				args = [await Promise.all(args.calls.map(x => handle_resolve(record, x, history.next()).catch(() => '0x')))];
				break;
			}
			default: throw new Error(`unreachable: ${func.name}`);
		}
		return RESOLVER_ABI.encodeFunctionResult(func, args);
	} catch (err) {
		history.error = err;
		throw err;
	}
}