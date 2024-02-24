/// raffy.eth
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract TNSFieldMaker {

	uint8 constant KIND_FLAG_STRING    = 0x80;
	uint8 constant KIND_FLAG_NO_DECODE = 0x40;
	uint8 constant KIND_FLAG_SKIP_4    = 0x20;
	uint8 constant KIND_FLAG_ENCODED   = 0x10;

	uint8 constant KIND_TEXT = 0x01 | KIND_FLAG_STRING;
	uint8 constant KIND_COIN = 0x02 | KIND_FLAG_SKIP_4;

	function encodeTextField(string calldata name) pure external returns (bytes memory) {
		return abi.encodePacked(KIND_TEXT, name);
	}
	function encodeAddrField(string calldata name, uint256 coinType) pure external returns (bytes memory) {
		if (coinType < 0x100000000) {
			return abi.encodePacked(KIND_COIN, uint32(coinType), name);
		} else {
			return abi.encodePacked(KIND_FLAG_ENCODED, abi.encode(name, abi.encodeWithSelector(0xf1cb7e06, 0, coinType)));
		}
	}
	function encodeHexBytesSelector(string calldata name, bytes4 selector, bool raw) pure external returns (bytes memory) {
		return abi.encodePacked(KIND_FLAG_SKIP_4 | (raw ? KIND_FLAG_NO_DECODE : 0), selector, name);
	}

	// text(name)		0x816e616d65
	// text(avatar)		0x81617661746172

	// $eth				0x220000003c24657468 
	// $btc				0x220000000024627463 
	// $op				0x228000000A246F70

	// #contenthash		0x20bc1c58d123636f6e74656e7468617368
	// #pubkey			0x60c8690233237075626b6579
	// #addr			0x603b3b57de2361646472

}