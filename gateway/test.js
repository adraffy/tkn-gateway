import {ethers} from 'ethers';
//import {fetch_record} from './json-storage.js';
import {fetch_record, KEYS} from './evm-storage.js';

let labels = ['0x833589fcd6edb6e08f4c7c32d4f71b54bda02913', 'base', 'tkn', 'eth'];

let rec = await fetch_record(labels);
//await fetch_record(labels); 
//await fetch_record(labels); 
//await fetch_record(labels); // should be instant since cached

console.log(rec.getText('name'));
console.log(rec.getAddr(60));
