import {ethers} from 'ethers';

function pad2(x) { return String(x).padStart(2, '0'); }
export function log(...a) {
	let d = new Date();
	console.log(`${d.getFullYear()}-${pad2(d.getMonth()+1)}-${pad2(d.getDate())} ${d.toLocaleTimeString(undefined, {hour12: false})}`, ...a);
}

export function buf_from_hex(hex) {
	return Buffer.from(hex.slice(2), 'hex');
}

export function method_int32(decl) {
	return parseInt(ethers.id(decl).slice(0, 10));
}

export function labels_from_encoded_dns(buf) {
	let labels = [];
	let i = 0;
	while (true) {
		let len = buf[i++];
		if (!len) break;
		labels.push(buf.slice(i, i += len).toString('utf8'));
	}
	return labels;
}
