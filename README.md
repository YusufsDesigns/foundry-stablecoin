# Foundry Stablecoin

This project is a stablecoin implementation utilizing Foundry, a fast Ethereum application toolkit written in Rust. The stablecoin's goal is to maintain a peg to $1.00 using an algorithmic stability mechanism and collateralized with crypto assets like wETH and wBTC.

## Features
- **Relative Stability**: Pegged at $1.00 with Chainlink price feeds.
- **Stability Mechanism**: Algorithmic (Decentralized) with minting restricted to collateral-backed funds.
- **Collateral**: Uses wETH and wBTC as the underlying collateral for minting stablecoins.

## Setup & Usage

### Requirements:
- [Foundry](https://book.getfoundry.sh/)
- [Forge](https://github.com/foundry-rs/foundry)
- [Anvil](https://github.com/foundry-rs/foundry)

### Install:
Clone the repository:
```bash
git clone https://github.com/YusufsDesigns/foundry-stablecoin.git
cd foundry-stablecoin
```

Install dependencies:
```bash
forge install
```

### Build & Test:
To build the contract:
```bash
forge build
```

To test the contract:
```bash
forge test
```

### Deploy:
To deploy to a network:
```bash
forge script script/YourScript.s.sol:YourScript --rpc-url <rpc_url> --private-key <your_private_key>
```

### Interact with Contracts:
Use the `cast` tool to send transactions and interact with the deployed contract.

## Documentation
For more on Foundry tools like Forge, Anvil, and Cast, check the official [Foundry Documentation](https://book.getfoundry.sh/).

## Contribution
Contributions are welcome! Please fork this repo and submit a pull request with your changes.

---

This README introduces the stablecoin system, mentions setup and usage instructions, and encourages contributions while providing relevant documentation and commands.
