/// raffy.eth
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts@4.8.2/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts@4.8.2/utils/introspection/IERC165.sol";
import {BytesUtils} from "@ensdomains/ens-contracts/contracts/wrapper/BytesUtils.sol";

interface I {
	function resolver(bytes32 node) external view returns (address);
	function resolve(bytes memory name, bytes memory data) external view returns (bytes memory);
	function multicall(bytes[] memory calls) external view returns (bytes[] memory);
	function text(bytes32 node, string memory key) external view returns (string memory);
	function addr(bytes32 node, uint256 coinType) external view returns (bytes[] memory);
	function contenthash(bytes32 node) external view returns (bytes[] memory);
}
	
error OffchainLookup(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData);

contract TNS is Ownable, IERC165 {
	using BytesUtils for bytes;

	function supportsInterface(bytes4 x) external pure returns (bool) {
		return x == type(IERC165).interfaceId;
	}

	address constant ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;

	bytes public basename = hex"05742d6b2d6e0365746800";

	mapping (uint256 => bytes) _fields;
	uint256 _fieldCount;
	
	struct KV {
		string k;
		string v;
	}

	event FieldsChanged();
	event BasenameChanged(bytes indexed dnsname);

	constructor() {
		addText("name");
		addText("avatar");
		addText("description");
		addField("$eth", abi.encodeCall(I.addr, (0, 60)));
		addField("$btc", abi.encodeCall(I.addr, (0, 0)));
		addField("#contenthash", abi.encodeCall(I.contenthash, (0)));
	}

	function setBasename(bytes calldata dnsname) onlyOwner public {
		basename = dnsname;
		emit BasenameChanged(dnsname);
	}
	function addText(string memory name) public {
		addField(name, abi.encodeCall(I.text, (0, name)));
	}
	function addField(string memory name, bytes memory field) onlyOwner public {
		require(bytes(name).length < 32);
		assembly { mstore(add(field, 36), 0) } // clear the node
		uint248 key = uint224(uint256(keccak256(field))); // hash it zeroed
		assembly { 
			mstore(add(field, 36), mload(add(name, 31)))  // store the name in the node
			mstore8(add(field, 36), mload(name))
		}
		if (_fields[key].length > 0) {
			_fields[key] = field; // update the name
		} else {
			uint256 last = _fieldCount;
			_fieldCount = last + 1; // append
			_fields[key] = field;
			_fields[last] = abi.encodePacked(key); // index lookup
		}
		emit FieldsChanged();
	}
	function removeFieldAt(uint256 i) onlyOwner external {
		uint256 last = _fieldCount - 1;
		_fieldCount = last;
		_fields[i] = _fields[last]; // replace with pop()
		emit FieldsChanged();
	}
	function fields(bytes32 node) external view returns (bytes[] memory fs) {
		uint256 n = _fieldCount;
		fs = new bytes[](n);
		for (uint256 i; i < n; i += 1) {
			bytes memory v = _fields[uint256(bytes32(_fields[i])) >> 8];
			if (node != 0) assembly { mstore(add(v, 36), node) } // replace name with node
			fs[i] = v;
		}
	}

	function lookup(string calldata tick) external view returns (KV[] memory) {
		require(bytes(tick).length < 256, "length");
		bytes32 node0 = basename.namehash(0);
		bytes32 node = keccak256(abi.encodePacked(node0, keccak256(bytes(tick))));
		address resolver = I(ENS_REGISTRY).resolver(node);
		if (resolver != address(0)) return fancy(I(resolver).multicall(this.fields(node))); // on-chain multicall
		resolver = I(ENS_REGISTRY).resolver(node0);
		(bool ok, bytes memory v) = resolver.staticcall(abi.encodeCall(I.resolve, ( // use wildcard 
			abi.encodePacked(uint8(bytes(tick).length), tick, basename), 
			abi.encodeCall(I.multicall, (this.fields(node))) // wildcard multicall
		)));
		if (ok) return fancy(abi.decode(v, (bytes[]))); // smart resolver?
		if (bytes4(v) != OffchainLookup.selector) assembly { revert(add(v, 32), mload(v)) } // expected
		assembly {
			mstore(add(v, 4), sub(mload(v), 4)) // trim selector
			v := add(v, 4)
		}
		(, string[] memory urls, bytes memory callData, bytes4 callback, bytes memory extraData) = abi.decode(v, (address, string[], bytes, bytes4, bytes));
		revert OffchainLookup(address(this), urls, callData, this.lookupCallback.selector, abi.encode(resolver, callback, extraData));
	}
	function lookupCallback(bytes calldata response, bytes calldata wrappedData) external view returns (KV[] memory) {
		(address resolver, bytes4 callback, bytes memory extraData) = abi.decode(wrappedData, (address, bytes4, bytes));
		(bool ok, bytes memory v) = resolver.staticcall(abi.encodeWithSelector(callback, response, extraData));
		if (!ok) assembly { revert(add(v, 32), mload(v)) }
		return fancy(abi.decode(abi.decode(v, (bytes)), (bytes[])));
	}

	function fancy(bytes[] memory vs) internal view returns (KV[] memory kv) {
		require(vs.length == _fieldCount, "mod");
		uint256 n;
		kv = new KV[](vs.length);
		for (uint256 i; i < vs.length; i++) {
			bytes memory v = abi.decode(vs[i], (bytes));
			if (v.length == 0) continue;
			bytes memory f = _fields[uint256(bytes32(_fields[i])) >> 8];
			bytes memory k = new bytes(32);
			assembly {
				mstore(add(k, 32), mload(add(f, 37)))
				mstore(k, shr(248, mload(add(f, 36))))
			}
			kv[n] = KV(string(k), bytes4(f) == I.text.selector ? string(v) : toHex(v));
			n += 1;
		}
		assembly { mstore(kv, n) } 
	}

	bytes32 constant RADIX = 0x3031323334353637383961626364656600000000000000000000000000000000;
	function toHex(bytes memory v) internal pure returns (string memory) {
		bytes memory u = new bytes((v.length + 1) << 1);
		assembly {
			mstore8(add(u, 32), 0x30) // 0
			mstore8(add(u, 33), 0x78) // x
			let i := v
			let e := add(i, mload(v))
			let j := add(u, 34)
			for {} lt(i, e) {} {
				i := add(i, 1) 
				let b := mload(i)
				mstore8(j, byte(and(shr(4, b), 15), RADIX))
				j := add(j, 1)
				mstore8(j, byte(and(b, 15), RADIX))
				j := add(j, 1)
			}
		}
		return string(u);
	}

}