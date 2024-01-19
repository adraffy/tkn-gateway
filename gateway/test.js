import {ethers} from 'ethers';
//import {fetch_record} from './json-storage.js';
import {fetch_record, KEYS} from './evm-storage.js';

let labels = ['wsteth', 'base', 'tkn', 'eth'];

let rec = await fetch_record(labels);
//await fetch_record(labels); 
//await fetch_record(labels); 
//await fetch_record(labels); // should be instant since cached

console.log(rec.getText('name'));
console.log(rec.getAddr(60));
