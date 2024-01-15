import {ethers} from 'ethers';
import {log, buf_from_hex, method_int32, labels_from_encoded_dns, escape_name} from './utils.js';
import {PRIVATE_KEY} from './config.js';

const SIGNING_KEY = new ethers.SigningKey(PRIVATE_KEY);
const ABI_CODER = ethers.AbiCoder.defaultAbiCoder();
const EXP_SEC = 60;

const METHOD_addr = method_int32('addr(bytes32)');
const METHOD_addr2 = method_int32('addr(bytes32,uint256)');
const METHOD_text = method_int32('text(bytes32,string)');
const METHOD_contenthash = method_int32('contenthash(bytes32)');
const METHOD_multicall = method_int32('multicallWithNodeCheck(bytes32,bytes[])');

async function handle_record(safe_name, record, call_data, multi) {
	let method = call_data.readUInt32BE();
	call_data = call_data.slice(4);
	switch (method) {
		case METHOD_addr: {
			let value = await record?.getAddr(60);
			let address = value ? ethers.hexlify(value) : ethers.ZeroAddress;
			log(safe_name, 'addr()', address);
			return ABI_CODER.encode(['address'], [address]);
		}
		case METHOD_addr2: {
			let [_, coinType] = ABI_CODER.decode(['bytes32', 'uint256'], call_data);
			coinType = Number(coinType);
			let value = await record?.getAddr(Number(coinType));
			log(safe_name, `addr(${coinType})`, value ? ethers.hexlify(value) : null);
			return ABI_CODER.encode(['bytes'], [value ?? '0x']);
		}
		case METHOD_text: {
			let [_, key] = ABI_CODER.decode(['bytes32', 'string'], call_data);
			let value = await record?.getText(key);
			log(safe_name, `text(${key})`, value);
			return ABI_CODER.encode(['string'], [value ?? '']);
		}
		case METHOD_contenthash: {
			let value = await record?.getContentHash(labels);
			log(safe_name, 'contenthash()', value);
			return ABI_CODER.encode(['bytes'], [value ?? '0x']);
		}
		case METHOD_multicall: {
			if (multi) throw 'recursive multicall';
			let [_, recs] = ABI_CODER.decode(['bytes32', 'bytes[]'], call_data);
			log(safe_name, 'multicall()', recs.length);
			recs = await Promise.all(recs.map(data => handle_record(safe_name, record, buf_from_hex(data), true).catch(() => '0x')));
			return ABI_CODER.encode(['bytes[]'], [recs]);
		}
		default: throw `unsupported resolver method: ${method.toString(16).padStart(8, '0')}`;
	}
}

export async function handle_resolve(sender, ccip_data, resolve) {
	let [dns_name, call_data] = ABI_CODER.decode(['bytes', 'bytes'], ccip_data.slice(4));
	let labels = labels_from_encoded_dns(buf_from_hex(dns_name));
	call_data = buf_from_hex(call_data);
	if (call_data.length < 36) throw 'invalid calldata';
	let safe_name = escape_name(labels.join('.'));
	let record = await resolve(labels);
	let result = await handle_record(safe_name, record, call_data);	
	let expires = Math.floor(Date.now() / 1000) + EXP_SEC;
	let hash = ethers.solidityPackedKeccak256(
		['address', 'uint64', 'bytes32', 'bytes32'],
		[sender, expires, ethers.keccak256(ccip_data), ethers.keccak256(result)]
	);
	let sig = SIGNING_KEY.sign(hash);
	let sig_data = ethers.concat([sig.r, sig.s, Uint8Array.of(sig.v)]);
	return ABI_CODER.encode(['bytes', 'uint64', 'bytes'], [sig_data, expires, result]);
}
