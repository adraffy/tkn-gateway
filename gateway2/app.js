import {createServer} from 'node:http';
import {ethers} from 'ethers';
import {getRecord} from './json/index.js';
import {HTTP_PORT, PRIVATE_KEY, ENDPOINTS} from './config.js';
import {handleCCIPRead, RESTError} from '@resolverworks/ezccip';

const signingKey = new ethers.SigningKey(PRIVATE_KEY);

createServer(async (req, reply) => {
	try {
		req._ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
		reply.setHeader('access-control-allow-origin', '*');
		let url = new URL(req.url, 'http://a');
		switch (req.method) {
			case 'GET': return reply.end('TKN Gateway');
			case 'OPTIONS': return reply.setHeader('access-control-allow-headers', '*').end();
			case 'POST': {
				let resolver = ENDPOINTS[url.pathname];
				if (!resolver) throw new RESTError(404, 'resolver not found');
				let v = [];
				for await (let x of req) v.push(x);
				let {sender, data: request} = JSON.parse(Buffer.concat(v));
				let {data, history} = await handleCCIPRead({sender, request, signingKey, resolver, getRecord});
				log(req, history.toString());
				return write_json(reply, {data});
			}
			default: throw new RESTError(400, 'unsupported http method');
		}
	} catch (err) {
		let status = 500;
		let message = 'internal error';
		if (err instanceof RESTError) {
			({status, message} = err);
		}
		reply.statusCode = status;
		write_json(reply, {message});
		log(req, status, err);
	}
}).listen(HTTP_PORT).once('listening', () => {
	console.log(`Signer: ${ethers.computeAddress(signingKey)}`);
	console.log(`Listening on ${HTTP_PORT}`);
});

function log(req, ...a) {
	let date = new Date();
	let time = date.toLocaleTimeString(undefined, {hour12: false});
	date = `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
	console.log(date, time, req._ip, req.method, req.url, ...a);
}

function write_json(reply, json) {
	let buf = Buffer.from(JSON.stringify(json));
	reply.setHeader('content-length', buf.length);
	reply.setHeader('content-type', 'application/json');
	reply.end(buf);
}
