import {fetch_record} from './storage.js';

let rec = await fetch_record(['chonk', 'base', 't-k-n', 'eth']);

console.log(rec.entries());

console.log(rec.getText('avatar'));

console.log(rec.getAddr(60));
