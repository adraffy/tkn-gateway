/// raffy.eth
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts@4.8.2/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts@4.8.2/utils/introspection/IERC165.sol";
import {BytesUtils} from "@ensdomains/ens-contracts/contracts/wrapper/BytesUtils.sol";

interface WTF {
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
	bool _noContenthash;
	
	struct KV {
		string k;
		string v;
	}

	event FieldsChanged();
	event BasenameChanged(bytes indexed dnsname);

	uint8 constant KIND_TEXT = 1;
	uint8 constant KIND_ADDR = 2;

	constructor() {
		addText("name");
		addText("avatar");
		addText("description");
		addCoin("$eth", 60);
		addCoin("$btc", 0);
	}
	function setBasename(bytes calldata dnsname) onlyOwner external {
		basename = dnsname;
		emit BasenameChanged(dnsname);
	}
	function addText(string memory name) onlyOwner public {
		bytes memory v = abi.encodePacked(KIND_TEXT, name);
		addField(keccak256(v), v);
	}
	function addCoin(string memory name, uint64 coinType) onlyOwner public {
		bytes memory v = abi.encodePacked(KIND_ADDR, coinType);
		addField(keccak256(v), abi.encodePacked(v, name));
	}
	function toggleContenthash() onlyOwner external {
		_noContenthash = !_noContenthash;
	}
	function addField(bytes32 hash, bytes memory field) internal {
		uint248 key = uint224(uint256(hash));
		if (_fields[key].length == 0) {
			uint256 last = _fieldCount;
			_fieldCount = last + 1;
			_fields[last] = abi.encodePacked(key);
		}
		_fields[key] = field;
		emit FieldsChanged();
	}
	function removeFieldAt(uint256 i) onlyOwner external {
		uint256 last = _fieldCount - 1;
		_fieldCount = last;
		_fields[i] = _fields[last];
		emit FieldsChanged();
	}
	function fieldNames() public view returns (string[] memory names) {
		uint256 n = _fieldCount;
		names = new string[](n + (_noContenthash ? 0 : 1));
		for (uint256 i = 0; i < n; i += 1) {
			bytes memory v = _fields[uint256(bytes32(_fields[i])) >> 8];
			if (uint8(v[0]) == KIND_TEXT) {
				assembly {
					mstore(add(v, 1), sub(mload(v), 1))
					v := add(v, 1)
				}
				names[i] = string(v);
			} else { //if (uint8(v[0]) == KIND_ADDR) {
				assembly {
					mstore(add(v, 9), sub(mload(v), 9))
					v := add(v, 9)
				}
				// to enforce prefix, use offset 8 instead of 9 above
				//v[0] = '$';
				names[i] = string(v);
			}
		}
		if (!_noContenthash) {
			names[n] = "#contenthash";
		}
	}
	function makeCalls(bytes32 node) external view returns (bytes[] memory fs) {
		uint256 n = _fieldCount;
		fs = new bytes[](n + (_noContenthash ? 0 : 1));
		for (uint256 i; i < n; i += 1) {
			bytes memory v = _fields[uint256(bytes32(_fields[i])) >> 8];
			if (uint8(v[0]) == KIND_TEXT) {
				assembly {
					mstore(add(v, 1), sub(mload(v), 1))
					v := add(v, 1)
				}
				fs[i] = abi.encodeCall(WTF.text, (node, string(v)));
			} else { //if (uint8(v[0]) == KIND_ADDR) {
				uint256 coinType;
				assembly { coinType := mload(add(v, 9)) }
				fs[i] = abi.encodeCall(WTF.addr, (node, uint64(coinType)));
			}
		}
		if (!_noContenthash) {
			fs[n] = abi.encodeCall(WTF.contenthash, (node));
		}
	}

	function lookup(string calldata tick) external view returns (KV[] memory) {
		require(bytes(tick).length < 256, "length");
		bytes32 node0 = basename.namehash(0);
		bytes32 node = keccak256(abi.encodePacked(node0, keccak256(bytes(tick))));
		address resolver = WTF(ENS_REGISTRY).resolver(node);
		if (resolver != address(0)) return fancy(WTF(resolver).multicall(this.makeCalls(node)));
		resolver = WTF(ENS_REGISTRY).resolver(node0);
		(bool ok, bytes memory v) = resolver.staticcall(abi.encodeCall(WTF.resolve, (
			abi.encodePacked(uint8(bytes(tick).length), tick, basename), 
			abi.encodeCall(WTF.multicall, (this.makeCalls(node)))
		)));
		if (ok) return fancy(abi.decode(v, (bytes[]))); 
		if (bytes4(v) != OffchainLookup.selector) assembly { revert(add(v, 32), mload(v)) }
		assembly {
			mstore(add(v, 4), sub(mload(v), 4)) 
			v := add(v, 4)
		}
		(, string[] memory urls, bytes memory callData, bytes4 callbackFunction, bytes memory extraData) = abi.decode(v, (address, string[], bytes, bytes4, bytes));
		revert OffchainLookup(address(this), urls, callData, this.lookupCallback.selector, abi.encode(resolver, callbackFunction, extraData));
	}
	function lookupCallback(bytes calldata response, bytes calldata wrappedData) external view returns (KV[] memory) {
		(address resolver, bytes4 callbackFunction, bytes memory extraData) = abi.decode(wrappedData, (address, bytes4, bytes));
		(bool ok, bytes memory v) = resolver.staticcall(abi.encodeWithSelector(callbackFunction, response, extraData));
		if (!ok) assembly { revert(add(v, 32), mload(v)) }
		return fancy(abi.decode(abi.decode(v, (bytes)), (bytes[])));
	}

	function fancy(bytes[] memory values) internal view returns (KV[] memory kv) {
		string[] memory names = fieldNames();
		require(values.length == names.length, "mod");
		uint256 n;
		kv = new KV[](values.length);
		for (uint256 i = 0; i < values.length; i += 1) {
			bytes memory v = abi.decode(values[i], (bytes));
			if (v.length == 0) continue;
			bytes memory f = _fields[uint256(bytes32(_fields[i])) >> 8];
			kv[n] = KV(names[i], uint8(f[0]) == KIND_TEXT ? string(v) : toHex(v));
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