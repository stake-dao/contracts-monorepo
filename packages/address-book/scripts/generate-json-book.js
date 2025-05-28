#!/usr/bin/env node
/**
 * generate-json-book.js
 *
 * Usage:
 *   node scripts/generate-json-book.js
 *
 * Description:
 *   Scans all .sol files in the ../src directory, extracts all address internal constant definitions from all libraries,
 *   resolves CommonUniversal placeholders, and outputs a pretty-printed JSON file at ../generated/address-book.json,
 *   structured as protocol -> network -> product/addresses.
 *   DAO and Common libraries are flattened. CommonUniversal.sol is used only for reference, not as a network in the output.
 *
 *   - Protocol and network are inferred from filenames (e.g., BalancerEthereum.sol -> protocol: balancer, network: ethereum).
 *   - For DAO and Common files, the library is flattened (addresses are placed directly under the network key).
 *   - For Common* files, any value of the form CommonUniversal.XXXX is replaced with the actual address from CommonUniversal.sol.
 *   - The script always uses ../src as input and ../generated/address-book.json as output.
 *   - The output directory is created if it does not exist.
 *   - Empty objects are kept for schema consistency.
 *   - Errors are logged with context and the script exits with a non-zero code on failure.
 */

const fs = require("node:fs");
const path = require("node:path");

const SRC_DIR = path.resolve(__dirname, "../src");
const OUTPUT_FILE = path.resolve(__dirname, "../generated/address-book.json");
const OUTPUT_DIR = path.dirname(OUTPUT_FILE);
const COMMON_UNIVERSAL_FILE = path.join(SRC_DIR, "CommonUniversal.sol");

/**
 * Recursively collects all .sol files in a directory.
 * @param {string} dir - Directory to search.
 * @returns {string[]} Array of file paths.
 */
function getSolidityFiles(dir) {
	let results = [];
	const list = fs.readdirSync(dir);
	for (const file of list) {
		const filePath = path.join(dir, file);
		const stat = fs.statSync(filePath);
		if (stat?.isDirectory()) {
			results = results.concat(getSolidityFiles(filePath));
		} else if (file.endsWith(".sol")) {
			results.push(filePath);
		}
	}
	return results;
}

/**
 * Extracts protocol and network from a Solidity filename.
 * @param {string} filename - Solidity file name.
 * @returns {{protocol: string, network: string}}
 */
function parseFileName(filename) {
	const base = path.basename(filename, ".sol");
	// Find the last uppercase letter as the start of the network
	const match = base.match(/([A-Z][a-z0-9]+)([A-Z][A-Za-z0-9]+)$/);
	if (match) {
		return { protocol: match[1], network: match[2] };
	}
	// fallback: treat everything before first uppercase as protocol, rest as network
	const idx = base.search(/[A-Z][a-z0-9]+$/);
	if (idx > 0) {
		return { protocol: base.slice(0, idx), network: base.slice(idx) };
	}
	return { protocol: base, network: "" };
}

/**
 * Parses a Solidity file's content for libraries and their address constants.
 * @param {string} content - Solidity file content.
 * @returns {Object} libraries - { [libraryName]: { [addressName]: addressValue } }
 */
function parseSolidityFile(content) {
	const libraries = {};
	// Find all library blocks
	const libRegex = /library\s+(\w+)\s*{([\s\S]*?)}\s*/g;
	let libMatch = libRegex.exec(content);
	while (libMatch !== null) {
		const libName = libMatch[1];
		const libBody = libMatch[2];
		// Find all address internal constant definitions
		const addrRegex = /address\s+internal\s+constant\s+(\w+)\s*=\s*([^;]+);/g;
		let addrMatch = addrRegex.exec(libBody);
		const addresses = {};
		while (addrMatch !== null) {
			addresses[addrMatch[1]] = addrMatch[2].trim();
			addrMatch = addrRegex.exec(libBody);
		}
		libraries[libName] = addresses;
		libMatch = libRegex.exec(content);
	}
	return libraries;
}

/**
 * Gets the product name from a library name (e.g., BalancerProtocol -> Protocol).
 * @param {string} libName - Library name.
 * @param {string} protocol - Protocol name.
 * @returns {string} Product name.
 */
function getProductName(libName, protocol) {
	if (libName.startsWith(protocol)) {
		return libName.slice(protocol.length);
	}
	return libName;
}

/**
 * Parses CommonUniversal.sol and builds a lookup table for address references.
 * @returns {Object} lookup - { [addressName]: addressValue }
 */
function getCommonUniversalLookup() {
	const content = fs.readFileSync(COMMON_UNIVERSAL_FILE, "utf8");
	const libraries = parseSolidityFile(content);
	// There should be only one library, but merge all if not
	const lookup = {};
	for (const addresses of Object.values(libraries)) {
		Object.assign(lookup, addresses);
	}
	return lookup;
}

/**
 * Replaces CommonUniversal.XXXX placeholders with actual values from the lookup table.
 * @param {Object} addresses - { [addressName]: addressValue }
 * @param {Object} commonUniversalLookup - { [addressName]: addressValue }
 * @param {string} fileName - File being processed (for error context)
 * @returns {Object} resolved - { [addressName]: resolvedAddressValue }
 */
function resolveCommonUniversalPlaceholders(
	addresses,
	commonUniversalLookup,
	fileName,
) {
	const resolved = {};
	for (const [key, value] of Object.entries(addresses)) {
		const match = value.match(/^CommonUniversal\.(\w+)$/);
		if (match) {
			const ref = match[1];
			if (!(ref in commonUniversalLookup)) {
				throw new Error(
					`[${fileName}] Reference CommonUniversal.${ref} for key '${key}' not found in CommonUniversal.sol (value: '${value}')`,
				);
			}
			resolved[key] = commonUniversalLookup[ref];
		} else {
			resolved[key] = value;
		}
	}
	return resolved;
}

/**
 * Main entry point: builds the address book JSON from Solidity files.
 * Handles error logging and process exit on failure.
 */
function main() {
	try {
		const files = getSolidityFiles(SRC_DIR);
		const result = {};
		const commonUniversalLookup = getCommonUniversalLookup();

		for (const file of files) {
			const { protocol, network } = parseFileName(file);
			// Skip CommonUniversal.sol as a network
			if (
				protocol.toLowerCase() === "common" &&
				network.toLowerCase() === "universal"
			) {
				continue;
			}
			const content = fs.readFileSync(file, "utf8");
			const libraries = parseSolidityFile(content);
			const protocolKey = protocol.toLowerCase();
			const networkKey = network.toLowerCase();
			if (!result[protocolKey]) result[protocolKey] = {};
			if (!result[protocolKey][networkKey])
				result[protocolKey][networkKey] = {};

			// Flatten DAO/Common if only library is DAO/Common
			if (
				(protocolKey === "dao" &&
					Object.keys(libraries).length === 1 &&
					Object.keys(libraries)[0].toLowerCase() === "dao") ||
				(protocolKey === "common" &&
					Object.keys(libraries).length === 1 &&
					Object.keys(libraries)[0].toLowerCase().startsWith("common"))
			) {
				let addresses = libraries[Object.keys(libraries)[0]];
				if (protocolKey === "common") {
					addresses = resolveCommonUniversalPlaceholders(
						addresses,
						commonUniversalLookup,
						file,
					);
				}
				Object.assign(result[protocolKey][networkKey], addresses);
			} else {
				for (const [libName, addresses] of Object.entries(libraries)) {
					let resolvedAddresses = addresses;
					if (protocolKey === "common") {
						resolvedAddresses = resolveCommonUniversalPlaceholders(
							addresses,
							commonUniversalLookup,
							file,
						);
					}
					const product = getProductName(libName, protocol).toLowerCase();
					result[protocolKey][networkKey][product] = resolvedAddresses;
				}
			}
		}

		// Ensure output directory exists
		if (!fs.existsSync(OUTPUT_DIR)) {
			fs.mkdirSync(OUTPUT_DIR, { recursive: true });
		}
		fs.writeFileSync(OUTPUT_FILE, JSON.stringify(result, null, 2));
		console.log(`Address book written to ${OUTPUT_FILE}`);
	} catch (err) {
		console.error("\n[ERROR]", err.message);
		if (err.stack) {
			console.error(err.stack);
		}
		process.exit(1);
	}
}

main();
