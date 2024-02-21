/// raffy.eth
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts@4.8.2/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts@4.8.2/utils/introspection/IERC165.sol";
import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IAddressResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/ITextResolver.sol";
import {IContentHashResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IContentHashResolver.sol";
import {BytesUtils} from "@ensdomains/ens-contracts/contracts/wrapper/BytesUtils.sol";

interface ViewMulticall {
	function multicall(bytes[] memory data) external view returns (bytes[] memory results);
}

error OffchainLookup(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData);

contract TNS is Ownable, IERC165 {
	using BytesUtils for bytes;

	function supportsInterface(bytes4 x) external pure returns (bool) {
		return x == type(IERC165).interfaceId;
	}

	address constant ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;

	bytes public basename = hex"03746b6e0365746800";

	mapping (uint256 => bytes) _fields;
	uint256 _fieldCount;
	
	struct KV {
		string k;
		string v;
	}

	event FieldsChanged();
	event BasenameChanged(bytes indexed dnsname);

	uint8 constant KIND_TEXT = 1;
	uint8 constant KIND_ADDR = 2;

	// TKN dataset docs: https://docs.tkn.xyz/developers/querying-the-tns-dataset

	// addTexts(["name","symbol","description","avatar","url","notice","decimals","twitter","github","chainID","coinType","version","tokenSupply","circulatingSupply","discord","forum","governance","snapshot","git");
	// addCoins(
	//	[".eth",".op",".arb",".avax",".bnb",".base",".cro",".ftm",".gno",".matic",".celo",".goerli",".sepolia",".holesky",".near",".sol",".trx",".zil"],
	//  [60,2147483658,2147525809,2147526762,2147483704,2147492101,2147483673,2147483898,2147483748,2147483785,2147525868,2147483643,2136328537,2147500648,397,501,195,119]
	//)

	function setBasename(bytes calldata dnsname) onlyOwner external {
		basename = dnsname;
		emit BasenameChanged(dnsname);
	}
	function addText(string[] calldata names) onlyOwner external {
		for (uint256 i; i < names.length; i += 1) {
			addField(keccak256(bytes(names[i])), abi.encodePacked(KIND_TEXT, names[i]));
		}
	}
	function addCoins(string[] calldata names, uint64[] calldata coinTypes) onlyOwner external {
		require(names.length == coinTypes.length);
		for (uint256 i; i < names.length; i += 1) {
			bytes memory v = abi.encodePacked(KIND_ADDR, coinTypes[i]);
			addField(keccak256(v), abi.encodePacked(v, names[i]));
		}
	}
	function addField(bytes32 hash, bytes memory field) internal {
		unchecked { 
			uint248 key = uint224(uint256(hash));
			if (_fields[key].length == 0) {
				uint256 last = _fieldCount;
				_fieldCount = last + 1;
				_fields[last] = abi.encodePacked(key);
			}
			_fields[key] = field;
			emit FieldsChanged();
		}
	}
	function removeFieldAt(uint256 i) onlyOwner external {
		uint256 last = _fieldCount - 1; // checked
		_fieldCount = last;
		_fields[i] = _fields[last];
		emit FieldsChanged();
	}
	function fieldNames() public view returns (string[] memory names) {
		unchecked {
			uint256 n = _fieldCount;
			names = new string[](n + 1);
			for (uint256 i; i < n; i += 1) {
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
					names[i] = string(v);
				}
			}
			names[n] = "#contenthash";
		}
	}
	function makeCalls(bytes32 node) external view returns (bytes[] memory fs) {
		unchecked {
			uint256 n = _fieldCount;
			fs = new bytes[](n + 1);
			for (uint256 i; i < n; i += 1) {
				bytes memory v = _fields[uint256(bytes32(_fields[i])) >> 8];
				if (uint8(v[0]) == KIND_TEXT) {
					assembly {
						mstore(add(v, 1), sub(mload(v), 1))
						v := add(v, 1)
					}
					fs[i] = abi.encodeCall(ITextResolver.text, (node, string(v)));
				} else { //if (uint8(v[0]) == KIND_ADDR) {
					uint256 coinType;
					assembly { coinType := mload(add(v, 9)) }
					fs[i] = abi.encodeCall(IAddressResolver.addr, (node, uint64(coinType)));
				}
			}
			fs[n] = abi.encodeCall(IContentHashResolver.contenthash, (node));
		}
	}

	function lookup(string calldata tick) external view returns (KV[] memory) {
		require(bytes(tick).length < 256, "length");
		bytes32 node0 = basename.namehash(0);
		bytes32 node = keccak256(abi.encodePacked(node0, keccak256(bytes(tick))));
		address resolver = ENS(ENS_REGISTRY).resolver(node);
		if (resolver != address(0)) return fancy(ViewMulticall(resolver).multicall(this.makeCalls(node)));
		resolver = ENS(ENS_REGISTRY).resolver(node0);
		(bool ok, bytes memory v) = resolver.staticcall(abi.encodeCall(IExtendedResolver.resolve, (
			abi.encodePacked(uint8(bytes(tick).length), tick, basename), 
			abi.encodeCall(ViewMulticall.multicall, (this.makeCalls(node)))
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
		unchecked {
			string[] memory names = fieldNames();
			require(values.length == names.length, "mod");
			uint256 n;
			kv = new KV[](values.length);
			for (uint256 i; i < values.length; i += 1) {
				bytes memory v = abi.decode(values[i], (bytes));
				if (v.length == 0) continue;
				bytes memory f = _fields[uint256(bytes32(_fields[i])) >> 8];
				kv[n] = KV(names[i], uint8(f[0]) == KIND_TEXT ? string(v) : toHex(v));
				n += 1;
			}
			assembly { mstore(kv, n) } 
		}
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

}