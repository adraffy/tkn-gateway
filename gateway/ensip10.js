import {ethers} from 'ethers';
import {buf_from_hex, method_int32, labels_from_encoded_dns} from './utils.js';
import {PRIVATE_KEY} from './config.js';

const SIGNING_KEY = new ethers.SigningKey(PRIVATE_KEY);
const ABI_CODER = ethers.AbiCoder.defaultAbiCoder();
const EXP_SEC = 60;

const METHOD_addr = method_int32('addr(bytes32)');
const METHOD_addr2 = method_int32('addr(bytes32,uint256)');
const METHOD_text = method_int32('text(bytes32,string)');
const METHOD_contenthash = method_int32('contenthash(bytes32)');

export async function handle_resolve(sender, ccip_data, resolve) {
	let [dns_name, call_data] = ABI_CODER.decode(['bytes', 'bytes'], ccip_data.slice(4));
	let labels = labels_from_encoded_dns(buf_from_hex(dns_name));
	call_data = buf_from_hex(call_data);
	if (call_data.length < 36) throw 'invalid calldata';
	let method = call_data.readUInt32BE();
	call_data = call_data.slice(4);
	let record = await resolve(labels);
	let result;
	switch (method) {
		case METHOD_addr: {
			let value = await record?.getAddr(60);
			result = ABI_CODER.encode(['address'], [value ?? '0x0000000000000000000000000000000000000000']);
			break;
		}
		case METHOD_addr2: {
			let [_, coinType] = ABI_CODER.decode(['bytes32', 'uint256'], call_data);
			let value = await record?.getAddr(coinType);
			result = ABI_CODER.encode(['bytes'], [value ?? '0x']);
			break;
		}
		case METHOD_text: {
			let [_, key] = ABI_CODER.decode(['bytes32', 'string'], call_data);
			let value = await record?.getText(key);
			result = ABI_CODER.encode(['string'], [value ?? '']);
			break;
		}
		case METHOD_contenthash: {
			let value = await record?.getContentHash(labels);
			result = ABI_CODER.encode(['bytes'], [value ?? '0x']);
			break;
		}
		default: throw `unsupported resolver method: ${method.toString(16).padStart(8, '0')}`;
	}
	let expires = Math.floor(Date.now() / 1000) + EXP_SEC;
	let hash = ethers.solidityPackedKeccak256(
		['address', 'uint64', 'bytes32', 'bytes32'],
		[sender, expires, ethers.keccak256(ccip_data), ethers.keccak256(result)]
	);
	let sig = SIGNING_KEY.sign(hash);
	let sigData = ethers.concat([sig.r, sig.s, Uint8Array.of(sig.v)]);
	return ABI_CODER.encode(['bytes', 'uint64', 'bytes'], [sigData, expires, result]);
}
