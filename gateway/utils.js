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

export function buf_from_hex(s) {
	return Buffer.from(s.slice(2), 'hex');
}

export function method_int32(s) {
	return parseInt(ethers.id(s).slice(0, 10));
}

export function labels_from_encoded_dns(buf) {
	let v = [];
	let i = 0;
	while (true) {
		let len = buf[i++];
		if (!len) break;
		v.push(buf.slice(i, i += len).toString());
	}
	return v;
}

export function escape_name(s) {
	return Array.from(s, ch => {
		let cp = ch.codePointAt(0);
		return cp >= 0x20 && cp < 0x80 ? ch : `{${cp.toString(16).toUpperCase().padStart(2, '0')}}`;
	}).join('');
}
