// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts@4.8.2/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts@4.8.2/utils/introspection/IERC165.sol";
import {ECDSA} from "@openzeppelin/contracts@4.8.2/utils/cryptography/ECDSA.sol";
import {ENS} from "https://github.com/ensdomains/ens-contracts/blob/master/contracts/registry/ENS.sol";
import {IExtendedResolver} from "https://github.com/ensdomains/ens-contracts/blob/master/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IAddrResolver} from "https://github.com/ensdomains/ens-contracts/blob/master/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "https://github.com/ensdomains/ens-contracts/blob/master/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "https://github.com/ensdomains/ens-contracts/blob/master/contracts/resolvers/profiles/ITextResolver.sol";
import {IContentHashResolver} from "https://github.com/ensdomains/ens-contracts/blob/master/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IMulticallable} from "https://github.com/ensdomains/ens-contracts/blob/master/contracts/resolvers/IMulticallable.sol";
import {BytesUtils} from "https://github.com/ensdomains/ens-contracts/blob/master/contracts/wrapper/BytesUtils.sol";

contract L1Resolver is Ownable, IERC165, IExtendedResolver, IAddrResolver, IAddressResolver, ITextResolver, IContentHashResolver {

	function supportsInterface(bytes4 x) external pure returns (bool) {
		return x == type(IERC165).interfaceId              // 0x01ffc9a7 
			|| x == type(IExtendedResolver).interfaceId    // 0x9061b923
			|| x == type(IAddrResolver).interfaceId        // 0x3b3b57de
			|| x == type(IAddressResolver).interfaceId     // 0xf1cb7e06
			|| x == type(ITextResolver).interfaceId        // 0x59d1d43c
			|| x == type(IContentHashResolver).interfaceId // 0xbc1c58d1
			|| x == IMulticallable.multicall.selector;     // 0xac9650d8
	}

	address constant ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
	
	string public ccipURL = "https://home.antistupid.com/tkn-gateway/ccip";
	address public ccipSigner = 0xd00d726b2aD6C81E894DC6B87BE6Ce9c5572D2cd;
	mapping(bytes32 => bytes32) public aliases;

	function setURL(string calldata url) onlyOwner external {
		ccipURL = url;
	}  
	function setSigner(address signer) onlyOwner external {
		ccipSigner = signer;
	}
	function setAliasNode(bytes32 src, bytes32 dst) onlyOwner external {
		aliases[src] = dst;
	}

	function addr(bytes32 node) external view returns (address payable) {
		node = aliases[node];
		return IAddrResolver(ENS(ENS_REGISTRY).resolver(node)).addr(node);
	}
	function addr(bytes32 node, uint256 coinType) external view returns (bytes memory) {
		node = aliases[node];
		return IAddressResolver(ENS(ENS_REGISTRY).resolver(node)).addr(node, coinType);
	}
	function text(bytes32 node, string calldata key) external view returns (string memory) {
		node = aliases[node];
		return ITextResolver(ENS(ENS_REGISTRY).resolver(node)).text(node, key);
	}
	function contenthash(bytes32 node) external view returns (bytes memory) {
		node = aliases[node];
		return IContentHashResolver(ENS(ENS_REGISTRY).resolver(node)).contenthash(node);
	}

	error OffchainLookup(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData);

	function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory) {
		bytes32 alias = aliases[BytesUtils.namehash(name)];
		if (alias != 0) {
			address resolver = ENS(ENS_REGISTRY).resolver(alias);
			if (resolver != address(0)) {
				 (bool success, bytes memory v) = resolver.staticcall(data);
				 if (success) {
					return v;
				 }
			}
		}
		bytes memory encoded = abi.encodeWithSelector(IExtendedResolver.resolve.selector, name, data);
		string[] memory urls = new string[](1); 
		urls[0] = ccipURL;
		revert OffchainLookup(address(this), urls, encoded, this.resolveCallback.selector, encoded);
	}
	function resolveCallback(bytes calldata response, bytes calldata extraData) external view returns (bytes memory) {
		(bytes memory sig, uint64 expires, bytes memory result) = abi.decode(response, (bytes, uint64, bytes));
		require(expires > block.timestamp, "expired");
		bytes32 hash = keccak256(abi.encodePacked(address(this), expires, keccak256(extraData), keccak256(result)));
		address signer = ECDSA.recover(hash, sig);
		require(signer == ccipSigner, "untrusted");
		return result;
	}

	function multicall(bytes[] calldata calls) external view returns (bytes[] memory) {
		bytes memory encoded = abi.encodeWithSelector(IMulticallable.multicall.selector, calls);
		string[] memory urls = new string[](1); 
		urls[0] = ccipURL;
		revert OffchainLookup(address(this), urls, encoded, this.multicallCallback.selector, encoded);
	}
	function multicallCallback(bytes calldata response, bytes calldata extraData) external view returns (bytes[] memory) {
		(bytes memory sig, uint64 expires, bytes memory result) = abi.decode(response, (bytes, uint64, bytes));
		require(expires > block.timestamp, "expired");
		bytes32 hash = keccak256(abi.encodePacked(address(this), expires, keccak256(extraData), keccak256(result)));
		address signer = ECDSA.recover(hash, sig);
		require(signer == ccipSigner, "untrusted");		
		return abi.decode(result, (bytes[]));
	}
	
}