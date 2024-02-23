/// raffy.eth
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts@4.8.2/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts@4.8.2/utils/introspection/IERC165.sol";
import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IAddressResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/ITextResolver.sol";
import {IPubkeyResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IPubkeyResolver.sol";
import {IContentHashResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IMulticallable} from "@ensdomains/ens-contracts/contracts/resolvers/IMulticallable.sol";
import {BytesUtils} from "@ensdomains/ens-contracts/contracts/wrapper/BytesUtils.sol";

error OffchainLookup(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData);

contract TNS is Ownable, IERC165 {
	using BytesUtils for bytes;

	function supportsInterface(bytes4 x) external pure returns (bool) {
		return x == type(IERC165).interfaceId;
	}

	address constant ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;

	uint256 constant SLOT_FIELD_COUNT = 1; // skip owner
	uint256 constant SLOT_BASENAME = 2;
	uint256 constant SLOT_FIELDS = 3;

	uint8 constant KIND_FLAG_STRING    = 0x80;
	uint8 constant KIND_FLAG_SKIP_4    = 0x40;
	uint8 constant KIND_FLAG_ENCODED   = 0x20;
	uint8 constant KIND_FLAG_NO_DECODE = 0x10;

	uint8 constant KIND_TEXT = 0 | KIND_FLAG_STRING;
	uint8 constant KIND_COIN = 1 | KIND_FLAG_SKIP_4;
	uint8 constant KIND_0ARG = 2 | KIND_FLAG_SKIP_4;

	struct KV {string k; string v; }

	error BadInput();
	error Modified();

	event FieldsChanged();
	event BasenameChanged(string indexed dnsname);

	// setters
	function setBasename(string calldata name) onlyOwner external { 
		setTiny(SLOT_BASENAME, bytes(name));
		emit BasenameChanged(name);
	}
	function addFields(bytes[] calldata fields) onlyOwner external {
		unchecked {
			uint256 n = fields.length;
			if (n == 0) revert BadInput();
			uint256 fc;
			assembly { fc := sload(SLOT_FIELD_COUNT) }
			uint256 slot = SLOT_FIELDS + fc;
			for (uint256 i; i < n; i += 1) {
				setTiny(slot + i, fields[i]);
			}
			assembly { sstore(SLOT_FIELD_COUNT, add(fc, n)) }
			emit FieldsChanged();
		}
	}
	function removeFieldAt(uint256 i) onlyOwner external {
		unchecked {
			uint256 fc;
			assembly { fc := sload(SLOT_FIELD_COUNT) }
			if (i >= fc) revert BadInput();        
			fc -= 1;
			setTiny(SLOT_FIELDS + i, getTiny(SLOT_FIELDS + fc));
			assembly { sstore(SLOT_FIELD_COUNT, fc) }
			emit FieldsChanged();
		}
	}

	// profile
	function fieldNames() public view returns (string[] memory names) {
		unchecked {
			uint256 fc;
			assembly { fc := sload(SLOT_FIELD_COUNT) }
			names = new string[](fc);
			for (uint256 i; i < fc; i += 1) {
				bytes memory v = getTiny(SLOT_FIELDS + i);
				uint256 kind = uint8(v[0]);
				uint256 trim = (kind & KIND_FLAG_SKIP_4) != 0 ? 5 : 1;
				assembly {
					mstore(add(v, trim), sub(mload(v), trim))
					v := add(v, trim)
				}
				if ((kind & KIND_FLAG_ENCODED) != 0) {
					names[i] = string(abi.decode(v, (string)));
				} else {
					names[i] = string(v);
				}
			}
		}
	}
	function makeCalls(bytes32 node) external view returns (bytes[] memory calls) {
		unchecked {
			uint256 fc;
			assembly { fc := sload(SLOT_FIELD_COUNT) }
			calls = new bytes[](fc);
			for (uint256 i; i < fc; i += 1) {
				bytes memory v = getTiny(SLOT_FIELDS + i);
				uint256 kind = uint8(v[0]);
				uint256 trim = (kind & KIND_FLAG_SKIP_4) != 0 ? 5 : 1;
				uint256 arg0;      
				assembly {
					arg0 := and(add(v, 5), 0xFFFFFFFF)
					mstore(add(v, trim), sub(mload(v), trim))
					v := add(v, trim)
				}
				if (kind == KIND_TEXT) {
					calls[i] = abi.encodeCall(ITextResolver.text, (node, string(v)));
				} else if (kind == KIND_COIN) {
					calls[i] = abi.encodeCall(IAddressResolver.addr, (node, arg0));
				} else if (kind == KIND_0ARG) {
					calls[i] = abi.encodeWithSelector(bytes4(uint32(arg0)), node);
				} else {
					(, v) = abi.decode(v, (string, bytes));
					assembly { mstore(add(v, 36), node) } // replace node
					calls[i] = v;
				}
			}
		}
	}

	// primary api
	function lookup(string calldata tick) external view returns (KV[] memory) {
		bytes memory name0 = getTiny(SLOT_BASENAME);
		bytes32 node0 = dns_from_name(name0).namehash(0);
		address resolver = ENS(ENS_REGISTRY).resolver(node0);
		bytes memory name = dns_from_name(abi.encodePacked(tick, '.', name0));
		bytes32 node = name.namehash(0);
		(bool ok, bytes memory v) = resolver.staticcall(abi.encodeCall(IExtendedResolver.resolve, (
			name, 
			abi.encodeCall(IMulticallable.multicall, (this.makeCalls(node)))
		)));
		if (ok) return lookupOnchain(node, abi.decode(v, (bytes[]))); 
		if (bytes4(v) != OffchainLookup.selector) assembly { revert(add(v, 32), mload(v)) }
		assembly {
			mstore(add(v, 4), sub(mload(v), 4)) 
			v := add(v, 4)
		}
		(, string[] memory urls, bytes memory callData, bytes4 callbackFunction, bytes memory extraData) = abi.decode(v, (address, string[], bytes, bytes4, bytes));
		revert OffchainLookup(address(this), urls, callData, this.lookupCallback.selector, abi.encode(resolver, node, callbackFunction, extraData));
	}
	function lookupCallback(bytes calldata response, bytes calldata wrappedData) external view returns (KV[] memory) {
		(address resolver, bytes32 node, bytes4 callbackFunction, bytes memory extraData) = abi.decode(wrappedData, (address, bytes32, bytes4, bytes));
		(bool ok, bytes memory v) = resolver.staticcall(abi.encodeWithSelector(callbackFunction, response, extraData));
		if (!ok) assembly { revert(add(v, 32), mload(v)) }
		return lookupOnchain(node, abi.decode(abi.decode(v, (bytes)), (bytes[])));
	}
	function lookupOnchain(bytes32 node, bytes[] memory values) internal view returns (KV[] memory kv) {
		unchecked {
			string[] memory names = fieldNames();
			if (names.length != values.length) revert Modified();
			bytes[] memory calls = this.makeCalls(node);
			address resolver = ENS(ENS_REGISTRY).resolver(node);
			uint256 n;
			kv = new KV[](values.length);
			for (uint256 i; i < values.length; i += 1) {      
				bytes memory v = getTiny(SLOT_FIELDS + i);
				uint256 kind = uint8(v[0]);
				bool ok;
				if (resolver != address(0)) {
					(ok, v) = resolver.staticcall(calls[i]);
					if (ok) {
						if (v.length != 0 && (kind & KIND_FLAG_NO_DECODE) == 0) {
							v = abi.decode(v, (bytes));
						}
						if (isNull(v)) {
							ok = false;
						}
					}
				}
				if (!ok) {
					v = values[i];
					if (v.length != 0 && (kind & KIND_FLAG_NO_DECODE) == 0) {
						v = abi.decode(v, (bytes));
					}
					if (isNull(v)) {
						continue;
					}
				}
				if (v.length == 0) continue;
				kv[n] = KV(names[i], (kind & KIND_FLAG_STRING) != 0 ? string(v) : toHex(v));
				n += 1;
			}
			assembly { mstore(kv, n) } 
		}
	}

	// utils
	function dns_from_name(bytes memory str) internal pure returns (bytes memory dns) {
		unchecked {
			uint256 n = str.length;
			 // [a.b  ]
			 // [1a1b0]
			dns = new bytes(n + 2);
			assembly {
				let p := add(str, 32)
				let q := add(dns, 32)
				let r := q
				function check(a, b) {
					let w := sub(b, a)
					if or(eq(a, b), gt(w, 255)) {
						let x := mload(64)
						mstore(x, 0x2bb9acf700000000000000000000000000000000000000000000000000000000)
						revert(x, 4)
					}
					mstore8(a, w)
				} 
				for { let i := 0 } lt(i, n) { i := add(i, 1) } {
					let b := shr(248, mload(add(p, i)))
					if eq(b, 46) {
						check(r, q)
						r := add(q, 1)
					} {
						q := add(q, 1)
						mstore8(q, b)
					}
				}
				check(r, q)
			}
		}
	}

	function isNull(bytes memory v) internal pure returns (bool) {
		uint256 p;
		uint256 e;
		assembly { 
			p := add(v, 32)
			e := add(p, mload(v))
		}
		while (p < e) {
			uint256 word;
			assembly {
				word := mload(p) 
				p := add(p, 32)
			}
			if (word != 0) return false;
		}
		return true;
	}
	bytes32 constant RADIX = 0x3031323334353637383961626364656600000000000000000000000000000000;
	function toHex(bytes memory v) internal pure returns (string memory) {
		unchecked {
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

	// ************************************************************
	// TinyKV.sol: https://github.com/adraffy/TinyKV.sol

	// header: first 4 bytes
	// [00000000_00000000000000000000000000000000000000000000000000000000] // null (0 slot)
	// [00000000_00000000000000000000000000000000000000000000000000000001] // empty (1 slot, hidden)
	// [00000001_XX000000000000000000000000000000000000000000000000000000] // 1 byte (1 slot)
	// [0000001C_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX] // 28 bytes (1 slot
	// [0000001D_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX][XX000000...] // 29 bytes (2 slots)
	function tinySlots(uint256 size) internal pure returns (uint256) {
		unchecked {
			return size != 0 ? (size + 35) >> 5 : 0; // ceil((4 + size) / 32)
		}
	}
	function setTiny(uint256 slot, bytes memory v) internal {
		unchecked {
			uint256 head;
			assembly { head := sload(slot) }
			uint256 size;
			assembly { size := mload(v) }
			uint256 n0 = tinySlots(head >> 224);
			uint256 n1 = tinySlots(size);
			assembly {
				// overwrite
				if gt(n1, 0) {
					sstore(slot, or(shl(224, size), shr(32, mload(add(v, 32)))))
					let ptr := add(v, 60)
					for { let i := 1 } lt(i, n1) { i := add(i, 1) } {
						sstore(add(slot, i), mload(ptr))
						ptr := add(ptr, 32)
					}
				}
				// clear unused
				for { let i := n1 } lt(i, n0) { i := add(i, 1) } {
					sstore(add(slot, i), 0)
				}
			}
		}
	}
	function getTiny(uint256 slot) internal view returns (bytes memory v) {
		unchecked {
			uint256 head;
			assembly { head := sload(slot) }
			uint256 size = head >> 224;
			if (size != 0) {
				v = new bytes(size);
				uint256 n = tinySlots(size);
				assembly {
					mstore(add(v, 32), shl(32, head))
					let p := add(v, 60)
					let i := 1
					for {} lt(i, n) {} {
						mstore(p, sload(add(slot, i)))
						p := add(p, 32)
						i := add(i, 1)
					}
				}
			}
		}
	}

}