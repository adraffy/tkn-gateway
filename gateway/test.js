import {fetch_record} from './storage.js';

let labels = ['chonk', 'base', 't-k-n', 'eth'];

let rec = await fetch_record(labels);
await fetch_record(labels);
await fetch_record(labels);
await fetch_record(labels);
await fetch_record(labels);

console.log(rec);

console.log(rec.entries());

console.log(rec.getText('avatar'));

console.log(rec.getAddr(60));
