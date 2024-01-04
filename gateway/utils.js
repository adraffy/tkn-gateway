import {ethers} from 'ethers';

function pad2(x) { return String(x).padStart(2, '0'); }
export function log(...a) {
	let d = new Date();
	console.log(`${d.getFullYear()}-${pad2(d.getMonth()+1)}-${pad2(d.getDate())} ${d.toLocaleTimeString(undefined, {hour12: false})}`, ...a);
}

export function is_address(s) {
	return typeof s === 'string' && /^0x[0-9a-f]{40}$/i.test(s);
}

export function is_hex(s) {
	return typeof s === 'string' && /^0x[0-9a-f]*$/i.test(s);
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

export function escape_name(s) {
	return [...s].map(x => {
		let c = x.codePointAt(0);
		return c >= 0x20 && c < 0x80 ? x : `{${c.toString(16).toUpperCase().padStart(2, '0')}}`;
	}).join('');
}
