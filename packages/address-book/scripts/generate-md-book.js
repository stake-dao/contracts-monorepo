#!/usr/bin/env node
/**
 * generate-md-book.js
 *
 * Usage:
 *   node scripts/generate-md-book.js
 *
 * Description:
 *   Reads generated/address-book.json and outputs a human-friendly Markdown file at generated/README.md.
 *   The Markdown file is structured by protocol, network, and product, with tables for addresses.
 *   DAO and Common sections are flattened (no product level).
 *   The script ensures the generated directory exists before writing.
 *   Auto-generated warning is included at the top.
 */

const fs = require("node:fs");
const path = require("node:path");

const JSON_FILE = path.resolve(__dirname, "../generated/address-book.json");
const MD_FILE = path.resolve(__dirname, "../generated/README.md");
const OUTPUT_DIR = path.dirname(MD_FILE);

// Mapping from normalized network names to explorer URL prefixes (ending with /address/)
const networkExplorers = {
	ethereum: "https://etherscan.io/address/",
	base: "https://basescan.org/address/",
	bsc: "https://bscscan.com/address/",
	linea: "https://lineascan.build/address/",
	polygon: "https://polygonscan.com/address/",
	fraxtal: "https://fraxscan.com/address/",
	zksync: "https://explorer.zksync.io/address/",
	arbitrum: "https://arbiscan.io/address/",
	optimism: "https://optimistic.etherscan.io/address/",
};

function capitalize(str) {
	return str.charAt(0).toUpperCase() + str.slice(1);
}

function formatTable(addresses, network) {
	const keys = Object.keys(addresses);
	if (keys.length === 0) return "_No addresses defined._\n";

	// Normalize network for lookup
	const normalizedNetwork = network.toLowerCase();
	const explorerPrefix = networkExplorers[normalizedNetwork];

	let md = "| Name | Address | Explorer |\n|------|---------|----------|\n";
	for (const key of keys) {
		const address = addresses[key];
		let explorerCell = "";
		if (explorerPrefix && address.startsWith("0x")) {
			explorerCell = `[View](${explorerPrefix}${address}#code)`;
		}
		md += `| ${key} | \`${address}\` | ${explorerCell} |\n`;
	}
	return `${md}\n`;
}

function main() {
	try {
		// Ensure output directory exists
		if (!fs.existsSync(OUTPUT_DIR))
			fs.mkdirSync(OUTPUT_DIR, { recursive: true });

		// Read the JSON data
		const data = JSON.parse(fs.readFileSync(JSON_FILE, "utf8"));

		// Write the header and auto-generated warning
		let md = "";
		md += "# Stake DAO Address Book\n\n";
		md += "> **Auto-generated file. Do not edit manually.**\n";

		// Table of Contents
		const protocols = Object.keys(data).sort();
		md += "\n## Table of Contents\n";
		for (const protocol of protocols) {
			const anchor = protocol
				.toLowerCase()
				.replace(/[^a-z0-9]+/g, "-")
				.replace(/^-+|-+$/g, "");
			md += `- [${protocol.toUpperCase()}](#${anchor})\n`;
		}

		// Iterate over the data
		for (const protocol of protocols) {
			// Write the protocol header
			md += `\n## \`${protocol.toUpperCase()}\`\n`;

			// Iterate over the networks
			const networks = Object.keys(data[protocol]).sort();
			for (const network of networks) {
				// Write the network header
				md += `\n### \`${capitalize(network)}\`\n`;

				// Get the section
				const section = data[protocol][network];

				// Flattened (DAO/Common): just a table
				if (
					protocol === "dao" ||
					protocol === "common" ||
					Object.keys(section).every(
						(k) =>
							typeof section[k] === "string" && section[k].startsWith("0x"),
					)
				) {
					// Write the table
					md += formatTable(section, network);
				} else {
					// Otherwise, iterate over the products
					const products = Object.keys(section).sort();
					for (const product of products) {
						// Write the product header
						md += `\n#### \`${capitalize(product)}\`\n`;
						md += formatTable(section[product], network);
					}
				}
			}
		}

		// Write the file
		fs.writeFileSync(MD_FILE, md);
		console.log(`Markdown address book written to ${MD_FILE}`);
	} catch (err) {
		console.error("\n[ERROR]", err.message);
		if (err.stack) {
			console.error(err.stack);
		}
		process.exit(1);
	}
}

main();
