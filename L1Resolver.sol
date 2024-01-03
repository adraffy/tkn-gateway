// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts@4.8.2/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts@4.8.2/utils/introspection/IERC165.sol";
import {ECDSA} from "@openzeppelin/contracts@4.8.2/utils/cryptography/ECDSA.sol";
import {ENS} from "https://github.com/ensdomains/ens-contracts/blob/master/contracts/registry/ENS.sol";
import {IExtendedResolver} from "https://github.com/ensdomains/ens-contracts/blob/master/contracts/resolvers/profiles/IExtendedResolver.sol";

contract L1Resolver is Ownable, IERC165, IExtendedResolver {

	function supportsInterface(bytes4 x) external pure returns (bool) {
		return x == type(IERC165).interfaceId            // 0x01ffc9a7 
			|| x == type(IExtendedResolver).interfaceId; // 0x9061b923
	}

	string public ccipURL = "https://alpha.antistupid.com/tkn-gateway/ccip";
	address public ccipSigner = 0xd00d726b2aD6C81E894DC6B87BE6Ce9c5572D2cd;

	function setURL(string calldata url) onlyOwner external {
		ccipURL = url;
	}  
	function setSigner(address signer) onlyOwner external {
		ccipSigner = signer;
	}

	error OffchainLookup(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData);
	function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory) {
		bytes memory encoded = abi.encodeWithSelector(IExtendedResolver.resolve.selector, name, data);
		string[] memory urls = new string[](1); 
		urls[0] = ccipURL;
		revert OffchainLookup(address(this), urls, encoded, this.resolveCallback.selector, encoded);
	} 
	function resolveCallback(bytes calldata response, bytes calldata extraData) external view returns(bytes memory) {
		(bytes memory sig, uint64 expires, bytes memory result) = abi.decode(response, (bytes, uint64, bytes));
		require(expires > block.timestamp, "expired");
		bytes32 hash = keccak256(abi.encodePacked(address(this), expires, keccak256(extraData), keccak256(result)));
		address signer = ECDSA.recover(hash, sig);
		require(signer == ccipSigner, "untrusted");
		return result;
	}

}